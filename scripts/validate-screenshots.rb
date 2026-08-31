#!/usr/bin/env ruby
# Run after Jekyll: rbenv exec bundle exec ruby scripts/validate-screenshots.rb --site /path/to/build
# Missing captures/alt translations are failures, never silently replaced with English.
require 'yaml'
require 'pathname'
require 'optparse'
require 'uri'
require 'nokogiri'

class ScreenshotValidator
  EVENT_SCENES = %w[
    wedding-countdown-app vacation-countdown-app anniversary-countdown-app
    theme-park-trip-countdown-app birthday-countdown-app holiday-countdown-app
    retirement-countdown-app pregnancy-countdown-app event-countdown-app christmas-countdown-app
  ].freeze
  SCENES = (%w[normal-display compact-display colors editing settings home-screen-widgets lock-screen-widgets] + EVENT_SCENES).freeze
  GUIDES = EVENT_SCENES.to_h { |scene| [scene, scene] }.merge(
    'iphone-countdown-widget' => 'home-screen-widgets',
    'lock-screen-countdown-widget' => 'lock-screen-widgets'
  ).freeze
  HOME_SCENES = %w[colors home-screen-widgets lock-screen-widgets home-screen-widgets editing settings compact-display normal-display].freeze
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze

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

  def expected_path(locale, scene)
    folder = locale['folder'].to_s.empty? ? 'en' : locale['folder']
    "/assets/screenshots/#{folder}/#{scene}.png"
  end

  def localized_alt(code, scene)
    mapping(@alts[code])[scene]
  end

  def validate_manifest
    @manifest = mapping(read_yaml('_data/screenshots.yml'))
    @alts = mapping(read_yaml('_data/screenshot_alts.yml'))
    locale_data = read_yaml('_data/locales.yml')
    @locales = locale_data.is_a?(Array) ? locale_data : []
    codes = @locales.map { |locale| locale['code'] }
    check(:manifest, codes.size == 22 && codes.uniq.size == 22, 'Expected 22 unique locale codes')
    check(:manifest, @manifest['version'] == 'v12', 'Screenshot version must be v12')
    check(:manifest, @manifest.values_at('width', 'height') == [1206, 2622], 'Screenshot dimensions must be 1206x2622')
    check(:manifest, @manifest['guides'] == GUIDES, 'Guide map must contain the 12 required slug-to-scene mappings')
    guide_slugs = @source.glob('_guide_pages/*.md').map { |path| path.basename('.md').to_s }
    check(:manifest, guide_slugs.sort == GUIDES.keys.sort, 'Guide map must cover every source guide')
    manifest_locales = mapping(@manifest['locales'])
    check(:manifest, manifest_locales.keys.sort == codes.sort, 'Manifest locale keys must exactly match locales.yml codes')

    @locales.each do |locale|
      code = locale['code']
      entries = mapping(manifest_locales[code])
      check(:manifest, entries.keys.sort == SCENES.sort, "#{code}: expected exactly 17 scene keys")
      SCENES.each do |scene|
        @counts[:sources] += 1
        path = expected_path(locale, scene)
        check(:manifest, entries[scene] == path, "#{code}/#{scene}: expected exact path #{path}, got #{entries[scene].inspect}")
        validate_png(@source.join(path.delete_prefix('/')))
        @counts[:alts] += 1
        alt = localized_alt(code, scene)
        check(:alts, alt.is_a?(String) && !alt.strip.empty?, "#{code}/#{scene}: missing localized alt text")
        if code != 'en' && alt.is_a?(String)
          english = localized_alt('en', scene)
          check(:alts, alt.strip != english.to_s.strip, "#{code}/#{scene}: alt text repeats English")
        end
      end
    end
  end

  def validate_png(path)
    unless path.file?
      check(:sources, false, "Missing PNG: #{path.relative_path_from(@source)}")
      return
    end
    header = path.open('rb') { |file| file.read(24) }
    valid = header && header.bytesize == 24 && header.start_with?(PNG_SIGNATURE) &&
      header.byteslice(8, 8) == "\x00\x00\x00\x0dIHDR".b
    check(:sources, valid, "Invalid PNG header: #{path}")
    return unless valid

    dimensions = header.byteslice(16, 8).unpack('NN')
    check(:sources, dimensions == [1206, 2622], "#{path}: dimensions #{dimensions.join('x')}, expected 1206x2622")
  rescue SystemCallError => error
    check(:sources, false, "Cannot read #{path}: #{error.message}")
  end

  # Inspect all img and image-preload references, not just the shared include.
  # This catches legacy screenshots introduced outside the framed component.
  def validate_reference(value, route, locale)
    @counts[:references] += 1
    if value.to_s.empty?
      check(:routes, false, "#{route}: empty image/preload path")
      return
    end
    uri = URI.parse(value)
    if uri.scheme || uri.host
      check(:routes, !value.include?('/assets/screenshots/'), "#{route}: screenshot must use an exact local manifest path: #{value}")
      return
    end

    path = URI::DEFAULT_PARSER.unescape(uri.path)
    path = if path.start_with?('/')
             if !@baseurl.empty? && !path.start_with?("#{@baseurl}/")
               check(:routes, false, "#{route}: image path omits baseurl #{@baseurl}: #{value}")
             end
             path.delete_prefix(@baseurl).delete_prefix('/')
           else
             File.join(route.delete_prefix('/'), path)
           end
    file = @site.join(path).cleanpath
    check(:built_files, file.to_s.start_with?("#{@site}/") && file.file?, "#{route}: missing built image/preload file #{value}")
    return unless path.include?('assets/screenshots/')

    allowed = SCENES.map { |scene| expected_path(locale, scene).delete_prefix('/') }
    check(:routes, allowed.include?(path), "#{route}: legacy, wrong-locale, or unknown screenshot path #{value}")
  rescue URI::InvalidURIError, ArgumentError => error
    check(:routes, false, "#{route}: invalid image/preload URL #{value.inspect}: #{error.message}")
  end

  def validate_frame(frame, route, locale, expected_scene, home:, index:)
    code = locale['code']
    scene = frame['data-screenshot-scene']
    check(:routes, scene == expected_scene, "#{route}: frame #{index + 1} must use #{expected_scene}, got #{scene.inspect}")
    check(:routes, frame['data-screenshot-locale'] == code, "#{route}: wrong frame locale #{frame['data-screenshot-locale'].inspect}")
    images = frame.css('> img')
    check(:routes, images.size == 1, "#{route}: each frame must contain exactly one img")
    check(:routes, frame.at_css('> .screenshot-phone__island[aria-hidden="true"]'), "#{route}: missing decorative phone island")
    image = images.first
    return unless image

    path = @baseurl + expected_path(locale, expected_scene)
    check(:routes, image['src'] == path, "#{route}: expected #{path}, got #{image['src'].inspect}")
    check(:routes, [image['width'], image['height']] == %w[1206 2622], "#{route}: img must declare native 1206x2622 dimensions")
    decorative = home && index.zero?
    eager = !home || index == 1
    if decorative
      check(:routes, image['alt'] == '' && frame['aria-hidden'] == 'true', "#{route}: secondary hero must be decorative with empty alt")
    else
      alt = localized_alt(code, expected_scene)
      check(:alts, image['alt'].is_a?(String) && !image['alt'].strip.empty? && image['alt'] == alt,
            "#{route}: #{expected_scene} img must use its nonempty localized alt")
      check(:routes, frame['aria-hidden'] != 'true' && image['aria-hidden'] != 'true', "#{route}: meaningful screenshot hidden from accessibility")
    end
    check(:routes, image['loading'] == (eager ? 'eager' : 'lazy'), "#{route}: #{expected_scene} has incorrect loading priority")
    check(:routes, image['fetchpriority'] == 'high', "#{route}: hero must have fetchpriority=high") if eager
    if home && index < 2
      modifier = index.zero? ? 'hero__phone--secondary' : 'hero__phone--primary'
      check(:routes, frame['class'].to_s.split.include?(modifier), "#{route}: #{modifier} must be on the frame")
      check(:routes, !image['class'].to_s.include?('hero__phone'), "#{route}: hero layout classes must not be on img")
    end
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
    home = slug.empty?
    scenes = home ? HOME_SCENES : [slug == 'countdown-ideas' ? 'colors' : GUIDES.fetch(slug)]
    frames = doc.css('.screenshot-phone')
    check(:routes, frames.size == scenes.size, "#{route}: expected #{scenes.size} screenshot frames, found #{frames.size}")
    frames.first(scenes.size).each_with_index do |frame, index|
      validate_frame(frame, route, locale, scenes[index], home: home, index: index)
    end
    doc.css('img').each do |image|
      validate_reference(image['src'], route, locale)
      if image['src'].to_s.include?('/assets/screenshots/')
        check(:routes, image.parent['class'].to_s.split.include?('screenshot-phone'), "#{route}: unframed screenshot #{image['src']}")
      end
      image['srcset'].to_s.split(',').each { |candidate| validate_reference(candidate.strip.split.first, route, locale) }
    end
    preloads = doc.css('link[rel~="preload"][as="image"]')
    preloads.each do |preload|
      validate_reference(preload['href'], route, locale)
      preload['imagesrcset'].to_s.split(',').each { |candidate| validate_reference(candidate.strip.split.first, route, locale) }
    end
    if home
      path = @baseurl + expected_path(locale, 'home-screen-widgets')
      check(:routes, preloads.size == 1 && preloads.first['href'] == path, "#{route}: preload must match the localized primary hero #{path}")
      check(:routes, preloads.first && preloads.first['fetchpriority'] == 'high', "#{route}: home preload must have fetchpriority=high")
    end
  end

  def run
    validate_manifest
    @locales.each do |locale|
      ['', 'countdown-ideas', *GUIDES.keys].each { |slug| validate_route(locale, slug) }
    end
    check(:manifest, @counts[:sources] == 374 && @counts[:alts] == 374, 'Expected 374 source paths and localized alts')
    check(:routes, @counts[:routes] == 308, 'Expected 308 routes')
    puts "Checked #{@counts[:sources]} source PNG paths, #{@counts[:alts]} localized alts, " \
         "#{@counts[:html]}/#{@counts[:routes]} built routes, #{@counts[:references]} image/preload references."
    @errors.each do |group, errors|
      next if errors.empty?

      warn "#{group}: #{errors.size} failure(s)"
      (@verbose ? errors : errors.first(12)).each { |error| warn "  #{error}" }
      warn "  ... #{errors.size - 12} more (use --verbose)" if !@verbose && errors.size > 12
    end
    total = @errors.values.sum(&:size)
    puts(total.zero? ? 'PASS: all screenshot checks passed.' : "FAIL: #{total} screenshot validation errors.")
    total.zero?
  end
end

if $PROGRAM_NAME == __FILE__
  options = { source: File.expand_path('..', __dir__) }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: bundle exec ruby scripts/validate-screenshots.rb [--site BUILD_DIR] [--baseurl /prefix] [--verbose]'
    opts.on('--site PATH', 'Built Jekyll directory (default: SOURCE/_site)') { |value| options[:site] = value }
    opts.on('--source PATH', 'Source root (default: repository root)') { |value| options[:source] = value }
    opts.on('--baseurl PATH', 'Override baseurl when validating a build with a CLI override') { |value| options[:baseurl] = value }
    opts.on('--verbose', 'Print every failure') { options[:verbose] = true }
    opts.on('-h', '--help', 'Show usage') { puts opts; exit }
  end
  parser.parse!
  abort(parser.to_s) unless ARGV.empty?
  options[:site] ||= File.join(options[:source], '_site')
  exit(ScreenshotValidator.new(**options).run ? 0 : 1)
end
