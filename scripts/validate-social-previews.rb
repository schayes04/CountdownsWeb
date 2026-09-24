#!/usr/bin/env ruby
# Run after bundle exec jekyll build: bundle exec ruby scripts/validate-social-previews.rb [BUILD_DIR]
require 'jekyll'
require 'nokogiri'
require 'digest'
require 'yaml'
require 'pathname'

source = Pathname.new(File.expand_path('..', __dir__))
build = Pathname.new(ARGV.fetch(0, source.join('_site').to_s)).expand_path
locales = YAML.load_file(source.join('_data/locales.yml'))
images = YAML.load_file(source.join('_data/social_previews.yml'))
config = Jekyll.configuration('source' => source.to_s, 'destination' => build.to_s, 'quiet' => true)
origin = config.fetch('url').delete_suffix('/') + config.fetch('baseurl', '').to_s.delete_suffix('/')
abort 'The canonical origin must use HTTPS' unless origin.start_with?('https://')
abort 'Manifest must cover exactly the website locales' unless images.keys.sort == locales.map { |l| l.fetch('code') }.sort
errors = []
check = ->(condition, message) { errors << message unless condition }
check_meta = lambda do |html, expected, label, default_image|
  doc = Nokogiri::HTML(html)
  ['meta[property="og:image"]', 'meta[name="twitter:image"]'].each do |selector|
    nodes = doc.css(selector)
    check.call(nodes.size == 1 && nodes.first['content'] == expected, "#{label}: incorrect #{selector}")
  end
  dimensions = %w[width height].map { |key| doc.at_css("meta[property='og:image:#{key}']")&.[]('content') }
  check.call(dimensions == (default_image ? %w[1200 630] : [nil, nil]), "#{label}: incorrect dimensions")
end

locales.each do |locale|
  code = locale.fetch('code')
  path = images.fetch(code)
  check.call(path.match?(%r{\A/assets/link-previews/#{Regexp.escape(code)}\.[0-9a-f]{12}\.png\z}), "#{code}: invalid image path")
  original = source.join(path.delete_prefix('/'))
  deployed = build.join(path.delete_prefix('/'))
  [original, deployed].each do |file|
    check.call(file.file?, "Missing #{file}")
    next unless file.file?
    bytes = file.binread
    check.call(bytes.start_with?("\x89PNG\r\n\x1a\n".b) && bytes.byteslice(16, 8).unpack('NN') == [1200, 630], "#{file}: invalid PNG/dimensions")
    check.call(File.basename(path).split('.')[-2] == Digest::SHA256.hexdigest(bytes)[0, 12], "#{file}: filename hash mismatch")
  end
  ['', 'support', 'countdown-ideas', *source.glob('_guide_pages/*.md').map { |p| p.basename('.md').to_s }].each do |slug|
    page = build.join(locale.fetch('folder'), slug, 'index.html')
    check.call(page.file?, "Missing #{page}")
    check_meta.call(page.read, origin + path, page.to_s, true) if page.file?
  end
end

# Render the real shared head through Jekyll; fixtures remain in memory and are never published.
site = Jekyll::Site.new(config)
site.read
[
  [{ 'locale' => 'unknown' }, origin + images.fetch('en'), true],
  [{}, origin + images.fetch('en'), true],
  [{ 'locale' => 'ar', 'image' => '/assets/promo.png' }, origin + '/assets/promo.png', false],
  [{ 'locale' => 'ja', 'image' => 'https://example.com/custom.png' }, 'https://example.com/custom.png', false]
].each_with_index do |(data, expected, default_image), index|
  page = Jekyll::PageWithoutAFile.new(site, source.to_s, '', "preview-fixture-#{index}.html")
  page.data.merge!(data.merge('localized' => false))
  page.content = '{% include head.html %}'
  html = Jekyll::Renderer.new(site, page).run
  check_meta.call(html, expected, "fixture #{index}", default_image)
end
check.call(source.join('assets/promo.png').file? && build.join('assets/promo.png').file?, 'Legacy shared preview must remain available')
check.call(source.glob('assets/link-previews/*').map { |p| '/' + p.relative_path_from(source).to_s }.sort == images.values.sort, 'Unexpected preview assets')
check.call(source.glob('assets/**/banner*.png').empty?, 'Banner assets must not be deployed')
if errors.empty?
  puts "PASS: #{locales.size} hashed previews, #{locales.size * (3 + source.glob('_guide_pages/*.md').size)} built home/guide/support/ideas pages, both fallback cases and both explicit overrides."
else
  abort errors.join("\n")
end
