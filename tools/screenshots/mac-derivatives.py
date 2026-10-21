#!/usr/bin/env python3
"""Generate or check WebP derivatives for the native Mac website captures.

Sources are listed in _data/mac_screenshots.yml. Requires Pillow (with WebP) and
PyYAML. The PNGs stay the unedited native sources; only resized copies are
written. Run with --check to verify the recorded hashes without re-encoding.
"""

import argparse
import hashlib
import io
import json
import sys
from pathlib import Path

import yaml
from PIL import Image, features


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "_data/mac_screenshots.yml"
MANIFEST = ROOT / "_data/mac_screenshot_variants.json"
WIDTHS = [480, 960, 1440]
QUALITY = 85


def asset(path):
    return ROOT / path.lstrip("/")


def sha256(path):
    return hashlib.sha256(asset(path).read_bytes()).hexdigest()


def sources():
    config = yaml.safe_load(CONFIG.read_text())
    paths = {path for scenes in config["locales"].values() for path in scenes.values()}
    return config, sorted(paths)


def record(path, width, height):
    return {"path": path, "width": width, "height": height,
            "bytes": asset(path).stat().st_size, "sha256": sha256(path)}


def check():
    config, paths = sources()
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("widths") != WIDTHS or manifest.get("quality") != QUALITY:
        sys.exit("Unexpected encoder settings")
    if sorted(manifest["screenshots"]) != paths:
        sys.exit("Derivative source coverage differs from mac_screenshots.yml")
    for path in paths:
        entry = manifest["screenshots"][path]
        with Image.open(asset(path)) as image:
            if image.size != (config["width"], config["height"]):
                sys.exit(f"{path}: expected {config['width']}x{config['height']}, got {image.size}")
        if entry["source_sha256"] != sha256(path):
            sys.exit(f"Stale source: {path}")
        for variant in entry["variants"]:
            if asset(variant["path"]).stat().st_size != variant["bytes"] or sha256(variant["path"]) != variant["sha256"]:
                sys.exit(f"Missing/modified derivative: {variant['path']}")
    print(f"PASS: Mac screenshot source and derivative hashes ({len(paths)} screenshots)")


def generate():
    if not features.check("webp"):
        sys.exit("Pillow was built without WebP support")
    config, paths = sources()
    entries = {}
    for path in paths:
        with Image.open(asset(path)) as image:
            image.load()
            if image.size != (config["width"], config["height"]):
                sys.exit(f"{path}: expected {config['width']}x{config['height']}, got {image.size}")
            variants = []
            for width in WIDTHS:
                height = round(width * config["height"] / config["width"])
                output = path.replace(".png", f"-{width}.webp")
                buffer = io.BytesIO()
                image.resize((width, height), Image.LANCZOS).save(buffer, "WEBP", quality=QUALITY, method=6)
                asset(output).write_bytes(buffer.getvalue())
                variants.append(record(output, width, height))
        entries[path] = {"source": path, "source_sha256": sha256(path), "variants": variants}
    manifest = {"encoder": f"Pillow {Image.__version__} (libwebp {features.version('webp')})",
                "quality": QUALITY, "widths": WIDTHS, "screenshots": entries}
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Generated {len(entries) * len(WIDTHS)} WebP images.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="verify hashes without re-encoding")
    check() if parser.parse_args().check else generate()
