#!/usr/bin/env ruby
# Run after Jekyll: rbenv exec bundle exec ruby scripts/validate-screenshots.rb --site /path/to/build
# Missing captures/alt translations fail; regional English reuse is explicitly audited below.
require 'yaml'
require 'pathname'
require 'optparse'
require 'uri'
require 'nokogiri'
require 'json'
require 'digest'

class ScreenshotValidator
  EVENT_SCENES = %w[
    wedding-countdown-app vacation-countdown-app anniversary-countdown-app
    theme-park-trip-countdown-app birthday-countdown-app holiday-countdown-app
    retirement-countdown-app pregnancy-countdown-app event-countdown-app christmas-countdown-app
  ].freeze
  SCENES = (%w[normal-display compact-display colors editing settings home-screen-widgets lock-screen-widgets
              home-screen-custom-widgets widget-editor] + EVENT_SCENES).freeze
  GUIDES = EVENT_SCENES.to_h { |scene| [scene, scene] }.merge(
    'iphone-countdown-widget' => 'home-screen-custom-widgets',
    'lock-screen-countdown-widget' => 'lock-screen-widgets',
    'mac-countdown-widget' => 'home-screen-widgets'
  ).freeze
  HOME_SCENES = %w[colors home-screen-custom-widgets lock-screen-widgets home-screen-widgets editing settings widget-editor normal-display].freeze
  REGIONAL_UPDATES = {
    'en-CA' => %w[editing settings event-countdown-app home-screen-custom-widgets widget-editor],
    'en-GB' => %w[editing settings event-countdown-app normal-display compact-display colors home-screen-widgets vacation-countdown-app lock-screen-widgets christmas-countdown-app
                 home-screen-custom-widgets widget-editor],
    'en-AU' => %w[editing settings event-countdown-app normal-display compact-display colors home-screen-widgets vacation-countdown-app lock-screen-widgets christmas-countdown-app
                 home-screen-custom-widgets widget-editor]
  }.freeze
  # Locales that show another locale's native captures until their own exist.
  BORROWED_SCREENSHOTS = {}.freeze
  # Native Mac Catalyst captures replace the phone hero on these guides where a
  # locale has one (_data/mac_screenshots.yml); other locales keep the phone frame.
  MAC_GUIDES = { 'mac-countdown-widget' => 'desktop' }.freeze
  MAC_DIMENSIONS = [2048, 1536].freeze
  MAC_WIDTHS = [480, 960, 1440].freeze
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
    folder = BORROWED_SCREENSHOTS.fetch(locale['code'], folder)
    updates = REGIONAL_UPDATES[locale['code']]
    folder = 'en' if updates && !updates.include?(scene)
    "/assets/screenshots/#{folder}/#{scene}.png"
  end

  def localized_alt(code, scene)
    mapping(@alts[code])[scene]
  end

  def validate_manifest
    @manifest = mapping(read_yaml('_data/screenshots.yml'))
    @responsive = JSON.parse(@source.join('_data/responsive_images.json').read)
    @alts = mapping(read_yaml('_data/screenshot_alts.yml'))
    locale_data = read_yaml('_data/locales.yml')
    @locales = locale_data.is_a?(Array) ? locale_data : []
    codes = @locales.map { |locale| locale['code'] }
    check(:manifest, codes.size == 38 && codes.uniq.size == 38, 'Expected 38 unique locale codes')
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
      check(:manifest, entries.keys.sort == SCENES.sort, "#{code}: expected exactly 19 scene keys")
      SCENES.each do |scene|
        @counts[:sources] += 1
        path = expected_path(locale, scene)
        check(:manifest, entries[scene] == path, "#{code}/#{scene}: expected exact path #{path}, got #{entries[scene].inspect}")
        validate_png(@source.join(path.delete_prefix('/')))
        validate_derivatives(path)
        @counts[:alts] += 1
        alt = localized_alt(code, scene)
        check(:alts, alt.is_a?(String) && !alt.strip.empty?, "#{code}/#{scene}: missing localized alt text")
        if code != 'en' && !REGIONAL_UPDATES.key?(code) && alt.is_a?(String)
          english = localized_alt('en', scene)
          check(:alts, alt.strip != english.to_s.strip, "#{code}/#{scene}: alt text repeats English")
        end
      end
    end
    validate_mac_manifest
  end

  def validate_mac_manifest
    @mac = mapping(read_yaml('_data/mac_screenshots.yml'))
    @mac_variants = mapping(JSON.parse(@source.join('_data/mac_screenshot_variants.json').read)['screenshots'])
    check(:manifest, @mac['guides'] == MAC_GUIDES, 'Mac guide map must match MAC_GUIDES')
    check(:manifest, @mac.values_at('width', 'height') == MAC_DIMENSIONS, 'Mac screenshot dimensions must be 2048x1536')
    codes = @locales.map { |locale| locale['code'] }
    mac_locales = mapping(@mac['locales'])
    check(:manifest, (mac_locales.keys - codes).empty?, 'Mac screenshot locales must exist in locales.yml')
    mac_locales.each do |code, scenes|
      check(:manifest, mapping(scenes).keys == MAC_GUIDES.values.uniq, "#{code}: unexpected Mac scenes")
      mapping(scenes).each do |scene, path|
        check(:manifest, path.to_s.match?(%r{\A/assets/screenshots-mac/[a-z-]+/[a-z-]+\.png\z}), "#{code}/#{scene}: invalid Mac path #{path.inspect}")
        validate_png(@source.join(path.to_s.delete_prefix('/')), MAC_DIMENSIONS)
        validate_mac_derivatives(path.to_s)
        alt = mapping(mapping(@mac['alts'])[code])[scene]
        check(:alts, alt.is_a?(String) && !alt.strip.empty?, "#{code}/#{scene}: missing Mac alt text")
      end
    end
  rescue Errno::ENOENT, JSON::ParserError => error
    check(:manifest, false, "Mac screenshot manifest: #{error.message.lines.first.strip}")
  end

  def mac_path(locale, slug)
    scene = MAC_GUIDES[slug]
    scene && mapping(mapping(@mac['locales'])[locale['code']])[scene]
  end

  def mac_derivatives(path)
    mapping(@mac_variants[path]).fetch('variants', [])
  end

  def validate_mac_derivatives(path)
    entry = mapping(@mac_variants[path])
    source = @source.join(path.delete_prefix('/'))
    check(:derivatives, entry['source'] == path && source.file? && entry['source_sha256'] == Digest::SHA256.file(source).hexdigest,
          "#{path}: missing/stale Mac derivative source")
    variants = mac_derivatives(path)
    check(:derivatives, variants.map { |v| v['width'] } == MAC_WIDTHS, "#{path}: expected 480/960/1440 variants")
    variants.each do |variant|
      expected = path.sub('.png', "-#{variant['width']}.webp")
      check(:derivatives, variant['path'] == expected, "#{path}: incorrect Mac derivative path")
      file = @source.join(expected.delete_prefix('/'))
      check(:derivatives, file.file?, "Missing derivative #{expected}")
      next unless file.file?

      bytes = file.binread
      check(:derivatives, bytes.bytesize == variant['bytes'] && Digest::SHA256.hexdigest(bytes) == variant['sha256'], "#{expected}: stale size/hash")
      expected_dimensions = [variant['width'], (variant['width'].to_f * MAC_DIMENSIONS[1] / MAC_DIMENSIONS[0]).round]
      check(:derivatives, webp_dimensions(bytes) == expected_dimensions && variant.values_at('width', 'height') == expected_dimensions,
            "#{expected}: wrong encoded dimensions")
    end
  end

  def derivatives(path)
    mapping(@responsive['screenshots'])[path].to_h.fetch('variants', [])
  end

  def validate_derivatives(path)
    entry = mapping(mapping(@responsive['screenshots'])[path])
    source = @source.join(path.delete_prefix('/'))
    check(:derivatives, entry['source'] == path && source.file? && entry['source_sha256'] == Digest::SHA256.file(source).hexdigest,
          "#{path}: missing/stale derivative source")
    variants = derivatives(path)
    check(:derivatives, variants.map { |v| v['width'] } == [360, 720, 1080], "#{path}: expected 360/720/1080 variants")
    variants.each do |variant|
      expected = path.sub('/screenshots/', '/screenshots-responsive/').sub('.png', "-#{variant['width']}.webp")
      check(:derivatives, variant['path'] == expected, "#{path}: incorrect derivative path")
      file = @source.join(expected.delete_prefix('/'))
      check(:derivatives, file.file?, "Missing derivative #{expected}")
      next unless file.file?
      bytes = file.binread
      check(:derivatives, bytes.bytesize == variant['bytes'] && Digest::SHA256.hexdigest(bytes) == variant['sha256'], "#{expected}: stale size/hash")
      dimensions = webp_dimensions(bytes)
      check(:derivatives, dimensions, "#{expected}: invalid WebP")
      expected_dimensions = [variant['width'], (variant['width'].to_f * 2622 / 1206).round]
      check(:derivatives, dimensions == expected_dimensions && variant.values_at('width', 'height') == dimensions, "#{expected}: wrong encoded dimensions")
    end
  end

  # A lossy VP8 frame stores its dimensions after the start code.
  def webp_dimensions(bytes)
    return unless bytes.start_with?('RIFF') && bytes.byteslice(8, 4) == 'WEBP'

    offset = 12
    while offset + 8 <= bytes.bytesize
      kind = bytes.byteslice(offset, 4)
      length = bytes.byteslice(offset + 4, 4).unpack1('V')
      if kind == 'VP8 ' && bytes.byteslice(offset + 11, 3) == "\x9d\x01\x2a".b
        return bytes.byteslice(offset + 14, 4).unpack('vv').map { |v| v & 0x3fff }
      end
      offset += 8 + length + length % 2
    end
    nil
  end

  def validate_png(path, expected_dimensions = [1206, 2622])
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
    check(:sources, dimensions == expected_dimensions, "#{path}: dimensions #{dimensions.join('x')}, expected #{expected_dimensions.join('x')}")
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
    if path.start_with?('assets/screenshots-mac/')
      allowed = mapping(mapping(@mac['locales'])[locale['code']]).values.flat_map { |p| [p, *mac_derivatives(p).map { |v| v['path'] }] }
      check(:routes, allowed.map { |p| p.delete_prefix('/') }.include?(path), "#{route}: wrong-locale or unknown Mac screenshot path #{value}")
      return
    end
    return unless path.match?(%r{assets/screenshots(?:-responsive)?/})

    allowed = SCENES.flat_map do |scene|
      original = expected_path(locale, scene)
      [original, *derivatives(original).map { |v| v['path'] }].map { |p| p.delete_prefix('/') }
    end
    check(:routes, allowed.include?(path), "#{route}: legacy, wrong-locale, or unknown screenshot path #{value}")
  rescue URI::InvalidURIError, ArgumentError => error
    check(:routes, false, "#{route}: invalid image/preload URL #{value.inspect}: #{error.message}")
  end

  def validate_frame(frame, route, locale, expected_scene, home:, index:)
    code = locale['code']
    scene = frame['data-screenshot-scene']
    check(:routes, scene == expected_scene, "#{route}: frame #{index + 1} must use #{expected_scene}, got #{scene.inspect}")
    check(:routes, frame['data-screenshot-locale'] == code, "#{route}: wrong frame locale #{frame['data-screenshot-locale'].inspect}")
    images = frame.css('> picture > img')
    check(:routes, images.size == 1, "#{route}: each frame must contain exactly one img")
    check(:routes, frame.at_css('> .screenshot-phone__island[aria-hidden="true"]'), "#{route}: missing decorative phone island")
    image = images.first
    return unless image

    path = @baseurl + expected_path(locale, expected_scene)
    check(:routes, image['src'] == path, "#{route}: expected #{path}, got #{image['src'].inspect}")
    check(:routes, [image['width'], image['height']] == %w[1206 2622], "#{route}: img must declare native 1206x2622 dimensions")
    sources = frame.css('> picture > source')
    source = sources.first
    expected_srcset = derivatives(expected_path(locale, expected_scene)).map { |v| "#{@baseurl}#{v['path']} #{v['width']}w" }.join(', ')
    check(:routes, sources.size == 1 && source['type'] == 'image/webp' && source['srcset'] == expected_srcset,
          "#{route}: expected localized WebP srcset #{expected_srcset}")
    check(:routes, source && !source['sizes'].to_s.empty?, "#{route}: missing responsive sizes")
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

  def validate_mac_frame(frame, route, locale, scene, path)
    code = locale['code']
    check(:routes, frame['data-screenshot-scene'] == scene && frame['data-screenshot-locale'] == code, "#{route}: wrong Mac frame scene or locale")
    images = frame.css('> .screenshot-mac__screen > picture > img')
    check(:routes, images.size == 1, "#{route}: Mac frame must contain exactly one img")
    check(:routes, frame.at_css('> .screenshot-mac__base[aria-hidden="true"]'), "#{route}: missing decorative Mac base")
    image = images.first
    return unless image

    check(:routes, image['src'] == @baseurl + path, "#{route}: expected #{@baseurl + path}, got #{image['src'].inspect}")
    check(:routes, [image['width'], image['height']] == MAC_DIMENSIONS.map(&:to_s), "#{route}: Mac img must declare native 2048x1536 dimensions")
    source = frame.at_css('> .screenshot-mac__screen > picture > source')
    expected_srcset = mac_derivatives(path).map { |v| "#{@baseurl}#{v['path']} #{v['width']}w" }.join(', ')
    check(:routes, source && source['type'] == 'image/webp' && source['srcset'] == expected_srcset && !source['sizes'].to_s.empty?,
          "#{route}: expected Mac WebP srcset #{expected_srcset}")
    alt = mapping(mapping(@mac['alts'])[code])[scene]
    check(:alts, image['alt'] == alt && !alt.to_s.strip.empty?, "#{route}: Mac img must use its nonempty localized alt")
    check(:routes, image['loading'] == 'eager' && image['fetchpriority'] == 'high', "#{route}: Mac hero must load eagerly with high priority")
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
    doc = Nokogiri::HTML5(file.read)
    home = slug.empty?
    mac = mac_path(locale, slug)
    scenes = if home then HOME_SCENES
             elsif mac then []
             else [slug == 'countdown-ideas' ? 'colors' : GUIDES.fetch(slug)]
             end
    mac_frames = doc.css('.screenshot-mac')
    check(:routes, mac_frames.size == (mac ? 1 : 0), "#{route}: expected #{mac ? 1 : 0} Mac screenshot frames, found #{mac_frames.size}")
    validate_mac_frame(mac_frames.first, route, locale, MAC_GUIDES.fetch(slug), mac) if mac && mac_frames.size == 1
    frames = doc.css('.screenshot-phone')
    check(:routes, frames.size == scenes.size, "#{route}: expected #{scenes.size} screenshot frames, found #{frames.size}")
    frames.first(scenes.size).each_with_index do |frame, index|
      validate_frame(frame, route, locale, scenes[index], home: home, index: index)
    end
    doc.css('img').each do |image|
      validate_reference(image['src'], route, locale)
      if image['src'].to_s.include?('/assets/screenshots/')
        check(:routes, image.parent.name == 'picture' && image.parent.parent['class'].to_s.split.include?('screenshot-phone'), "#{route}: unframed screenshot #{image['src']}")
      end
      image['srcset'].to_s.split(',').each { |candidate| validate_reference(candidate.strip.split.first, route, locale) }
    end
    doc.css('picture > source').each do |source|
      source['srcset'].to_s.split(',').each { |candidate| validate_reference(candidate.strip.split.first, route, locale) }
    end
    preloads = doc.css('link[rel~="preload"][as="image"]')
    preloads.each do |preload|
      validate_reference(preload['href'], route, locale)
      preload['imagesrcset'].to_s.split(',').each { |candidate| validate_reference(candidate.strip.split.first, route, locale) }
    end
    if home
      path = @baseurl + derivatives(expected_path(locale, 'home-screen-custom-widgets'))[1].fetch('path')
      check(:routes, preloads.size == 1 && preloads.first['href'] == path, "#{route}: preload must match the localized primary hero #{path}")
      hero_source = frames[1]&.at_css('picture > source')
      check(:routes, preloads.first && hero_source && preloads.first['type'] == 'image/webp' && preloads.first['imagesrcset'] == hero_source['srcset'] && preloads.first['imagesizes'] == hero_source['sizes'], "#{route}: preload must match hero type, srcset and sizes")
      check(:routes, preloads.first && preloads.first['fetchpriority'] == 'high', "#{route}: home preload must have fetchpriority=high")
    end
  end

  def run
    validate_manifest
    @locales.each do |locale|
      ['', 'countdown-ideas', *GUIDES.keys].each { |slug| validate_route(locale, slug) }
    end
    check(:manifest, @counts[:sources] == 722 && @counts[:alts] == 722, 'Expected 722 source paths and localized alts')
    check(:routes, @counts[:routes] == 570, 'Expected 570 routes')
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
