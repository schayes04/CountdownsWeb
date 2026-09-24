#!/usr/bin/env ruby
# Requires cwebp (libwebp); generation also uses macOS sips for PNG icons.
require 'yaml'
require 'json'
require 'digest'
require 'fileutils'
require 'open3'

ROOT = File.expand_path('..', __dir__)
MANIFEST = File.join(ROOT, '_data/responsive_images.json')
WIDTHS = [360, 720, 1080].freeze
QUALITY = 85

def asset(path)
  File.join(ROOT, path.delete_prefix('/'))
end

def digest(path)
  Digest::SHA256.file(asset(path)).hexdigest
end

def record(path, width, height)
  { 'path' => path, 'width' => width, 'height' => height,
    'bytes' => File.size(asset(path)), 'sha256' => digest(path) }
end

def run(*command)
  output, status = Open3.capture2e(*command)
  abort "#{command.first} failed: #{output}" unless status.success?
end

if ARGV == ['--check']
  manifest = JSON.parse(File.read(MANIFEST))
  sources = YAML.safe_load_file(File.join(ROOT, '_data/screenshots.yml'))
  expected = sources.fetch('locales').values.flat_map(&:values).sort
  abort 'Derivative source coverage differs from screenshots.yml' unless manifest.fetch('screenshots').keys.sort == expected
  abort 'Unexpected encoder settings' unless manifest.fetch('widths') == WIDTHS && manifest.fetch('quality') == QUALITY
  icon_source = '/' + YAML.safe_load_file(File.join(ROOT, '_config.yml'), permitted_classes: [Symbol]).fetch('app_icon').delete_prefix('/')
  abort 'Icon source differs from app_icon configuration' unless manifest.fetch('icon').fetch('source') == icon_source
  abort 'Expected 32/64/128/180px icons' unless manifest.fetch('icon').fetch('variants').map { |v| v['width'] } == [32, 64, 128, 180]
  manifest.fetch('icon').fetch('variants').each do |variant|
    header = File.binread(asset(variant.fetch('path')), 24)
    abort 'Invalid icon dimensions' unless header.start_with?("\x89PNG\r\n\x1a\n".b) && header.byteslice(16, 8).unpack('NN') == [variant['width'], variant['width']]
  end
  (manifest.fetch('screenshots').values + [manifest.fetch('icon')]).each do |entry|
    abort "Stale source: #{entry['source']}" unless digest(entry.fetch('source')) == entry.fetch('source_sha256')
    entry.fetch('variants').each do |variant|
      abort "Missing/modified derivative: #{variant['path']}" unless digest(variant.fetch('path')) == variant.fetch('sha256') && File.size(asset(variant['path'])) == variant['bytes']
    end
  end
  puts "PASS: responsive image source and derivative hashes (#{expected.size} screenshots plus icons)"
  exit
end
abort 'Usage: ruby scripts/generate-responsive-images.rb [--check]' unless ARGV.empty?

encoder, status = Open3.capture2e('cwebp', '-version')
abort 'Install libwebp to provide cwebp' unless status.success?
sources = YAML.safe_load_file(File.join(ROOT, '_data/screenshots.yml'))
paths = sources.fetch('locales').values.flat_map(&:values).uniq.sort
previous = File.exist?(MANIFEST) ? JSON.parse(File.read(MANIFEST)) : {}
settings_match = previous['encoder'] == encoder.strip && previous['quality'] == QUALITY && previous['widths'] == WIDTHS
entries = {}
queue = Queue.new
paths.each { |path| queue << path }
workers = 6.times.map do
  Thread.new do
    loop do
      path = queue.pop(true) rescue break
      source_sha = digest(path)
      old = previous.fetch('screenshots', {})[path]
      if settings_match && old && old['source_sha256'] == source_sha && old['variants'].all? { |v| File.file?(asset(v['path'])) && digest(v['path']) == v['sha256'] }
        entries[path] = old
        next
      end
      variants = WIDTHS.map do |width|
        height = (width.to_f * sources.fetch('height') / sources.fetch('width')).round
        output = path.sub('/screenshots/', '/screenshots-responsive/').sub('.png', "-#{width}.webp")
        FileUtils.mkdir_p(File.dirname(asset(output)))
        run('cwebp', '-quiet', '-q', QUALITY.to_s, '-m', '6', '-resize', width.to_s, height.to_s, asset(path), '-o', asset(output))
        record(output, width, height)
      end
      entries[path] = { 'source' => path, 'source_sha256' => source_sha, 'variants' => variants }
    end
  end
end
workers.each(&:value)
icon_path = '/' + YAML.safe_load_file(File.join(ROOT, '_config.yml'), permitted_classes: [Symbol]).fetch('app_icon').delete_prefix('/')
icon = { 'source' => icon_path, 'source_sha256' => digest(icon_path), 'variants' => [32, 64, 128, 180].map do |size|
  path = "/assets/icons/appicon-#{size}.png"
  FileUtils.mkdir_p(File.dirname(asset(path)))
  run('sips', '-z', size.to_s, size.to_s, asset(icon_path), '--out', asset(path))
  record(path, size, size)
end }
manifest = { 'encoder' => encoder.strip, 'quality' => QUALITY, 'widths' => WIDTHS,
             'screenshots' => entries.sort.to_h, 'icon' => icon }
File.write(MANIFEST, JSON.pretty_generate(manifest) + "\n")
puts "Generated #{entries.size * WIDTHS.size} WebP images and #{icon['variants'].size} icons."
