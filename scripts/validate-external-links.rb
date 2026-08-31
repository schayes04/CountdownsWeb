#!/usr/bin/env ruby
# Offline audit of every built anchor. Run after Jekyll without network access.
require 'nokogiri'
require 'liquid'
require 'optparse'
require 'pathname'
require 'uri'
require 'yaml'

class ExternalLinksValidator
  APPLE_ARTICLE_KEYS = %w[iphone_widgets iphone_wallpaper mac_widgets refunds].freeze
  SUPPORT_EMAIL = 'mailto:support@shayesapps.com'.freeze
  REVENUECAT_PRIVACY = 'https://www.revenuecat.com/privacy'.freeze
  ADMOB_PRIVACY = 'https://support.google.com/admob/answer/6128543?hl=en'.freeze

  def initialize(source:, site:, verbose: false)
    @source = Pathname(source).expand_path
    @site = Pathname(site).expand_path
    @verbose = verbose
    @errors = Hash.new { |hash, key| hash[key] = [] }
    @counts = Hash.new(0)
    @internal_inventory = Hash.new(0)
    @external_inventory = Hash.new(0)
  end

  def run
    validate_source
    return finish unless @origin && @locales.any?

    files = @site.glob('**/*.html').sort
    check(:site, !files.empty?, "no built HTML found in #{@site}")
    files.each { |file| validate_document(file) }
    finish
  end

  private

  def check(group, condition, message)
    @errors[group] << message unless condition
  end

  def add_error(group, message)
    @errors[group] << message
  end

  def read_yaml(path)
    YAML.safe_load(@source.join(path).read, permitted_classes: [Symbol], aliases: true) || {}
  rescue Errno::ENOENT, Psych::Exception => error
    add_error(:source, "#{path}: #{error.message.lines.first.strip}")
    {}
  end

  def validate_source
    @config = read_yaml('_config.yml')
    @config = {} unless @config.is_a?(Hash)
    @locales = read_yaml('_data/locales.yml')
    @links = read_yaml('_data/external_links.yml')
    @locales = [] unless @locales.is_a?(Array)
    @links = {} unless @links.is_a?(Hash)
    @locale_by_html_lang = @locales.to_h { |locale| [locale['html_lang'].to_s, locale['code'].to_s] }
    configure_origin
    @apple = @links['apple_support'].is_a?(Hash) ? @links['apple_support'] : {}
    @articles = @apple['articles'].is_a?(Hash) ? @apple['articles'] : {}
    @regions = @apple['locales'].is_a?(Hash) ? @apple['locales'] : {}
    @guide_overrides = @apple['guide_locale_overrides'].is_a?(Hash) ? @apple['guide_locale_overrides'] : {}
    codes = @locales.map { |locale| locale['code'].to_s }
    check(:source, codes.length == 22 && codes.uniq.length == 22, 'locales.yml must contain 22 unique locale codes')
    check(:source, @articles.keys.sort == APPLE_ARTICLE_KEYS.sort, 'apple_support.articles must contain exactly the four audited article keys')
    check(:source, @regions.keys.sort == codes.sort, 'apple_support.locales must cover exactly the configured locales')
    @articles.each do |key, path|
      check(:source, path.is_a?(String) && path.match?(%r{\A(?:\d+|guide/[a-z0-9-]+/[a-z0-9-]+/[a-z0-9-]+)\z}), "apple article #{key} is malformed")
    end
    @regions.each do |code, region|
      check(:source, region.is_a?(String) && region.match?(%r{\A[a-z]{2}(?:-[a-z]{2})?\z}), "apple region #{code} is malformed")
    end
    check(:source, (@guide_overrides.keys - codes).empty?, 'Apple guide overrides must name configured locales only')
    @guide_overrides.each { |code, region| check(:source, region.is_a?(String) && (region.empty? || region.match?(%r{\A[a-z]{2}(?:-[a-z]{2})?\z})), "Apple guide override #{code} is malformed") }
    check(:source, @guide_overrides['en'] == '', 'English Mac guide override must be empty')
    check(:source, @guide_overrides['ca'] == 'ca-es', 'Catalan Mac guide override must be ca-es')
    store = @links['app_store'].is_a?(Hash) ? @links['app_store'] : {}
    @store_hints = store['language_hints'].is_a?(Hash) ? store['language_hints'] : {}
    check(:source, @store_hints.keys.sort == codes.sort, 'app_store.language_hints must cover exactly the configured locales')
    @store_hints.each do |code, hint|
      check(:source, hint.is_a?(String) && hint.match?(/\A[a-z]{2}(?:-[A-Z][a-z]{3})?(?:-[A-Z]{2})?\z/), "App Store language hint #{code} is malformed")
    end
    {
      'en' => 'en-US', 'nb' => 'nb-NO', 'pt' => 'pt-PT', 'pt-BR' => 'pt-BR',
      'zh-Hans' => 'zh-Hans-CN', 'zh-Hant' => 'zh-Hant-TW'
    }.each do |code, hint|
      check(:source, @store_hints[code] == hint, "App Store #{code} must retain its audited #{hint} language hint")
    end
    validate_app_store_include
  end

  def configure_origin
    @origin = URI.parse(@config['url'].to_s)
    valid = @origin.is_a?(URI::HTTP) && !@origin.host.to_s.empty?
    check(:source, valid, '_config.yml url must be an absolute HTTP(S) origin')
    @origin = nil unless valid
  rescue URI::InvalidURIError
    add_error(:source, '_config.yml url must be an absolute HTTP(S) origin')
    @origin = nil
  end

  def validate_document(file)
    @counts[:pages] += 1
    doc = Nokogiri::HTML(file.read)
    relative = file.relative_path_from(@site).to_s
    locale = @locale_by_html_lang[doc.at_css('html')&.[]('lang').to_s]
    check(:site, !locale.nil?, "#{relative}: unknown or missing page language")
    policy = english_policy?(relative, doc)
    doc.css('a[href]').each do |link|
      href = link['href'].to_s.strip
      next if href.empty?
      validate_href(relative, locale, policy, href)
    end
  rescue SystemCallError => error
    add_error(:site, "#{file}: #{error.message}")
  end

  def validate_href(page, locale, policy, href)
    uri = URI.parse(href)
    if internal?(uri, href)
      @counts[:internal] += 1
      @internal_inventory[href] += 1
      return
    end
    @counts[:external] += 1
    @external_inventory[href] += 1
    if uri.scheme == 'mailto'
      check(:links, href == SUPPORT_EMAIL, "#{page}: unsupported mailto destination #{href.inspect}")
      return
    end
    unless uri.scheme == 'https'
      add_error(:links, "#{page}: unsafe external scheme in #{href.inspect}")
      return
    end
    validate_https_destination(page, locale, policy, href, uri)
  rescue URI::InvalidURIError
    add_error(:links, "#{page}: malformed href #{href.inspect}")
  end

  def internal?(uri, href)
    return true if uri.scheme.nil? && !href.start_with?('//')
    uri.scheme == @origin.scheme && uri.host == @origin.host && uri.port == @origin.port
  end

  def validate_https_destination(page, locale, policy, href, uri)
    if uri.host == 'support.apple.com'
      @counts[:apple_support] += 1
      expected = locale ? APPLE_ARTICLE_KEYS.map { |key| apple_url(locale, key) } : []
      check(:links, expected.include?(href), "#{page}: Apple Support URL #{href.inspect} is not valid for locale #{locale || 'unknown'}")
    elsif uri.host == 'apps.apple.com' || href == @config['appstore_link'].to_s
      @counts[:app_store] += 1
      check(:links, href == app_store_url(locale), "#{page}: App Store URL #{href.inspect} does not match the page's language hint")
    elsif same_url?(href, @config['your_link'].to_s)
      @counts[:developer] += 1
    elsif href == "https://www.facebook.com/#{@config['facebook_username']}"
      @counts[:facebook] += 1
    elsif href == "https://www.instagram.com/#{@config['instagram_username']}"
      @counts[:instagram] += 1
    elsif href == @config['mastodon_link'].to_s
      @counts[:mastodon] += 1
    elsif policy && href == REVENUECAT_PRIVACY
      @counts[:revenuecat] += 1
    elsif policy && href == ADMOB_PRIVACY
      @counts[:admob] += 1
    elsif [REVENUECAT_PRIVACY, ADMOB_PRIVACY].include?(href)
      add_error(:links, "#{page}: English policy URL #{href.inspect} is only allowed on the English policies page")
    else
      add_error(:links, "#{page}: unknown external destination requires audit: #{href.inspect}")
    end
  end

  def apple_url(code, key)
    fallback = @regions.key?(code) ? code : 'en'
    region = @regions[fallback]
    region = @guide_overrides[fallback] if key == 'mac_widgets' && @guide_overrides.key?(fallback)
    path = @articles[key]
    return nil unless region.is_a?(String) && path.is_a?(String)
    "https://support.apple.com/#{region.empty? ? '' : "#{region}/"}#{path}"
  end

  def english_policy?(relative, doc)
    %w[policies.html policies/index.html].include?(relative) && doc.at_css('html')&.[]('lang') == 'en-US'
  end

  def app_store_url(code, configured: @config['appstore_link'])
    default = "https://apps.apple.com/app/apple-store/id#{@config['ios_app_id']}"
    return configured unless configured == default
    hint = @store_hints[code] || @store_hints['en']
    hint ? "#{configured}?l=#{hint}" : configured
  end

  def validate_app_store_include
    cases = [
      ['no locale fallback', nil, nil, 'en'],
      ['empty locale fallback', '', '', 'en'],
      ['unknown locale fallback', 'unknown', 'fr', 'en'],
      ['page locale', nil, 'fr', 'fr'],
      ['explicit locale override', 'ja', 'fr', 'ja']
    ]
    @store_hints.each_key { |code| cases << [code, nil, code, code] }
    cases.each do |label, include_locale, page_locale, expected_locale|
      actual = render_app_store_include(include_locale, page_locale)
      check(:liquid, actual == app_store_url(expected_locale), "app-store-url #{label}: #{actual.inspect}, expected #{app_store_url(expected_locale).inspect}")
    end
    [
      'https://example.test/app?a=1&b="quoted"<tag>',
      "#{@config['appstore_link']}?ct=campaign&l=fr",
      "#{@config['appstore_link']}#details",
      "https://apps.apple.com/fr/app/apple-store/id#{@config['ios_app_id']}?l=fr"
    ].each do |configured|
      actual = render_app_store_include(nil, 'ja', configured: configured)
      check(:liquid, actual == configured, "app-store-url must preserve deliberate config override #{configured.inspect}")
    end
  end

  def render_app_store_include(include_locale, page_locale, configured: @config['appstore_link'])
    @counts[:renders] += 1
    payload = {
      'site' => {
        'data' => { 'external_links' => @links },
        'appstore_link' => configured,
        'ios_app_id' => @config['ios_app_id']
      },
      'page' => { 'locale' => page_locale },
      'include' => { 'locale' => include_locale }
    }
    Liquid::Template.parse(@source.join('_includes/app-store-url.html').read).render!(payload).strip
  rescue StandardError => error
    add_error(:liquid, "app-store-url rendering failed: #{error.class}: #{error.message}")
    ''
  end

  # Jekyll may emit a root URL without the optional trailing slash; retain
  # configuration ownership while accepting that equivalent serialization.
  def same_url?(left, right)
    a, b = URI.parse(left), URI.parse(right)
    a.scheme == b.scheme && a.userinfo == b.userinfo && a.host == b.host && a.port == b.port && a.query == b.query && a.fragment == b.fragment && a.path.sub(%r{/+\z}, '') == b.path.sub(%r{/+\z}, '')
  rescue URI::InvalidURIError
    false
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
    puts "Checked #{@counts[:pages]} built HTML pages: #{@counts[:internal]} internal anchors (#{@internal_inventory.length} unique), #{@counts[:external]} external anchors (#{@external_inventory.length} unique destinations)."
    puts "Locale-aware links: Apple Support=#{@counts[:apple_support]}, App Store=#{@counts[:app_store]}; #{@counts[:renders]} App Store include regressions."
    puts "Shared exceptions: developer=#{@counts[:developer]}, Facebook=#{@counts[:facebook]}, Instagram=#{@counts[:instagram]}, Mastodon=#{@counts[:mastodon]}, RevenueCat=#{@counts[:revenuecat]}, AdMob=#{@counts[:admob]}, mailto=#{@external_inventory[SUPPORT_EMAIL]}."
    puts(total.zero? ? 'PASS: all external-link validation checks passed.' : "FAIL: #{total} external-link validation errors.")
    total.zero?
  end
end

if $PROGRAM_NAME == __FILE__
  options = { source: Dir.pwd, verbose: false }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: validate-external-links.rb [options]'
    opts.on('--source PATH', 'Project source (default: current directory)') { |value| options[:source] = value }
    opts.on('--site PATH', 'Built site (default: SOURCE/_site)') { |value| options[:site] = value }
    opts.on('--verbose', 'Show every validation failure') { options[:verbose] = true }
  end
  parser.parse!
  options[:site] ||= File.join(options[:source], '_site')
  exit(ExternalLinksValidator.new(**options).run ? 0 : 1)
end
