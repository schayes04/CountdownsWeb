#!/usr/bin/env python3
"""spec.py USECASE -> design spec JSON on stdout. Slots match the placed Home Screen widgets."""
import json, sys
L, R, B = "00000000-0000-4000-8000-000000000005", "00000000-0000-4000-8000-000000000002", "00000000-0000-4000-8000-000000000001"
def stock(k): return {"photo": f"{k}.jpg", "unsplash": f"{k}.photo.json"}
cases = {
    "wedding": ["wedding-1", "wedding-2", "wedding-3"],
    "vacation": ["vacation-1", "vacation-2", "vacation-3"],
    "anniversary": ["anniversary-1", "anniversary-2", "anniversary-3"],
    "themepark": ["themepark-1", "themepark-2", "themepark-3"],
    "holiday": ["holiday-1", "holiday-2", "Fireworks"],
    "christmas": ["christmas-1", "Fireworks", "christmas-3"],
}
keys = cases[sys.argv[1]]
out = []
for slot, key, n, layout, size in ((L, keys[0], 1, "largePhoto", "large"), (R, keys[1], 2, "smallPhoto", "small"), (B, keys[2], 3, "smallPhoto", "small")):
    # A bit darker than the app's 45% default, so white text holds up on every photo.
    spec = {"id": slot, "layout": layout, "size": size, "event": f"website-event-{n}", "overlay": 0.6}
    spec.update({"photo": key} if key == "Fireworks" else stock(key))
    out.append(spec)
# Per-widget tweaks so the text stays readable on light photos; one non-photo small widget at most per screen.
tweaks = {
    ("wedding", 0): {"layout": "largePhotoCentered", "overlay": 0.85},
    ("anniversary", 0): {"layout": "largePhotoCentered", "overlay": 0.85},
    ("themepark", 0): {"layout": "largePhotoCentered", "overlay": 0.85},
    ("vacation", 1): {"layout": "smallNumber", "photo": None, "unsplash": None,
                      "gradient": [0.96, 0.62, 0.36, 0.80, 0.33, 0.20]},
    ("vacation", 2): {"overlay": 0.85},
    ("anniversary", 2): {"layout": "smallNumber", "photo": None, "unsplash": None,
                         "gradient": [0.93, 0.74, 0.36, 0.66, 0.44, 0.12]},
}
for i, spec in enumerate(out):
    for k, v in tweaks.get((sys.argv[1], i), {}).items():
        if v is None: spec.pop(k, None)
        else: spec[k] = v
print(json.dumps(out))
