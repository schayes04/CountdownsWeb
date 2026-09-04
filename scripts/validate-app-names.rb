#!/usr/bin/env ruby
# Run after Jekyll: bundle exec ruby scripts/validate-app-names.rb --site /path/to/build
require 'json'
require 'jekyll'
require 'nokogiri'
require 'optparse'
require 'pathname'
require 'yaml'

class AppNameValidator
  # Native CFBundleDisplayName baseline; update together with locales.yml.
  EXPECTED = {
    'en' => 'Countdowns', 'ar' => 'العدادات التنازلية', 'ca' => 'Comptes Enrere',
    'da' => 'Nedtællinger', 'de' => 'Countdowns', 'es' => 'Cuentas atrás',
    'fi' => 'Laskurit', 'fr' => 'Compte à rebours', 'it' => 'Contatore',
    'ja' => 'カウントダウン', 'ko' => '카운트다운', 'nb' => 'Nedtellinger',
    'nl' => 'Aftellingen', 'pl' => 'Odliczanie', 'pt' => 'Contagem',
    'pt-BR' => 'Contagens', 'ru' => 'Таймеры', 'sk' => 'Odpočty',
    'sv' => 'Nedräkningar', 'tr' => 'Geri Sayım', 'zh-Hans' => '时光仪',
    'zh-Hant' => '倒數日'
  }.freeze
  BRAND_FIELDS = %w[app_description pricing_heading ideas_index_body guide_body_p1 guide_cta_text].freeze
  ROUTES = %w[countdown-ideas support].freeze

  def initialize(source:, site:, native_catalog: nil, verbose: false)
    @source, @site = Pathname(source).expand_path, Pathname(site).expand_path
    @native_catalog, @verbose = native_catalog && Pathname(native_catalog).expand_path, verbose
    @errors, @counts = Hash.new { |h, k| h[k] = [] }, Hash.new(0)
  end

  def check(group, condition, message)
    @errors[group] << message unless condition
  end

  def read_yaml(path)
    YAML.safe_load(@source.join(path).read, permitted_classes: [Symbol]) || {}
  rescue Errno::ENOENT, Psych::Exception => error
    check(:source, false, "#{path}: #{error.message.lines.first.strip}")
    {}
  end

  def mapping(value)
    value.is_a?(Hash) ? value : {}
  end

  def validate_source
    data = read_yaml('_data/locales.yml')
    @locales = data.is_a?(Array) ? data : []
    @strings = mapping(read_yaml('_data/strings.yml'))
    @screenshot_alts = mapping(read_yaml('_data/screenshot_alts.yml'))
    codes = @locales.map { |locale| locale['code'].to_s }
    check(:source, codes.sort == EXPECTED.keys.sort, 'locales.yml codes must exactly match the expected app-name map')
    check(:source, codes.uniq.size == codes.size, 'locales.yml codes must be unique')
    @locales.each do |locale|
      code, expected = locale['code'].to_s, EXPECTED[locale['code'].to_s]
      check(:source, expected, "#{code}: locale is not in the expected app-name map")
      check(:source, locale['app_name'].to_s == expected, "#{code}: app_name must be #{expected.inspect}")
      check(:source, !locale['app_name'].to_s.strip.empty?, "#{code}: app_name is empty")
      validate_strings(code, expected)
      validate_screenshot_alts(code, expected)
    end
    validate_native_catalog if @native_catalog
  end

  def validate_strings(code, expected)
    return unless expected
    strings = mapping(@strings[code])
    BRAND_FIELDS.each do |field|
      value = strings[field]
      check(:strings, value.is_a?(String) && value.include?(expected), "#{code}: strings.#{field} must contain #{expected.inspect}")
      check(:strings, !value.to_s.include?('Countdowns'), "#{code}: strings.#{field} still contains stale Countdowns") unless expected == 'Countdowns'
    end
    answers = strings['faq_answers']
    value = answers.is_a?(Array) ? answers[1] : nil
    check(:strings, value.is_a?(String) && value.include?(expected), "#{code}: strings.faq_answers[1] must contain #{expected.inspect}")
    check(:strings, !value.to_s.include?('Countdowns'), "#{code}: strings.faq_answers[1] still contains stale Countdowns") unless expected == 'Countdowns'
  end

  def validate_screenshot_alts(code, expected)
    return unless expected
    values = mapping(@screenshot_alts[code]).values.select { |value| value.is_a?(String) }
    check(:strings, !values.empty?, "#{code}: screenshot alt catalog is empty")
    values.each_with_index do |value, index|
      check(:strings, value.include?(expected), "#{code}: screenshot alt #{index + 1} must contain #{expected.inspect}")
      check(:strings, !value.include?('Countdowns'), "#{code}: screenshot alt #{index + 1} still contains stale Countdowns") unless expected == 'Countdowns'
    end
  end

  def validate_native_catalog
    valid = @native_catalog.file? && @native_catalog.extname == '.xcstrings'
    check(:native, valid, "native catalog must be an existing .xcstrings file: #{@native_catalog}")
    return unless valid
    values = native_values(@native_catalog)
    EXPECTED.each do |code, expected|
      found = values.find { |locale, _| locale == code }&.last
      check(:native, found == expected, "#{code}: native CFBundleDisplayName #{found.inspect}, expected #{expected.inspect}")
    end
  rescue JSON::ParserError, SystemCallError, TypeError, NoMethodError => error
    check(:native, false, "cannot read native catalog: #{error.message}")
  end

  def native_values(file)
    json = JSON.parse(file.read)
    localizations = json.dig('strings', 'CFBundleDisplayName', 'localizations') || {}
    localizations.each_with_object([]) do |(locale, data), result|
      value = data.dig('stringUnit', 'value')
      result << [locale, value] if value
    end
  end

  def validate_route(locale, slug)
    code, expected = locale['code'], EXPECTED[locale['code']]
    route = '/' + [locale['folder'], slug].reject { |part| part.to_s.empty? }.join('/')
    route += '/' unless route.end_with?('/')
    file = slug.to_s.empty? ? @site.join(locale['folder'].to_s, 'index.html') : @site.join(locale['folder'].to_s, slug.to_s, 'index.html')
    if code == 'en' && slug == 'support'
      route = '/support'
      file = @site.join('support.html')
    end
    @counts[:routes] += 1
    unless file.file?
      check(:routes, false, "Missing built route: #{route}")
      return
    end
    @counts[:html] += 1
    # The English ideas index does not opt into SoftwareApplication structured data.
    schema_required = slug != 'support' && (code != 'en' || slug != 'countdown-ideas')
    validate_document(Nokogiri::HTML(file.read), route, code, expected, homepage: slug.to_s.empty?, guide: @guides.include?(slug), schema_required: schema_required)
  end

  def validate_document(doc, route, code, expected, homepage:, guide: false, schema_required: false)
    header, footer = doc.css('.site-header .site-brand'), doc.css('.site-footer .site-brand')
    [header, footer].each_with_index do |brands, index|
      label = index.zero? ? 'header' : 'footer'
      check(:surfaces, brands.size == 1, "#{route}: expected one #{label} brand")
      next unless brands.size == 1
      check(:surfaces, brands.first.at_css('span')&.text.to_s.strip == expected, "#{route}: #{label} brand name mismatch")
      check(:surfaces, brands.first['aria-label'].to_s.start_with?("#{expected} "), "#{route}: #{label} brand aria-label lacks localized name")
    end
    schemas, software_schemas = doc.css('script[type="application/ld+json"]'), []
    schemas.each do |script|
      json = JSON.parse(script.text)
      next unless json.is_a?(Hash) && json['@type'] == 'SoftwareApplication'
      software_schemas << json
      check(:metadata, json['name'] == expected, "#{route}: SoftwareApplication name #{json['name'].inspect}, expected #{expected.inspect}")
    rescue JSON::ParserError => error
      check(:metadata, false, "#{route}: invalid JSON-LD: #{error.message}")
    end
    check(:metadata, software_schemas.size == 1, "#{route}: expected exactly one SoftwareApplication JSON-LD block") if schema_required
    if homepage
      check(:surfaces, doc.at_css('h1')&.text.to_s.strip == expected, "#{route}: homepage h1 mismatch")
      { '.hero__facts' => 'app_highlights_label', '.hero__visual' => 'home_widgets_preview_label' }.each do |selector, key|
        label = @strings.dig(code, key).to_s.gsub('APP_NAME', expected)
        check(:surfaces, label.include?(expected) && doc.at_css(selector)&.[]('aria-label').to_s == label, "#{route}: #{selector} aria-label must use the translated label and app name")
      end
      %w[title meta[property="og:title"] meta[name="twitter:title"]].each do |selector|
        value = selector == 'title' ? doc.at_css(selector)&.text : doc.at_css(selector)&.[]('content')
        check(:metadata, value.to_s.include?(expected), "#{route}: #{selector} lacks localized app name")
      end
    end
    doc.css('.screenshot-phone img').each_with_index do |image, index|
      alt = image['alt'].to_s
      check(:surfaces, alt.empty? || alt.include?(expected), "#{route}: screenshot #{index + 1} alt lacks localized app name")
    end
    if guide
      asides = doc.css('.guide-aside')
      check(:surfaces, asides.size == 1, "#{route}: expected one guide app sidebar")
      if asides.size == 1
        check(:surfaces, asides.first.at_css('h2')&.text.to_s.strip == expected, "#{route}: guide sidebar name mismatch")
        check(:surfaces, asides.first['aria-label'].to_s == expected || asides.first['aria-label'].to_s.start_with?("#{expected} "), "#{route}: guide sidebar aria-label mismatch")
      end
    end
    reject_stale_brand(doc, route, expected) unless %w[en de nl].include?(code)
  rescue SystemCallError => error
    check(:routes, false, "#{route}: cannot read built HTML: #{error.message}")
  end

  def reject_stale_brand(doc, route, expected)
    stale = []
    stale << 'body text' if doc.at_css('body')&.text.to_s.include?('Countdowns')
    stale += doc.css('[aria-label], [alt], title').filter_map { |node| node.text.include?('Countdowns') || node['aria-label'].to_s.include?('Countdowns') || node['alt'].to_s.include?('Countdowns') ? node.name : nil }
    stale += doc.css('meta[name="description"], meta[property="og:title"], meta[property="og:description"], meta[name="twitter:title"], meta[name="twitter:description"]').filter_map { |node| node['content'].to_s.include?('Countdowns') ? node['property'] || node['name'] : nil }
    stale += doc.css('script[type="application/ld+json"]').filter_map { |node| node.text.include?('Countdowns') ? 'JSON-LD' : nil }
    check(:stale, stale.empty?, "#{route}: stale Countdowns in #{stale.uniq.join(', ')}; expected #{expected.inspect}")
  end

  def validate_liquid_fallbacks
    fallback_name = 'Fallback & "Name" <test>'
    cases = [
      ['unknown locale', { 'locale' => 'xx' }, @locales, fallback_name],
      ['absent page locale', {}, @locales, EXPECTED['en']],
      ['absent locale app_name', { 'locale' => 'fr' }, locales_with_app_name(nil), fallback_name],
      ['empty locale app_name', { 'locale' => 'fr' }, locales_with_app_name(''), fallback_name]
    ]
    cases.each do |label, page, locales, expected|
      %w[header.html footer.html].each do |name|
        assert_fallback_brand("#{label} #{name}", render_include("_includes/#{name}", page, locales: locales, app_name: fallback_name), expected)
      end
      head = render_include('_includes/head.html', page.merge('layout' => 'home', 'url' => '/', 'include_software_schema' => true), locales: locales, app_name: fallback_name)
      assert_fallback_head("#{label} head", head, expected)
    rescue StandardError => error
      check(:liquid, false, "Liquid #{label} fallback failed: #{error.class}: #{error.message}")
    end
  end

  def locales_with_app_name(value)
    locales = Marshal.load(Marshal.dump(@locales))
    locale = locales.find { |entry| entry['code'] == 'fr' }
    if locale
      value.nil? ? locale.delete('app_name') : locale['app_name'] = value
    end
    locales
  end

  def assert_fallback_brand(label, html, expected)
    @counts[:renders] += 1
    doc = Nokogiri::HTML.fragment(html)
    brands = doc.css('.site-brand')
    check(:liquid, brands.size == 1, "Liquid #{label}: expected one site brand")
    return unless brands.size == 1
    check(:liquid, brands.first.at_css('span')&.text.to_s.strip == expected, "Liquid #{label}: brand span fallback mismatch")
    check(:liquid, brands.first['aria-label'].to_s.start_with?("#{expected} "), "Liquid #{label}: brand aria-label fallback mismatch")
    if expected.match?(/[&"<>]/)
      check(:liquid, %w[&amp; &quot; &lt; &gt;].all? { |entity| html.include?(entity) }, "Liquid #{label}: special fallback name was not escaped")
    end
  end

  def assert_fallback_head(label, html, expected)
    @counts[:renders] += 1
    doc = Nokogiri::HTML(html)
    check(:liquid, doc.at_css('title')&.text.to_s.include?(expected), "Liquid #{label}: title fallback mismatch")
    schemas = doc.css('script[type="application/ld+json"]').each_with_object([]) do |script, result|
      begin
        json = JSON.parse(script.text)
        result << json if json.is_a?(Hash) && json['@type'] == 'SoftwareApplication'
      rescue JSON::ParserError
        next
      end
    end
    check(:liquid, schemas.size == 1, "Liquid #{label}: expected one SoftwareApplication schema")
    check(:liquid, schemas.first && schemas.first['name'] == expected, "Liquid #{label}: JSON-LD name fallback mismatch")
  end

  def render_include(path, page, locales: @locales, app_name: 'Countdowns')
    config = Jekyll.configuration('source' => @source.to_s, 'quiet' => true)
    site = Jekyll::Site.new(config)
    payload = { 'site' => { 'data' => { 'locales' => locales, 'strings' => @strings, 'screenshots' => { 'locales' => {} } },
                            'app_name' => app_name, 'page_title' => app_name, 'app_icon' => 'assets/appicon.png',
                            'app_description' => app_name, 'appstore_link' => 'https://example.test/app' }, 'page' => page }
    Liquid::Template.parse(@source.join(path).read).render!(payload, registers: { site: site })
  end

  def run
    @guides = @source.glob('_guide_pages/*.md').map { |path| path.basename('.md').to_s }.sort
    validate_source
    routes = ['', *ROUTES, *@guides]
    check(:source, routes.size == 15, "Expected 12 guide pages plus home, ideas, and support (found #{@guides.size} guides)")
    check(:routes, @locales.size * routes.size == 330, "Expected 330 locale routes (found #{@locales.size * routes.size})")
    @locales.each { |locale| routes.each { |slug| validate_route(locale, slug) } }
    %w[policies].each do |name|
      file = [@site.join("#{name}.html"), @site.join(name, 'index.html')].find(&:file?)
      check(:routes, file, "Missing English resource route: /#{name}/")
      validate_document(Nokogiri::HTML(file.read), "/#{name}/", 'en', EXPECTED['en'], homepage: false) if file
    end
    validate_liquid_fallbacks
    puts "Checked #{EXPECTED.size} app names, #{@counts[:html]}/#{@counts[:routes]} locale routes, and #{@counts[:renders]} fallback/escaping renders."
    @errors.each do |group, errors|
      next if errors.empty?

      warn "#{group}: #{errors.size} failure(s)"
      (@verbose ? errors : errors.first(12)).each { |error| warn "  #{error}" }
      warn "  ... #{errors.size - 12} more (use --verbose)" if !@verbose && errors.size > 12
    end
    total = @errors.values.sum(&:size)
    puts(total.zero? ? 'PASS: all app-name validation checks passed.' : "FAIL: #{total} app-name validation errors.")
    total.zero?
  end
end

if $PROGRAM_NAME == __FILE__
  options = { source: File.expand_path('..', __dir__) }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: bundle exec ruby scripts/validate-app-names.rb [--site BUILD_DIR] [--source SOURCE_DIR] [--native-catalog PATH] [--verbose]'
    opts.on('--site PATH', 'Built Jekyll directory (default: SOURCE/_site)') { |v| options[:site] = v }
    opts.on('--source PATH', 'Source root (default: repository root)') { |v| options[:source] = v }
    opts.on('--native-catalog PATH', 'Optional CFBundleDisplayName .xcstrings file') { |v| options[:native_catalog] = v }
    opts.on('--verbose', 'Print every failure') { options[:verbose] = true }
    opts.on('-h', '--help', 'Show usage') { puts opts; exit }
  end
  parser.parse!
  abort(parser.to_s) unless ARGV.empty?
  options[:site] ||= File.join(options[:source], '_site')
  exit(AppNameValidator.new(**options).run ? 0 : 1)
end
