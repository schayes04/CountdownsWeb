#!/usr/bin/env ruby
# Frozen validation of the localized Jekyll output. Run after building the site.
require 'nokogiri'
require 'optparse'
require 'pathname'
require 'uri'
require 'yaml'
require 'liquid'

class LocalizationValidator
  REQUIRED_ACCESSIBILITY_LABELS = %w[
    breadcrumb_label on_this_page app_highlights_label
    home_widgets_preview_label countdown_examples_label menu
  ].freeze
  APP_LABELS = %w[app_highlights_label home_widgets_preview_label].freeze
  ROUTE_KEYS = ['home', 'countdown-ideas', 'support'].freeze
  APPLE_ARTICLE_KEYS = %w[iphone_widgets iphone_wallpaper mac_widgets refunds].freeze

  def initialize(source:, site:, baseurl: '', verbose: false)
    @source = Pathname(source).expand_path
    @site = Pathname(site).expand_path
    @baseurl = normalize_baseurl(baseurl)
    @verbose = verbose
    @errors = Hash.new { |hash, key| hash[key] = [] }
    @documents = {}
    @counts = Hash.new(0)
  end

  def run
    validate_source
    return finish unless @locales && !@locales.empty?

    @guide_slugs = @source.glob('_guide_pages/*.md').map { |path| path.basename('.md').to_s }.sort
    @route_keys = ROUTE_KEYS + @guide_slugs
    check(:source, @guide_slugs.length == 12, "expected 12 guide slugs, found #{@guide_slugs.length}")
    check(:source, @route_keys.length == 15, "expected 15 page types, found #{@route_keys.length}")
    check(:source, @locales.length == 22, "expected 22 configured locales, found #{@locales.length}")

    @routes = @locales.flat_map { |locale| @route_keys.map { |key| route_for(locale, key) } }
    check(:routes, @routes.length == 330, "expected 330 locale routes, found #{@routes.length}")
    @routes.each { |route| validate_page(route) }
    validate_support_pages
    validate_links
    validate_policies
    validate_sitemap
    finish
  end

  private

  def check(group, condition, message)
    @errors[group] << message unless condition
  end

  def add_error(group, message)
    @errors[group] << message
  end

  def finish
    total = @errors.values.sum(&:length)
    @errors.each do |group, messages|
      next if messages.empty?

      warn "#{group}: #{messages.length} failure(s)"
      shown = @verbose ? messages : messages.first(12)
      shown.each { |message| warn "  #{message}" }
      warn "  ... #{messages.length - shown.length} more (use --verbose)" if messages.length > shown.length
    end
    puts "Checked #{@counts[:pages]}/#{@routes&.length || 0} locale pages, #{@counts[:support]} Support pages, and #{@counts[:links]} internal links."
    puts(total.zero? ? 'PASS: all localization validation checks passed.' : "FAIL: #{total} localization validation errors.")
    total.zero?
  end

  def read_yaml(path)
    YAML.safe_load(@source.join(path).read, permitted_classes: [Symbol], aliases: true) || {}
  rescue Errno::ENOENT, Psych::Exception => error
    add_error(:source, "#{path}: #{error.message.lines.first.strip}")
    {}
  end

  def parse_front_matter(path)
    text = path.read
    match = text.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    raise "missing YAML front matter" unless match

    YAML.safe_load(match[1], aliases: true) || {}
  rescue Psych::Exception => error
    raise "invalid YAML front matter: #{error.message.lines.first.strip}"
  end

  def validate_source
    @config = read_yaml('_config.yml')
    @config = {} unless @config.is_a?(Hash)
    configure_origin
    locales = read_yaml('_data/locales.yml')
    @locales = locales.is_a?(Array) ? locales : []
    @strings = read_yaml('_data/strings.yml')
    @strings = {} unless @strings.is_a?(Hash)
    @external_links = read_yaml('_data/external_links.yml')
    @external_links = {} unless @external_links.is_a?(Hash)
    @by_code = @locales.to_h { |locale| [locale['code'].to_s, locale] }
    codes = @locales.map { |locale| locale['code'].to_s }
    check(:source, codes.uniq.length == codes.length, 'locale codes must be unique')
    check(:source, @by_code.key?('en'), 'English locale is required')
    @locales.each do |locale|
      %w[code folder app_name html_lang dir].each do |key|
        check(:source, !locale[key].to_s.strip.empty? || key == 'folder', "#{locale['code']}: locales.yml #{key} is required")
      end
      check(:source, %w[ltr rtl].include?(locale['dir']), "#{locale['code']}: invalid dir #{locale['dir'].inspect}")
    end
    validate_string_catalog
    validate_apple_support_map
    validate_apple_support_include
  end

  def validate_string_catalog
    english = @strings['en']
    check(:strings, english.is_a?(Hash), 'strings.yml must include English')
    return unless english.is_a?(Hash)

    @locales.each do |locale|
      code = locale['code'].to_s
      value = @strings[code]
      check(:strings, value.is_a?(Hash), "#{code}: missing string catalog")
      next unless value.is_a?(Hash)

      compare_shape(english, value, "#{code}: strings")
      REQUIRED_ACCESSIBILITY_LABELS.each do |key|
        label = value[key]
        check(:strings, label.is_a?(String) && !label.strip.empty?, "#{code}: strings.#{key} must be nonempty")
      end
      APP_LABELS.each do |key|
        label = value[key].to_s
        check(:strings, label.scan('APP_NAME').length == 1, "#{code}: strings.#{key} must contain APP_NAME exactly once")
      end
    end
  end

  def compare_shape(expected, actual, path)
    case expected
    when Hash
      check(:strings, actual.is_a?(Hash), "#{path} must be a mapping")
      return unless actual.is_a?(Hash)
      check(:strings, actual.keys.sort == expected.keys.sort, "#{path} keys do not match English")
      (expected.keys & actual.keys).each { |key| compare_shape(expected[key], actual[key], "#{path}.#{key}") }
    when Array
      check(:strings, actual.is_a?(Array), "#{path} must be an array")
      return unless actual.is_a?(Array)
      check(:strings, actual.length == expected.length, "#{path} array size #{actual.length}, expected #{expected.length}")
      [expected.length, actual.length].min.times { |index| compare_shape(expected[index], actual[index], "#{path}[#{index}]") }
    else
      check(:strings, actual.class == expected.class, "#{path} type #{actual.class}, expected #{expected.class}")
    end
  end

  def route_for(locale, key)
    folder = locale['folder'].to_s
    path = case key
           when 'home' then folder.empty? ? '/' : "/#{folder}/"
           when 'support' then folder.empty? ? '/support' : "/#{folder}/support/"
           else
             "/#{[folder, key].reject(&:empty?).join('/')}/"
           end
    { locale: locale, code: locale['code'].to_s, key: key, path: path, file: file_for_path(path) }
  end

  def file_for_path(path)
    relative = build_path(path).sub(%r{\A/}, '')
    return @site.join('index.html') if relative.empty?
    direct = @site.join(relative)
    return direct if direct.file?
    return @site.join("#{relative}.html") if @site.join("#{relative}.html").file?

    @site.join(relative, 'index.html')
  end

  def validate_page(route)
    @counts[:pages] += 1
    path, file, locale, code, key = route.values_at(:path, :file, :locale, :code, :key)
    unless file.file?
      add_error(:routes, "#{path}: missing built file #{file}")
      return
    end
    doc = document_for(file)
    unless doc
      add_error(:routes, "#{path}: cannot parse HTML")
      return
    end
    validate_html_locale(doc, path, locale)
    validate_canonical_and_alternates(doc, path, key)
    validate_language_menu(doc, path, code, key)
    validate_footer_support(doc, path, locale)
    validate_unresolved_tokens(doc, path)
    validate_home(doc, path, code) if key == 'home'
    validate_breadcrumb(doc, path, code) if key == 'support' || @guide_slugs.include?(key)
  end

  def validate_html_locale(doc, path, locale)
    html = doc.at_css('html')
    check(:pages, html && html['lang'] == locale['html_lang'], "#{path}: html lang must be #{locale['html_lang'].inspect}")
    check(:pages, html && html['dir'] == locale['dir'], "#{path}: html dir must be #{locale['dir'].inspect}")
  end

  def validate_canonical_and_alternates(doc, path, key)
    canonical = doc.at_css('link[rel="canonical"]')&.[]('href')
    check(:pages, canonical == absolute_route(path), "#{path}: canonical must be #{absolute_route(path).inspect} (got #{canonical.inspect})")
    expected = @locales.to_h { |locale| [locale['html_lang'], route_for(locale, key)[:path]] }
    alternates = doc.css('link[rel="alternate"]').each_with_object(Hash.new { |h, k| h[k] = [] }) do |node, hash|
      hash[node['hreflang']] << node['href']
    end
    check(:pages, alternates.keys.sort == (expected.keys + ['x-default']).sort, "#{path}: alternate hreflang set is incomplete or unexpected")
    @locales.each do |locale|
      values = alternates[locale['html_lang']]
      wanted = absolute_route(route_for(locale, key)[:path])
      check(:pages, values == [wanted], "#{path}: alternate #{locale['html_lang']} must be #{wanted.inspect}")
    end
    english = absolute_route(route_for(@by_code['en'], key)[:path])
    check(:pages, alternates['x-default'] == [english], "#{path}: x-default must be #{english.inspect}")
  end

  def validate_language_menu(doc, path, code, key)
    menus = doc.css('details.language-menu')
    check(:pages, menus.length == 2, "#{path}: expected two responsive language menus")
    menus.each_with_index do |menu, index|
      validate_one_language_menu(menu, path, code, key, index + 1)
    end
    expected_menu_label = @strings.dig(code, 'menu').to_s
    summaries = doc.css('.navigation-menu > summary')
    check(:pages, summaries.length == 1, "#{path}: expected one main navigation-menu summary")
    summaries.each do |summary|
      check(:pages, summary['aria-label'].to_s == expected_menu_label, "#{path}: main navigation-menu aria-label must equal localized menu")
    end
  end

  def validate_one_language_menu(menu, path, code, key, index)
    summary = menu.at_css('summary')
    check(:pages, summary && !summary['aria-label'].to_s.strip.empty?, "#{path}: language menu #{index} summary needs a nonempty aria-label")
    links = menu.css('.language-menu__list > a')
    check(:pages, links.length == @locales.length, "#{path}: language menu #{index} must have #{@locales.length} links")
    expected_by_lang = @locales.to_h { |locale| [locale['html_lang'], locale] }
    check(:pages, links.map { |link| link['hreflang'] }.sort == expected_by_lang.keys.sort, "#{path}: language menu #{index} hreflang set is incorrect")
    links.each do |link|
      locale = expected_by_lang[link['hreflang']]
      next unless locale
      wanted = public_route(route_for(locale, key)[:path])
      check(:pages, url_path(link['href']) == wanted, "#{path}: language menu #{index} #{locale['code']} link must be #{wanted.inspect}")
      check(:pages, link['lang'] == locale['html_lang'], "#{path}: language menu #{index} #{locale['code']} lang is incorrect")
      check(:pages, link['dir'] == locale['dir'], "#{path}: language menu #{index} #{locale['code']} dir is incorrect")
    end
    current = links.select { |link| link['aria-current'] == 'page' }
    check(:pages, current.length == 1, "#{path}: language menu #{index} must have exactly one aria-current page")
    check(:pages, current.first && current.first['hreflang'] == @by_code[code]['html_lang'], "#{path}: language menu #{index} current locale is incorrect")
  end

  def validate_footer_support(doc, path, locale)
    support = doc.css('.site-footer .footerLinks a').find { |link| url_path(link['href']) == public_route(route_for(locale, 'support')[:path]) }
    check(:pages, !support.nil?, "#{path}: footer Support link is not locale-aware")
  end

  def validate_unresolved_tokens(doc, path)
    rendered = doc.to_html
    check(:pages, !rendered.include?('{{') && !rendered.include?('{%'), "#{path}: unresolved Liquid token")
    check(:pages, !rendered.match?(/\b(?:APP_NAME|TOPIC(?:_LOWER)?)\b/), "#{path}: unresolved APP_NAME or TOPIC token")
  end

  def validate_home(doc, path, code)
    strings = @strings[code] || {}
    app_name = @by_code[code]['app_name'].to_s
    { '.hero__facts' => 'app_highlights_label', '.hero__visual' => 'home_widgets_preview_label' }.each do |selector, key|
      expected = strings[key].to_s.gsub('APP_NAME', app_name)
      actual = doc.at_css(selector)&.[]('aria-label').to_s
      check(:pages, actual == expected, "#{path}: #{selector} aria-label must equal localized #{key}")
    end
    expected = strings['countdown_examples_label'].to_s
    actual = doc.at_css('.intro-band')&.[]('aria-label').to_s
    check(:pages, actual == expected, "#{path}: .intro-band aria-label must equal localized countdown_examples_label")
  end

  def validate_breadcrumb(doc, path, code)
    expected = @strings.dig(code, 'breadcrumb_label').to_s
    actual = doc.at_css('nav.breadcrumbs')&.[]('aria-label').to_s
    check(:pages, actual == expected, "#{path}: breadcrumb label must equal localized breadcrumb_label")
  end

  def validate_support_pages
    english_path = support_source_for(@by_code['en'])
    @english_support = parse_support(english_path, 'en')
    return unless @english_support
    validate_support_front_matter(@english_support, @by_code['en'], 'en')
    english_route = route_for(@by_code['en'], 'support')
    unless english_route[:file].file?
      add_error(:support, "#{english_route[:path]}: missing built English Support page")
      return
    end
    english_document = document_for(english_route[:file])
    unless english_document && prepare_english_support_baseline(english_document, english_route[:path])
      add_error(:support, 'cannot prepare English Support prose baseline') unless english_document
      return
    end
    validate_support_document(english_document, english_route[:path], @english_support)
    @locales.each do |locale|
      code = locale['code'].to_s
      next if code == 'en'
      source = support_source_for(locale)
      support = parse_support(source, code)
      next unless support
      validate_support_front_matter(support, locale, code)
      route = route_for(locale, 'support')
      next unless route[:file].file?
      doc = document_for(route[:file])
      validate_support_document(doc, route[:path], support) if doc
    end
  rescue RuntimeError, NoMethodError => error
    add_error(:support, "English Support source: #{error.message}")
  end

  def support_source_for(locale)
    return @source.join('support.md') if locale['code'].to_s == 'en'
    @source.join(locale['folder'].to_s, 'support', 'index.md')
  end

  def parse_support(path, code)
    unless path.file?
      add_error(:support, "#{code}: missing Support source #{path}")
      return nil
    end
    data = parse_front_matter(path)
    { path: path, data: data }
  rescue RuntimeError => error
    add_error(:support, "#{code}: #{path}: #{error.message}")
    nil
  end

  def validate_support_front_matter(support, locale, code)
    data = support[:data]
    expected_permalink = route_for(locale, 'support')[:path]
    check(:support, data['canonical_key'] == 'support', "#{code}: Support canonical_key must be support")
    check(:support, data['locale'] == code, "#{code}: Support locale front matter is incorrect")
    check(:support, data['permalink'] == expected_permalink, "#{code}: Support permalink must be #{expected_permalink.inspect}")
    check(:support, data['source_version'].is_a?(String) && !data['source_version'].strip.empty?, "#{code}: Support source_version must be nonempty")
    english_version = @english_support && @english_support.dig(:data, 'source_version')
    check(:support, data['source_version'] == english_version, "#{code}: Support source_version must match English") if english_version
    %w[title meta_title description intro].each do |key|
      check(:support, data[key].is_a?(String) && !data[key].strip.empty?, "#{code}: Support #{key} must be localized and nonempty")
    end
    sections = data['sections']
    check(:support, sections.is_a?(Array) && !sections.empty?, "#{code}: Support sections must be a nonempty array")
    if sections.is_a?(Array)
      sections.each_with_index do |section, index|
        check(:support, section.is_a?(Hash) && !section['id'].to_s.empty? && !section['title'].to_s.empty?, "#{code}: Support section #{index + 1} needs id and title")
      end
      english_ids = @english_section_ids || @english_support&.dig(:data, 'sections')&.map { |section| section['id'] }
      ids = sections.map { |section| section.is_a?(Hash) ? section['id'] : nil }
      check(:support, ids == english_ids, "#{code}: Support section IDs/order must match English") if english_ids
    end
  end

  def validate_support_document(doc, path, support)
    @counts[:support] += 1
    data = support[:data]
    values = {
      'title' => doc.at_css('title')&.text,
      'meta_title' => doc.at_css('meta[property="og:title"]')&.[]('content'),
      'description' => doc.at_css('meta[name="description"]')&.[]('content'),
      'og:description' => doc.at_css('meta[property="og:description"]')&.[]('content'),
      'twitter:title' => doc.at_css('meta[name="twitter:title"]')&.[]('content'),
      'twitter:description' => doc.at_css('meta[name="twitter:description"]')&.[]('content')
    }
    check(:support, values['title'] == data['meta_title'], "#{path}: built title must match Support meta_title")
    check(:support, values['meta_title'] == data['meta_title'], "#{path}: OG title must match Support meta_title")
    check(:support, values['description'] == data['description'], "#{path}: meta description must match Support description")
    check(:support, values['og:description'] == data['description'], "#{path}: OG description must match Support description")
    check(:support, values['twitter:title'] == data['meta_title'], "#{path}: Twitter title must match Support meta_title")
    check(:support, values['twitter:description'] == data['description'], "#{path}: Twitter description must match Support description")
    check(:support, doc.at_css('.resource-hero h1')&.text.to_s == data['title'], "#{path}: Support h1 must match front-matter title")
    check(:support, doc.at_css('.resource-hero p')&.text.to_s == data['intro'], "#{path}: Support intro must match front-matter intro")
    check(:support, doc.at_css('.resource-nav')&.[]('aria-label').to_s == @strings.dig(data['locale'], 'on_this_page').to_s, "#{path}: Support TOC aria-label must be localized")
    check(:support, doc.at_css('.resource-nav > p')&.text.to_s == @strings.dig(data['locale'], 'on_this_page').to_s, "#{path}: Support TOC label must be localized")
    sections = data['sections']
    return unless valid_support_sections?(sections)
    expected_sections = sections.map { |section| [section['id'], section['title']] }
    headings = doc.css('.resource-prose > h2').map { |heading| [heading['id'], comparable_text(heading.text)] }
    expected_sections = expected_sections.map { |id, title| [id, comparable_text(title)] }
    check(:support, headings == expected_sections, "#{path}: Support section IDs/order/headings must match front matter")
    toc = doc.css('.resource-nav a').map { |link| [link['href'], comparable_text(link.text)] }
    expected_toc = expected_sections.map { |id, title| ["##{id}", title] }
    check(:support, toc == expected_toc, "#{path}: Support TOC links/text must match declared sections")
    prose = doc.at_css('.resource-prose')
    check(:support, prose && !prose.text.include?('**'), "#{path}: rendered Support prose contains raw Markdown **")
    if prose && @english_prose_signature
      check(:support, prose_signature(prose) == @english_prose_signature, "#{path}: Support heading/paragraph/list structure differs from English")
      check(:support, numbered_steps(prose) == @english_numbered_steps, "#{path}: Support numbered-step count differs from English")
      check(:support, non_apple_external_hrefs(prose) == @english_non_apple_external_hrefs, "#{path}: Support non-Apple external-link multiset differs from English")
      validate_support_apple_urls(prose, data['locale'], path)
    end
  end

  def prepare_english_support_baseline(doc, path)
    data = @english_support[:data]
    version = data['source_version']
    check(:support, version.is_a?(String) && !version.strip.empty?, 'en: Support source_version must be nonempty')
    sections = data['sections']
    unless valid_support_sections?(sections)
      add_error(:support, 'en: Support sections must be a nonempty array')
      return false
    end
    prose = doc.at_css('.resource-prose')
    unless prose
      add_error(:support, "#{path}: missing English Support prose")
      return false
    end
    @english_section_ids = sections.map { |section| section.is_a?(Hash) ? section['id'] : nil }
    @english_prose_signature = prose_signature(prose)
    @english_numbered_steps = numbered_steps(prose)
    @english_non_apple_external_hrefs = non_apple_external_hrefs(prose)
    true
  end

  def prose_signature(prose)
    prose.css('h2, h3, h4, p, ul, ol, li').map do |node|
      [node.name, node.name.match?(/\Ah[234]\z/) ? node['id'].to_s.empty? : nil]
    end
  end

  def valid_support_sections?(sections)
    sections.is_a?(Array) && !sections.empty? && sections.all? do |section|
      section.is_a?(Hash) && !section['id'].to_s.empty? && !section['title'].to_s.empty?
    end
  end

  # Kramdown's smart punctuation converts straight apostrophes in Markdown headings.
  # Compare their textual meaning, while retaining exact ID and section-order checks.
  def comparable_text(value)
    value.to_s.tr("‘’‛", "'''").tr("“”", '""').strip
  end

  def numbered_steps(prose)
    prose.css('h3').count { |heading| heading.text.strip.match?(/\A\d+\./) }
  end

  def external_hrefs(prose)
    prose.css('a[href]').map { |link| link['href'] }.select { |href| external_href?(href) }.sort
  end

  def non_apple_external_hrefs(prose)
    external_hrefs(prose).reject { |href| apple_support_href?(href) }
  end

  def validate_support_apple_urls(prose, locale, path)
    actual = external_hrefs(prose).select { |href| apple_support_href?(href) }.sort
    expected = APPLE_ARTICLE_KEYS.map { |key| apple_support_url(locale, key) }.compact.sort
    check(:support, actual == expected, "#{path}: Apple Support URLs must match the locale-aware external-links map")
    return unless locale == 'ca'
    prose.css('a[href]').select { |link| link['href'].start_with?('https://support.apple.com/en-us/') }.each do |link|
      check(:support, link['hreflang'] == 'en' && !link.text.strip.empty?, "#{path}: Catalan Support must identify English-only Apple article fallbacks")
    end
  end

  def apple_support_href?(href)
    uri = URI.parse(href)
    uri.scheme == 'https' && uri.host == 'support.apple.com'
  rescue URI::InvalidURIError
    false
  end

  def validate_apple_support_map
    apple = @external_links['apple_support']
    check(:external_links, apple.is_a?(Hash), 'external_links.yml must include apple_support')
    return unless apple.is_a?(Hash)
    @apple_articles = apple['articles'].is_a?(Hash) ? apple['articles'] : {}
    @apple_locales = apple['locales'].is_a?(Hash) ? apple['locales'] : {}
    @apple_guide_overrides = apple['guide_locale_overrides'].is_a?(Hash) ? apple['guide_locale_overrides'] : {}
    check(:external_links, @apple_articles.keys.sort == APPLE_ARTICLE_KEYS.sort, 'apple_support.articles keys must match the four supported article keys')
    @apple_articles.each do |key, value|
      check(:external_links, value.is_a?(String) && value.match?(%r{\A(?:\d+|guide/[a-z0-9-]+/[a-z0-9-]+/[a-z0-9-]+)\z}), "apple_support.articles.#{key} must be a safe Apple Support path")
    end
    locale_codes = @locales.map { |locale| locale['code'].to_s }
    check(:external_links, @apple_locales.keys.sort == locale_codes.sort, 'apple_support.locales must cover exactly the configured locale codes')
    @apple_locales.each do |code, region|
      check(:external_links, locale_codes.include?(code) && region.is_a?(String) && region.match?(%r{\A[a-z]{2}(?:-[a-z]{2})?\z}), "apple_support.locales.#{code} must be a safe supported region code")
    end
    check(:external_links, (@apple_guide_overrides.keys - locale_codes).empty?, 'apple_support.guide_locale_overrides may only name configured locales')
    @apple_guide_overrides.each do |code, region|
      check(:external_links, region.is_a?(String) && (region.empty? || region.match?(%r{\A[a-z]{2}(?:-[a-z]{2})?\z})), "apple_support.guide_locale_overrides.#{code} must be empty or a safe region code")
    end
    check(:external_links, @apple_guide_overrides['en'] == '', 'apple_support.guide_locale_overrides.en must retain the unprefixed English guide route')
    check(:external_links, @apple_guide_overrides['ca'] == 'ca-es', 'apple_support.guide_locale_overrides.ca must retain the Catalan Mac guide route')
  end

  def apple_support_url(locale, key)
    code = @apple_locales&.key?(locale.to_s) ? locale.to_s : 'en'
    region = @apple_locales&.[](code)
    region = @apple_guide_overrides[code] if key == 'mac_widgets' && @apple_guide_overrides&.key?(code)
    path = @apple_articles&.[](key)
    return nil unless region.is_a?(String) && path.is_a?(String)
    "https://support.apple.com/#{region.empty? ? '' : "#{region}/"}#{path}"
  end

  def validate_apple_support_include
    cases = [
      ['explicit English article', 'en', 'en', 'iphone_widgets', 'https://support.apple.com/en-us/118610'],
      ['no locale fallback', nil, nil, 'iphone_widgets', 'https://support.apple.com/en-us/118610'],
      ['page-locale default', nil, 'fr', 'refunds', 'https://support.apple.com/fr-fr/118223'],
      ['empty locale fallback', '', 'de', 'iphone_widgets', 'https://support.apple.com/de-de/118610'],
      ['unknown locale fallback', 'unknown', 'fr', 'iphone_wallpaper', 'https://support.apple.com/en-us/102638'],
      ['unknown article key', 'fr', 'fr', 'unknown', ''],
      ['Catalan article fallback', 'ca', 'ca', 'iphone_widgets', 'https://support.apple.com/en-us/118610'],
      ['Catalan Mac guide override', 'ca', 'ca', 'mac_widgets', 'https://support.apple.com/ca-es/guide/mac-help/mchl52be5da5/mac'],
      ['unprefixed English Mac guide', 'en', 'en', 'mac_widgets', 'https://support.apple.com/guide/mac-help/mchl52be5da5/mac'],
      ['Norwegian Bokmål', 'nb', 'nb', 'refunds', 'https://support.apple.com/no-no/118223'],
      ['Portuguese', 'pt', 'pt', 'iphone_widgets', 'https://support.apple.com/pt-pt/118610'],
      ['Brazilian Portuguese', 'pt-BR', 'pt-BR', 'iphone_widgets', 'https://support.apple.com/pt-br/118610'],
      ['Simplified Chinese', 'zh-Hans', 'zh-Hans', 'iphone_widgets', 'https://support.apple.com/zh-cn/118610'],
      ['Traditional Chinese', 'zh-Hant', 'zh-Hant', 'iphone_widgets', 'https://support.apple.com/zh-tw/118610']
    ]
    cases.each do |label, include_locale, page_locale, key, expected|
      actual = render_apple_support_include(include_locale, page_locale, key)
      check(:liquid, actual == expected, "apple-support-url #{label}: #{actual.inspect}, expected #{expected.inspect}")
    end
  end

  def render_apple_support_include(include_locale, page_locale, key)
    payload = { 'site' => { 'data' => { 'external_links' => @external_links } }, 'page' => { 'locale' => page_locale }, 'include' => { 'key' => key } }
    payload['include']['locale'] = include_locale unless include_locale.nil?
    Liquid::Template.parse(@source.join('_includes/apple-support-url.html').read).render!(payload).strip
  rescue StandardError => error
    add_error(:liquid, "apple-support-url rendering failed: #{error.class}: #{error.message}")
    ''
  end

  def validate_links
    @routes.each do |route|
      next unless route[:file].file?
      doc = document_for(route[:file])
      next unless doc
      validate_document_internal_links(route[:path], doc)
    end
    policy_file = [@site.join('policies.html'), @site.join('policies', 'index.html')].find(&:file?)
    validate_document_internal_links('/policies', document_for(policy_file)) if policy_file
  end

  def validate_document_internal_links(path, doc)
    doc.css('a[href]').each do |link|
      href = link['href'].to_s
      next if href.empty? || external_href?(href) || href.start_with?('javascript:', 'data:')
      @counts[:links] += 1
      validate_internal_link(path, href)
    end
  end

  def validate_internal_link(from_path, href)
    uri = URI.parse(href)
    path = uri.path.to_s
    target_path = if path.empty?
                    from_path
                  elsif path.start_with?('/')
                    path
                  else
                    File.join(File.dirname(from_path.end_with?('/') ? "#{from_path}index.html" : from_path), path)
                  end
    target_path = normalize_path(target_path)
    file = file_for_path(target_path)
    unless file.file?
      add_error(:links, "#{from_path}: internal link #{href.inspect} does not resolve")
      return
    end
    return if uri.fragment.to_s.empty?
    target = document_for(file)
    check(:links, target && target.at_css("##{css_escape(uri.fragment)}"), "#{from_path}: fragment #{href.inspect} does not resolve")
  rescue URI::InvalidURIError
    add_error(:links, "#{from_path}: invalid internal URL #{href.inspect}")
  end

  def validate_policies
    policy_source = @source.join('policies.md')
    check(:policies, policy_source.file?, 'missing policies.md')
    if policy_source.file?
      policy = parse_front_matter(policy_source)
      check(:policies, policy['locale'] == 'en', 'policies.md must remain English')
      check(:policies, policy['localized'] == false, 'policies.md must retain localized: false')
    end
    translated_sources = @locales.reject { |locale| locale['code'].to_s == 'en' }.flat_map do |locale|
      folder = locale['folder'].to_s
      %W[policies.md policies.html policies/index.md policies/index.html].map { |relative| @source.join(folder, relative) }
    end.select(&:file?)
    check(:policies, translated_sources.empty?, "localized policy sources are forbidden: #{translated_sources.join(', ')}")
    file = [@site.join('policies.html'), @site.join('policies', 'index.html')].find(&:file?)
    check(:policies, !file.nil?, 'missing built English policies route')
    return unless file
    doc = document_for(file)
    check(:policies, doc.at_css('details.language-menu').nil?, 'policies must not render a language menu')
    check(:policies, doc.css('link[rel="alternate"]').empty?, 'policies must not render alternate hreflang links')
  rescue RuntimeError => error
    add_error(:policies, error.message)
  end

  def validate_sitemap
    path = @site.join('sitemap.xml')
    check(:sitemap, path.file?, 'missing sitemap.xml')
    return unless path.file?
    xml = Nokogiri::XML(path.read)
    locs = xml.xpath('//*[local-name()="loc"]').map(&:text)
    routes = locs.map { |loc| url_path(loc) }
    duplicates = routes.group_by(&:itself).select { |_route, values| values.length > 1 }.keys
    check(:sitemap, duplicates.empty?, "sitemap has duplicate URLs: #{duplicates.join(', ')}")
    expected = @routes.map { |route| public_route(route[:path]) }
    missing = expected - routes
    check(:sitemap, missing.empty?, "sitemap is missing locale routes: #{missing.join(', ')}")
    check(:sitemap, routes.include?(public_route('/policies')), 'sitemap is missing English /policies')
    folders = @locales.map { |locale| locale['folder'].to_s }.reject(&:empty?)
    translated = routes.select { |route| folders.any? { |folder| route.match?(%r{\A#{Regexp.escape(public_route("/#{folder}/policies/"))}\z}) || route.match?(%r{\A#{Regexp.escape(public_route("/#{folder}/policies"))}\z}) } }
    check(:sitemap, translated.empty?, "sitemap must not contain translated policy URLs: #{translated.join(', ')}")
  end

  def document_for(file)
    @documents[file.to_s] ||= Nokogiri::HTML(file.read)
  rescue SystemCallError
    nil
  end

  def external_href?(href)
    uri = URI.parse(href)
    return true if %w[mailto tel].include?(uri.scheme)
    return false unless uri.scheme
    uri.host != @origin.host || uri.scheme != @origin.scheme || uri.port != @origin.port
  rescue URI::InvalidURIError
    false
  end

  def configure_origin
    @origin = URI.parse(@config['url'].to_s)
    valid = @origin.is_a?(URI::HTTP) && !@origin.host.to_s.empty?
    check(:source, valid, '_config.yml url must be an absolute HTTP(S) origin')
    @origin = URI.parse('https://invalid.local') unless valid
  rescue URI::InvalidURIError
    add_error(:source, '_config.yml url must be an absolute HTTP(S) origin')
    @origin = URI.parse('https://invalid.local')
  end

  def url_path(url)
    return '' if url.nil?
    URI.parse(url).path.to_s.then { |path| normalize_path(path) }
  rescue URI::InvalidURIError
    ''
  end

  def normalize_path(path)
    value = path.to_s.empty? ? '/' : path.to_s
    trailing_slash = value.end_with?('/')
    normalized = Pathname.new(value).cleanpath.to_s
    normalized = "/#{normalized}" unless normalized.start_with?('/')
    normalized = '/' if normalized == '/.'
    normalized += '/' if trailing_slash && normalized != '/' && !normalized.end_with?('/')
    normalized
  end

  def normalize_baseurl(baseurl)
    value = baseurl.to_s.strip
    return '' if value.empty? || value == '/'
    "/#{value.sub(%r{\A/+}, '').sub(%r{/+\z}, '')}"
  end

  def build_path(path)
    value = normalize_path(path)
    return value if @baseurl.empty?
    value.start_with?("#{@baseurl}/") ? value.delete_prefix(@baseurl) : value
  end

  def public_route(path)
    value = normalize_path(path)
    return value if @baseurl.empty?
    "#{@baseurl}#{value}"
  end

  def absolute_route(path)
    "#{@origin.to_s.sub(%r{/+\z}, '')}#{public_route(path)}"
  end

  def css_escape(value)
    value.to_s.gsub(/([^a-zA-Z0-9_-])/) { |char| "\\\\#{char.ord.to_s(16)} " }
  end
end

if $PROGRAM_NAME == __FILE__
  options = { source: Dir.pwd, baseurl: '', verbose: false }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: validate-localization.rb [options]'
    opts.on('--source PATH', 'Project source (default: current directory)') { |value| options[:source] = value }
    opts.on('--site PATH', 'Built site (default: SOURCE/_site)') { |value| options[:site] = value }
    opts.on('--baseurl PATH', 'Site baseurl (default: empty)') { |value| options[:baseurl] = value }
    opts.on('--verbose', 'Show every validation failure') { options[:verbose] = true }
  end
  parser.parse!
  options[:site] ||= File.join(options[:source], '_site')
  validator = LocalizationValidator.new(**options)
  exit(validator.run ? 0 : 1)
end
