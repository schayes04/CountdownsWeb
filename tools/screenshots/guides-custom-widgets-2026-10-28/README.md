# Guide screenshots with custom widgets (2026-10-28)

Six guide scenes were recaptured as iPhone Home Screens with Countdowns 12.3
custom widgets, in all 38 site locales: `wedding-countdown-app`,
`vacation-countdown-app`, `anniversary-countdown-app`,
`theme-park-trip-countdown-app`, `holiday-countdown-app` and
`christmas-countdown-app`. Christmas was previously a Lock Screen scene.

- `capture-manifest.json`: locale, scene, SHA-256 and size of every capture.
- `photos.json`: the Unsplash photos the widgets use, picked through the app's
  Stock Photos feature, with photographer credits.
- `widget-specs.py`: each widget's layout, photo, gradient and darkening.

en-CA captures were identical to en, so en-CA keeps using the en files.
en-GB and en-AU have their own files (day-month dates, "Holiday" wording).
