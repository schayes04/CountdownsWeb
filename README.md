# Automatic App Landing Page
**Create and deploy an iOS app landing page on GitHub Pages in only five minutes.**

Designed for GitHub Pages for super easy set up. 

🔧 Fork this repo

🗝 Enter iOS App ID in `_config.yml`

📲 Upload video preview or screenshot

🎨 Customise site in `_config.yml` (no HTML/CSS)

📝 Write Privacy Policy as markdown in `privacypolicy.md`

🕒 Keep a changelog in `CHANGELOG.md`

✅ Site becomes live at GitHub Pages repository URL, e.g. `https://your-username.github.io/your-repo-name/`.

<img src="https://emilbaehr.com/files/jayson1.png" width="440"> <img src="https://emilbaehr.com/files/slor1.png" width="440">




## Quick Start

### Step 1: Fork this repo.
After forking the repo, your site will be live immediately on your personal Github Pages account, e.g. `https://yourusername.github.io/your-repo-name/`.

*Make sure GitHub Pages is enabled for your repo. It might take some time for the site to propagate entirely.*



### Step 2: Enter iOS App ID in `_config.yml`
Enter your iOS app ID in the `ios_app_id` field and commit your changes. Your site will automatically rebuild with your app icon, name, price and link to App Store.

You can go on with customising almost anything in the `_config.yml` file. 

Things you can customise in `_config.yml`:
- App Name
- App Icon
- App Description
- App Price
- App Store Link
- Play Store Link
- Press Kit Download Link
- Cover Image
- Cover Overlay Color
- Background Color
- Text Colors
- iPhone Device Color
- Your Name / Company Name
- Link to Website
- Social Links and Contact Info
- Feature List (Title, text, icon)



### Step 3: Add screenshot or video

#### Adding a screenshot
Upload a `.png` or `.jpg` of your app to the folder `assets/screenshot/`. The name does not matter. Be sure to delete the placeholder `yourscreenshot.png`.

#### Adding video
Upload your video to the folder `assets/videos/`. To have support for most browsers, you need to upload two files – one for Safari and one for Chrome/Firefox.

Video formats supported by Chrome and Firefox:
- `.webm`
- `.ogg`

Video formats supported by Safari:
- `.mp4`
- `.mov`

#### Resolutions
The videos and screenshots must have one of the following resolutions:
- 828x1792
- 1125x2436
- 1242x2688



### Step 4: Edit (or remove) Privacy Policy and Changelog
Your site automatically includes pages for a Privacy Policy and a Changelog. Change the content of these pages by editing the `privacypolicy.md` and `CHANGELOG.md` files in the `_pages` directory.

In each of the markdown files, you can set the `include_in_header:` value to either `true` or `false`. This determines if the page is included in the top navigation.
By default, only the Changelog is included in the top navigation. The title of the navigation item can also be edited, by editing the `title:` in each markdown file.

If you need to, you can create additional markdown based pages just by creating an `.md` file like the `privacypolicy.md` and `CHANGELOG.md` files in the `_pages` directory.

**Please note:** The Privacy Policy and Changelog provided are written using dummy text, so please adapt each of them for your own app.
You can also choose not to include these pages, by simple deleting the `privacypolicy.md` and `CHANGELOG.md` files.




## Feedback
If you have feedback regarding bugs or improvements, open an issue, @ me on Twitter or write me an email. You can find my contact info on my website.

I'd love to see the sites you create using this little tool.

## Localized app names

Each entry in `_data/locales.yml` defines the app's localized `app_name`, sourced from `CFBundleDisplayName` in the native app's `Countdown/Supporting Files/InfoPlist.xcstrings` catalog. These are the app's display names, not translations invented for the website or the longer App Store marketing titles. English and German retain **Countdowns**; Dutch uses **Aftellingen**; the other languages use their native app names.

Shared branding and metadata use this name, falling back to `_config.yml`'s `app_name` for an unknown locale. Keep app references in `_data/strings.yml`, `_data/screenshot_alts.yml`, and the validator's native-name baseline in sync when a name changes; complete translated sentences preserve the grammar around each name.

After building, check branding, copy, accessibility text, and metadata across every home, ideas, guide, and Support page:

```sh
bundle exec ruby scripts/validate-app-names.rb --site _site
```

When the native repository is available, also pass `--native-catalog "/path/to/Countdowns/Countdown/Supporting Files/InfoPlist.xcstrings"` to verify the names directly against the app's catalog.

## Localized Support and navigation

`support.md` is the English Help Center source. Its existing `/support` URL is preserved; translations live at `<locale folder>/support/index.md` and use directory URLs. Keep the section IDs and order, troubleshooting steps, external-link destinations (using their localized equivalents), and `source_version` aligned with English when updating translations. Keep native app names intact, adapting the surrounding grammar as needed. Policies remain English-only and opt out of localization with `localized: false`.

The shared `_includes/locale-url.html` helper keeps language switching, alternate links, the footer's Help Center link, and sitemap routes consistent. Shared accessibility text and the menu label are translated in `_data/strings.yml`.

The header keeps the app name visible. At widths of 1120px or less, all navigation moves into a single disclosure menu; its nested language list stays within the scrollable panel. Desktop and compact navigation share `_includes/navigation-items.html`. The native disclosures work without JavaScript; `assets/header.js` adds outside-click dismissal, Escape/focus handling, and breakpoint cleanup. Keep its media query in sync with `_sass/layout.scss`.

After building, validate all 330 localized routes, Support content structure, language links, accessibility labels, internal links, and the sitemap:

```sh
bundle exec ruby scripts/validate-localization.rb --site _site
node scripts/validate-header.js
```

For a build using a subdirectory, pass the same `--baseurl /prefix` to the localization validator. Browser checks should also cover narrow screens, long localized names, Arabic right-to-left layout, and keyboard navigation.

## External-link audit and localization

The 2026-08-31 audit covered all 331 generated HTML pages, including the English policies page: 20,446 internal anchors and 2,713 external anchors (114 unique destinations, including email). All internal page and fragment links resolved. Apple Support's 85 unique target URLs were checked with real GET requests, redirects, and rendered language metadata, not just URL patterns or HTTP status.

Support links use `_includes/apple-support-url.html` and `_data/external_links.yml`. Keep the article keys shared across translations; the include selects Apple's supported language/region code. This preserves European/Brazilian Portuguese and Simplified/Traditional Chinese and maps Norwegian Bokmål to Apple's `no-no` routes. Unknown locales fall back to English.

Catalan is a per-article exception: Apple's [Mac widgets guide](https://support.apple.com/ca-es/guide/mac-help/mchl52be5da5/mac) is available in Catalan, but the three standalone articles do not advertise Catalan versions. Those links use English and are labeled “en anglès” with `hreflang="en"`.

| Other destination | Audit result and language handling |
| --- | --- |
| App Store | Navigation and badges use the country-neutral link with an explicit language hint. Apple still chooses the country/storefront; it may fall back to a supported language or regional variant. See [Apple's locale table](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/). Country-specific URLs can improve language matching but also change displayed currency and reviews, so they are not inferred from the site's language. |
| [Shayes Apps](https://shayesapps.com/) | English-only site; no localized equivalents were found. Use the canonical shared URL. |
| Facebook and Instagram | Use the verified `www` profile URLs. No profile-specific language override was verified; retain the provider's own language/account preferences. Public profile text could not be inspected by the automated fetch. |
| Mastodon | Keep the shared profile URL; the provider handles UI language. The public response was a JavaScript application shell, not translated profile content. |
| [RevenueCat privacy](https://www.revenuecat.com/privacy) | English-only destination from the English policies page; unchanged. |
| [Google AdMob privacy information](https://support.google.com/admob/answer/6128543?hl=en) | Google supports localized `hl` values; the only link is on the English policies page, so `hl=en` is correct. |
| Email | `mailto:support@shayesapps.com` is language-neutral and unchanged. |

The social, developer, RevenueCat, and Google destinations returned HTTP 200 during the audit. HTTP success alone does not prove that social-profile content is translated. App Store JSON-LD `sameAs` and `schema.org` are identifiers, not navigation links.

`_includes/app-store-url.html` applies the audited hints in `external_links.yml` to the standard country-neutral `appstore_link` for `ios_app_id`. Explicit configuration overrides (including campaign, fragment, country-specific, or custom URLs) are preserved unchanged. Unknown locales fall back to the English hint. Use the exact `zh-Hant-TW` hint for Traditional Chinese and `nb-NO` for Norwegian Bokmål: the shorter `zh-Hant` and `no` forms did not select the intended languages in the audit. These remain best-effort hints, not promises about the visitor's final storefront language.

All 22 emitted App Store URLs were checked. The final verification sweep returned 19 HTTP 200 responses and three Apple rate-limit responses (`it`, `pt`, `pt-BR`); those three exact URLs had already returned valid pages earlier in the audit. There were no observed 404 or server-error responses. Avoid repeated high-volume checks, and distinguish temporary rate limits from broken URLs.

After building, run the offline external-link regression checks along with the localization validator:

```sh
bundle exec ruby scripts/validate-external-links.rb --site _site
bundle exec ruby scripts/validate-localization.rb --site _site
```

New external destinations must be audited before being added to the validator's known shared exceptions. Recheck provider language support when changing an article or adding a site locale.

## Localized App Store badges

Pages use the shared `_includes/app-store-badge.html` include to select official Apple artwork from `_data/app_store_badges.yml`. SVGs are stored locally in `assets/app-store-badges/`, with English as the fallback for an unknown locale. Badge labels use the existing `download_badge` translations.

Keep Apple's SVG artwork unmodified and follow the [App Store badge guidelines](https://developer.apple.com/app-store/marketing/guidelines/#section-badges). The artwork download endpoint is recorded in the badge map; note that Arabic uses `ar-ar`, Norwegian Bokmål uses `no-no`, and Portuguese and Chinese each have separate regional/script variants. These artwork codes are separate from the App Store link hints above.

After building the site, validate the artwork, locale fallback, accessible labels, and every home/ideas/guide page with:

```sh
bundle exec ruby scripts/validate-app-store-badges.rb --site _site
```

For a build using a subdirectory, pass the same `--baseurl /prefix` to the validator.

## Credits
- [Jekyll](https://github.com/jekyll/jekyll)
- [FontAwesome](https://fontawesome.github.io/Font-Awesome/)

## Donations
[Donations are welcome](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=S8ZZT3JXJPN92&currency_code=USD&source=url)

## Author
[Emil Baehr](https://emilbaehr.com/)

## License
[MIT License](LICENSE)
