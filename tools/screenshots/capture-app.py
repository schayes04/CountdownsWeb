#!/usr/bin/env python3
"""Capture native app PNGs on an already installed, disposable Simulator.

Requires the capture-only native patch and generated fixtures. Does not build,
erase a simulator, change a real account, or publish the website. Evidence is
written separately from the public images. Widget surfaces use a separate flow.
"""

import argparse
import hashlib
import json
import os
import struct
import subprocess
import time
from datetime import date, datetime, timezone
from pathlib import Path


BUNDLE_ID = "com.shayesapps.countdownApp"
APP_SCENES = (
    "normal-display", "compact-display", "colors", "editing", "settings",
    "birthday-countdown-app", "holiday-countdown-app", "retirement-countdown-app",
    "pregnancy-countdown-app", "event-countdown-app",
)


def simctl(*args, env=None, timeout=40):
    result = subprocess.run(
        ["xcrun", "simctl", *args], env=env, capture_output=True, text=True,
        check=False, timeout=timeout,
    )
    if result.returncode:
        # Never include the fixture-bearing environment in failure output.
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_proof(proof, fixture, apple_locale):
    expected = {
        "scene": fixture["scene"], "requestedLocale": fixture["locale"],
        "screen": fixture["screen"], "isLifetimeUser": True, "isProUser": True,
        "appVersion": "12.0.0", "theme": "light",
        "currentLocaleIdentifier": apple_locale,
    }
    for key, value in expected.items():
        if proof.get(key) != value:
            raise ValueError(f"Proof {key}: expected {value!r}, got {proof.get(key)!r}")
    if proof.get("preferredLocalizations", [None])[0] != fixture["locale"]:
        raise ValueError(f"Wrong app localization: {proof.get('preferredLocalizations')}")
    expected_events = [{"id": event["id"], "name": event["name"]} for event in fixture["events"]]
    if proof.get("events") != expected_events:
        raise ValueError("The saved events do not match this scene's localized fixture")
    for setting in ("compact", "listsEnabled", "showDates", "showDirection"):
        if proof["settings"].get(setting) != fixture[setting]:
            raise ValueError(f"Wrong native setting: {setting}")
    if proof["settings"]["iCloudSync"] or proof["settings"]["countdownEndNotifications"]:
        raise ValueError("Demo capture must not sync or schedule notifications")


def capture(args, index, locale, scene, container):
    folder = index["locales"][locale]["folder"]
    fixture_path = args.fixtures / index["locales"][locale]["fixtures"][scene]
    fixture = json.loads(fixture_path.read_text())
    apple_locale = index["appleLocales"][locale]
    output = args.output / folder / f"{scene}.png"
    evidence = args.evidence / folder / f"{scene}.json"
    if args.resume and output.exists() and evidence.exists():
        previous = json.loads(evidence.read_text())
        if (previous.get("fixtureSHA256") == digest(fixture_path)
                and previous.get("imageSHA256") == digest(output)):
            validate_proof(previous["nativeProof"], fixture, apple_locale)
            print(f"VERIFIED {locale}/{scene}", flush=True)
            return
    output.parent.mkdir(parents=True, exist_ok=True)
    evidence.parent.mkdir(parents=True, exist_ok=True)
    proof_path = container / "Documents" / "website-screenshot-proof.json"
    # This one file is produced by our isolated demo fixture, never user data.
    proof_path.unlink(missing_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("SIMCTL_CHILD_")}
    env.update({
        "SIMCTL_CHILD_screenshots": "true",
        "SIMCTL_CHILD_isProUser": "true",
        "SIMCTL_CHILD_websiteScreenshotFixture": json.dumps(fixture, ensure_ascii=False),
    })
    launch_args = [
        "-AppleLanguages", f"({locale})", "-AppleLocale", apple_locale,
        "-isProUserKey", "YES", "-isLifetimeUserKey", "YES",
    ]
    started = datetime.now(timezone.utc).isoformat()
    simctl("launch", "--terminate-running-process", args.simulator, BUNDLE_ID, *launch_args, env=env)
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline:
        if proof_path.exists():
            proof = json.loads(proof_path.read_text())
            validate_proof(proof, fixture, apple_locale)
            break
        time.sleep(0.25)
    else:
        raise RuntimeError(f"No ready proof for {locale}/{scene}; refusing to capture")
    time.sleep(args.settle)
    pending = output.with_suffix(".pending.png")
    simctl("io", args.simulator, "screenshot", "--type=png", str(pending))
    header = pending.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", header[16:24]) != (1206, 2622):
        raise RuntimeError(f"Unexpected capture dimensions or format: {pending}")
    pending.replace(output)
    record = {
        "locale": locale, "scene": scene, "surface": "app",
        "device": "iPhone 17 Pro", "os": "iOS 27.0", "simulator": args.simulator,
        "sourceCommit": args.source_commit, "referenceDate": index["referenceDate"],
        "captureStartedAt": started, "capturedAt": datetime.now(timezone.utc).isoformat(),
        "width": 1206, "height": 2622, "imageSHA256": digest(output),
        "fixtureSHA256": digest(fixture_path), "launchArguments": launch_args,
        "nativeProof": proof,
    }
    evidence.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print(f"CAPTURED {locale}/{scene} · lifetime Pro · {output.stat().st_size:,} bytes", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Dedicated, booted simulator UUID")
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--locales", help="Comma-separated locale codes; default all")
    parser.add_argument("--scenes", help="Comma-separated app scenes; default all ten")
    parser.add_argument("--settle", type=float, default=2.0)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    index = json.loads((args.fixtures / "batch-index.json").read_text())
    if index["referenceDate"] != date.today().isoformat():
        parser.error("Regenerate fixtures for today's date before capturing live countdowns")
    locales = args.locales.split(",") if args.locales else list(index["locales"])
    scenes = args.scenes.split(",") if args.scenes else list(APP_SCENES)
    if set(locales) - index["locales"].keys() or set(scenes) - set(APP_SCENES):
        parser.error("Unknown locale or non-app scene requested")
    if not 0.5 <= args.settle <= 30:
        parser.error("--settle must be between 0.5 and 30 seconds")
    container = Path(simctl("get_app_container", args.simulator, BUNDLE_ID, "data"))
    simctl("ui", args.simulator, "appearance", "light")
    # simctl's date parser requires milliseconds and an unseparated UTC offset.
    clock = f"{index['referenceDate']}T09:41:00.000{datetime.now().astimezone():%z}"
    simctl("status_bar", args.simulator, "override", "--time", clock,
           "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
           "--cellularMode", "active", "--cellularBars", "4",
           "--batteryState", "discharging", "--batteryLevel", "100")
    for locale in locales:
        for scene in scenes:
            capture(args, index, locale, scene, container)


if __name__ == "__main__":
    main()
