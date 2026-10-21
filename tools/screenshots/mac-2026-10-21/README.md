# Mac app window capture (October 21, 2026)

`assets/screenshots-mac/en/app-window.png` is a native 2048×1536 capture of the
Countdowns Mac Catalyst window (app 12.3.0, macOS 27.0.1). It is the hero image
of `/mac-countdown-widget/` for `en` and `en-CA`; the page in other locales keeps
its localized iPhone screenshot. `en-GB` and `en-AU` need their own capture,
because the fixture says "Vacation" rather than "Holiday".

- Captured with `screencapture -x -o -l<CGWindowID>`: window only, no shadow,
  transparent corners. No pixels were edited. The hero frame lets the window's
  empty lower half run off the display in CSS; the PNG itself is complete.
- The capture build was an isolated Debug copy (`.maccapture` bundle IDs and app
  group, no iCloud) loaded with the English fixture from
  `generate-fixtures.py --date 2026-10-20`. It never touched real data.
- `provenance.json` records the source commit, binary hashes, the capture patch
  hash, the fixture hash and the PNG hash. The patch and fixture files are kept
  outside the repository.
- Desktop widgets were not captured. The capture widget extension rendered blank
  without a provisioning profile; `provenance.json` (`widgetFindings`) lists what
  to try next.

WebP derivatives are made with `python3 tools/screenshots/mac-derivatives.py`
(Pillow, quality 85, 480/960/1440px) and recorded in
`_data/mac_screenshot_variants.json`; `--check` verifies them, and
`scripts/validate-screenshots.rb` checks the built pages.
