#!/usr/bin/env ruby
# Run after Jekyll: bundle exec ruby scripts/validate-app-store-badges.rb --site /path/to/build
require 'digest'
require 'jekyll'
require 'nokogiri'
require 'optparse'
require 'pathname'
require 'yaml'

class AppStoreBadgeValidator
  def initialize(source:, site:, baseurl: nil, verbose: false)
    @source = Pathname(source).expand_path
    @site = Pathname(site).expand_path
    @verbose = verbose
    @errors = Hash.new { |hash, key| hash[key] = [] }
    @counts = Hash.new(0)
    @baseurl = (baseurl || read_yaml('_config.yml')['baseurl']).to_s.sub(%r{/+$}, '')
  end

  def check(group, condition, message)
    @errors[group] << message unless condition
  end

  def read_yaml(path)
    YAML.safe_load(@source.join(path).read, permitted_classes: [Symbol]) || {}
  rescue Errno::ENOENT, Psych::Exception => error
    check(:manifest, false, "#{path}: #{error.message.lines.first.strip}")
    {}
  end

  def mapping(value)
    value.is_a?(Hash) ? value : {}
  end

  def validate_manifest
    @manifest = mapping(read_yaml('_data/app_store_badges.yml'))
    locale_data = read_yaml('_data/locales.yml')
    @locales = locale_data.is_a?(Array) ? locale_data : []
    codes = @locales.map { |locale| locale['code'] }
    check(:manifest, @manifest.keys.sort == codes.sort, 'Badge map keys must exactly match locales.yml codes')
    check(:manifest, codes.uniq.size == codes.size, 'Locale codes must be unique')
    hints = app_store_language_hints
    check(:manifest, hints.keys.sort == codes.sort, 'App Store language-hint keys must exactly match locales.yml codes')
    check(:manifest, hints.values.all? { |hint| !hint.to_s.empty? }, 'App Store language hints must not be empty')

    contents = {}
    @manifest.each do |code, entry|
      entry = mapping(entry)
      file = entry['file'].to_s
      path = @source.join('assets/app-store-badges', file)
      check(:manifest, !file.empty?, "#{code}: missing badge filename")
      check(:sources, path.file?, "#{code}: missing SVG #{path}")
      next unless path.file?

      bytes = path.binread
      digest = Digest::SHA256.hexdigest(bytes)
      if contents.key?(digest)
        check(:sources, false, "#{code}: #{file} duplicates #{contents[digest]}")
      end
      contents[digest] = file
      @counts[:sources] += 1
      validate_svg(path, entry, code)
    rescue SystemCallError => error
      check(:sources, false, "#{code}: cannot read #{path}: #{error.message}")
    end
  end

  def validate_svg(path, entry, code)
    doc = Nokogiri::XML(path.read) { |config| config.strict.nonet }
    root = doc.at_xpath('/*[local-name()="svg"]')
    check(:sources, root, "#{code}: #{path.basename} has no SVG root")
    return unless root

    width = root['width'].to_s[/[-+]?\d*\.?\d+/]&.to_f
    height = root['height'].to_s[/[-+]?\d*\.?\d+/]&.to_f
    viewbox = root['viewBox'].to_s.split.map(&:to_f)
    check(:sources, width && viewbox.size == 4, "#{code}: #{path.basename} must declare width and viewBox")
    if width && viewbox.size == 4
      check(:sources, width.round == entry['width'].to_i && viewbox[2].round == entry['width'].to_i,
            "#{code}: #{path.basename} width/viewBox #{width}/#{viewbox[2]} does not round to #{entry['width']}")
    end
    check(:sources, height && height.round == 40, "#{code}: #{path.basename} height must round to 40")
  rescue Nokogiri::XML::SyntaxError => error
    check(:sources, false, "#{code}: invalid SVG #{path.basename}: #{error.message.lines.first.strip}")
  end

  def expected_path(locale)
    entry = mapping(@manifest[locale['code']])
    "/assets/app-store-badges/#{entry['file']}"
  end

  def app_store_language_hints
    mapping(mapping(@external_links['app_store'])['language_hints'])
  end

  def expected_app_store_href(locale_code, appstore_link: @config_appstore_link)
    appstore_link = appstore_link.to_s
    canonical_link = "https://apps.apple.com/app/apple-store/id#{@ios_app_id}"
    return appstore_link unless appstore_link == canonical_link

    hints = app_store_language_hints
    hint = hints[locale_code.to_s]
    hint = hints['en'] if hint.to_s.empty?
    "#{appstore_link}?l=#{hint}"
  end

  def validate_route(locale, slug)
    @counts[:routes] += 1
    route = '/' + [locale['folder'], slug].reject { |part| part.to_s.empty? }.join('/')
    route += '/' unless route.end_with?('/')
    file = @site.join(route.delete_prefix('/'), 'index.html')
    unless file.file?
      check(:routes, false, "Missing built route: #{route}")
      return
    end
    @counts[:html] += 1
    doc = Nokogiri::HTML(file.read)
    links = doc.css('a.app-store-badge')
    check(:routes, links.size == 2, "#{route}: expected exactly 2 .app-store-badge links, found #{links.size}")
    expected_href = expected_app_store_href(locale['code'])
    expected_label = localized_label(locale['code'])
    expected_src = @baseurl + expected_path(locale)
    links.each_with_index do |link, index|
      label = link['aria-label']
      check(:routes, link['href'] == expected_href, "#{route}: badge #{index + 1} href #{link['href'].inspect}, expected #{expected_href.inspect}")
      check(:routes, label == expected_label, "#{route}: badge #{index + 1} aria-label does not match localized label")
      image = link.at_css('img')
      check(:routes, image, "#{route}: badge #{index + 1} is missing img")
      next unless image

      check(:routes, image['src'] == expected_src, "#{route}: badge #{index + 1} src #{image['src'].inspect}, expected #{expected_src.inspect}")
      check(:routes, image['alt'] == expected_label, "#{route}: badge #{index + 1} alt does not match localized label")
      entry = mapping(@manifest[locale['code']])
      check(:routes, image['width'] == entry['width'].to_i.to_s && image['height'] == '40', "#{route}: badge #{index + 1} has incorrect dimensions")
      check(:built_files, @site.join(expected_src.delete_prefix(@baseurl).delete_prefix('/')).file?, "#{route}: missing built badge #{expected_src}")
    end
  end

  def localized_label(code)
    strings = mapping(@strings[code])
    strings['download_badge'].to_s.empty? ? mapping(@strings['en'])['download_badge'].to_s : strings['download_badge']
  end

  def render_include(page: {}, include_data: {}, strings: @strings, manifest: @manifest, external_links: @external_links,
                     ios_app_id: @ios_app_id, appstore_link: @config_appstore_link)
    config = Jekyll.configuration('source' => @source.to_s, 'quiet' => true, 'baseurl' => '/badge-test')
    site = Jekyll::Site.new(config)
    payload = {
      'site' => {
        'data' => { 'app_store_badges' => manifest, 'external_links' => external_links, 'strings' => strings },
        'appstore_link' => appstore_link,
        'ios_app_id' => ios_app_id
      },
      'page' => page,
      'include' => include_data
    }
    template = Liquid::Template.parse(@source.join('_includes/app-store-badge.html').read)
    template.render!(Marshal.load(Marshal.dump(payload)), registers: { site: site })
  end

  def assert_rendered_badge(html, expected_file:, expected_width:, expected_label:, expected_href:)
    @counts[:renders] += 1
    fragment = Nokogiri::HTML.fragment(html)
    link = fragment.at_css('a.app-store-badge')
    image = link&.at_css('img')
    check(:liquid, fragment.css('*').map(&:name) == %w[a img], 'Liquid regression: expected only one badge link and image')
    check(:liquid, link && link.attribute_nodes.map(&:name).sort == %w[aria-label class href], 'Liquid regression: unexpected link elements or attributes')
    check(:liquid, image && image.attribute_nodes.map(&:name).sort == %w[alt height src width], 'Liquid regression: unexpected image elements or attributes')
    return unless link && image

    check(:liquid, link['href'] == expected_href && link['aria-label'] == expected_label, 'Liquid regression: link or label mismatch')
    check(:liquid, image['src'] == "/badge-test/assets/app-store-badges/#{expected_file}" && image['alt'] == expected_label,
          'Liquid regression: image path or alt mismatch')
    check(:liquid, image['width'] == expected_width.to_i.to_s && image['height'] == '40', 'Liquid regression: image dimensions mismatch')
  end

  def validate_liquid_include
    en = mapping(@manifest['en'])
    fr = mapping(@manifest['fr'])
    ja = mapping(@manifest['ja'])
    en_label = localized_label('en')
    fr_label = localized_label('fr')
    ja_label = localized_label('ja')
    assert_rendered_badge(render_include, expected_file: en['file'], expected_width: en['width'], expected_label: en_label, expected_href: expected_app_store_href('en'))
    assert_rendered_badge(render_include(page: { 'locale' => 'xx' }), expected_file: en['file'], expected_width: en['width'], expected_label: en_label, expected_href: expected_app_store_href('xx'))
    assert_rendered_badge(render_include(page: { 'locale' => '' }), expected_file: en['file'], expected_width: en['width'], expected_label: en_label, expected_href: expected_app_store_href(''))
    assert_rendered_badge(render_include(page: { 'locale' => 'fr' }), expected_file: fr['file'], expected_width: fr['width'], expected_label: fr_label, expected_href: expected_app_store_href('fr'))
    assert_rendered_badge(render_include(page: { 'locale' => 'fr' }, include_data: { 'locale' => 'ja' }), expected_file: ja['file'], expected_width: ja['width'], expected_label: ja_label, expected_href: expected_app_store_href('ja'))

    missing_label_strings = Marshal.load(Marshal.dump(@strings))
    missing_label_strings['fr'] = mapping(missing_label_strings['fr']).reject { |key, _| key == 'download_badge' }
    assert_rendered_badge(render_include(page: { 'locale' => 'fr' }, strings: missing_label_strings), expected_file: fr['file'], expected_width: fr['width'], expected_label: en_label, expected_href: expected_app_store_href('fr'))

    custom_href = 'https://example.test/app?a=1&b="quoted"<tag>'
    custom_label = 'Use & enjoy <Countdowns> "now"'
    custom_strings = Marshal.load(Marshal.dump(@strings))
    custom_strings['fr'] = mapping(custom_strings['fr']).merge('download_badge' => custom_label)
    assert_rendered_badge(render_include(page: { 'locale' => 'fr' }, strings: custom_strings, appstore_link: custom_href), expected_file: fr['file'], expected_width: fr['width'], expected_label: custom_label, expected_href: custom_href)

    country_override = "https://apps.apple.com/us/app/apple-store/id#{@ios_app_id}"
    assert_rendered_badge(render_include(page: { 'locale' => 'ja' }, appstore_link: country_override), expected_file: ja['file'], expected_width: ja['width'], expected_label: ja_label, expected_href: country_override)
  rescue StandardError => error
    check(:liquid, false, "Liquid regression tests failed: #{error.class}: #{error.message}")
  end

  def run
    config = read_yaml('_config.yml')
    @config_appstore_link = config['appstore_link']
    @ios_app_id = config['ios_app_id']
    @external_links = mapping(read_yaml('_data/external_links.yml'))
    @strings = mapping(read_yaml('_data/strings.yml'))
    validate_manifest
    guides = @source.glob('_guide_pages/*.md').map { |path| path.basename('.md').to_s }.sort
    check(:manifest, @locales.any? { |locale| locale['code'] == 'en' }, 'Locale data must include English')
    check(:manifest, !guides.empty?, 'At least one source guide is required')
    validate_liquid_include
    @locales.each do |locale|
      ['', 'countdown-ideas', *guides].each { |slug| validate_route(locale, slug) }
    end
    puts "Checked #{@counts[:sources]} SVG sources, #{@counts[:html]}/#{@counts[:routes]} built routes, #{@counts[:renders]} include regressions."
    @errors.each do |group, errors|
      next if errors.empty?

      warn "#{group}: #{errors.size} failure(s)"
      (@verbose ? errors : errors.first(12)).each { |error| warn "  #{error}" }
      warn "  ... #{errors.size - 12} more (use --verbose)" if !@verbose && errors.size > 12
    end
    total = @errors.values.sum(&:size)
    puts(total.zero? ? 'PASS: all App Store badge checks passed.' : "FAIL: #{total} App Store badge validation errors.")
    total.zero?
  end
end

if $PROGRAM_NAME == __FILE__
  options = { source: File.expand_path('..', __dir__) }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: bundle exec ruby scripts/validate-app-store-badges.rb [--site BUILD_DIR] [--baseurl /prefix] [--verbose]'
    opts.on('--site PATH', 'Built Jekyll directory (default: SOURCE/_site)') { |value| options[:site] = value }
    opts.on('--source PATH', 'Source root (default: repository root)') { |value| options[:source] = value }
    opts.on('--baseurl PATH', 'Override baseurl when validating a build with a CLI override') { |value| options[:baseurl] = value }
    opts.on('--verbose', 'Print every failure') { options[:verbose] = true }
    opts.on('-h', '--help', 'Show usage') { puts opts; exit }
  end
  parser.parse!
  abort(parser.to_s) unless ARGV.empty?
  options[:site] ||= File.join(options[:source], '_site')
  exit(AppStoreBadgeValidator.new(**options).run ? 0 : 1)
end
