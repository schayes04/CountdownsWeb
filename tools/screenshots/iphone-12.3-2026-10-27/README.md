# iPhone 12.3 captures (October 27, 2026)

171 native 1206×2622 PNGs from the Countdowns 12.3.0 Debug build (develop) on
iOS 27.0 iPhone 17 Pro simulators, with lifetime Pro and notifications allowed.
`capture-manifest.json` lists each file's locale, scene, size and SHA-256.

- **New scenes, all 38 locales (76):** `home-screen-custom-widgets` (Large Beach
  trip photo widget, Small Mom's birthday photo widget and Small Wedding gradient
  widget on the blue site wallpaper) and `widget-editor` (the Beach trip widget on
  the editor's Background tab). The widgets come from the app's `widgetScreenshots`
  sample data, placed through the Home Screen widget gallery in each language.
- **es-MX (17):** the full scene set, made with `capture-app.py`,
  `capture-widgets.py` and fixtures generated for es-MX.
  `es-mx-capture-tools.patch` holds the local tool changes, and `fixtures-es-mx/`
  the generated fixtures. The widget captions under Home Screen widgets read
  "Cuentas atrás": the simulator showed the Spain app name in Mexican Spanish.
- **ar, ca, el, fr, hu, ro (78):** the 13 scenes that show the app name, recaptured
  so they show the shorter 12.3 app names. Lock Screen widgets, editing and event
  scenes never show it and keep their earlier captures.

Capture-only changes (the site's `native-capture.patch`, opening the editor on a
widget's Background tab, hiding tips, suppressing the rating prompt) were applied
to a scratch copy of the app, not committed. Filipino shows "Layout" and
"Background" in English in the editor, as the app translates them.

WebP derivatives for these files were encoded with cwebp 1.3.2 (recorded per entry
in `_data/responsive_images.json`); the rest of the set keeps its 1.6.0 encodes.
