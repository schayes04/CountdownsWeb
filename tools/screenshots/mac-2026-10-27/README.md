# Mac desktop capture (October 27, 2026)

`assets/screenshots-mac/<locale>/desktop.png` is a 2048×1536 capture of a Mac
desktop for each of the 38 site locales: the Countdowns window in grid view next to
a Large and two Small custom widgets (Beach trip, Mom's birthday, Wedding). It is
the hero image of `/mac-countdown-widget/` in every locale.

- Built from the Countdowns Beta 12.3 Mac Catalyst app with the debug-only
  `widgetScreenshots` sample data, lifetime unlock on and notifications allowed.
  The app and widgets were launched in each locale's language and region; the
  widget extension used the debug-only screenshot language override.
- Each image is a composite of separate native captures of the wallpaper, the
  three widgets and the app window (with its shadow) at their real desktop
  positions and Retina pixels, cropped to 4:3 and resized with Lanczos to
  2048×1536. No menu bar. Text and widget pixels are not edited.
- The app window is 632×476pt, or 632×506pt for `de` and `el`, whose two-unit
  times wrap to two lines.
- `ar` uses the Gregorian calendar. Day and hour counts differ slightly between
  locales because the captures ran over about 30 minutes.
- `provenance.json` lists each source file's size and SHA-256.

The `/mac-countdown-widget/` frame crops the 4:3 image to its 16:10 display,
trimming only wallpaper. WebP derivatives come from
`python3 tools/screenshots/mac-derivatives.py`.
