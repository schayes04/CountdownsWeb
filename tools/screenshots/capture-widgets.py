#!/usr/bin/env python3
"""Capture seven real system-widget scenes on an opt-in disposable Simulator.

Requires an installed capture-patched app and main's prepared Home/Lock layouts.
Temporarily changes ONLY the selected simulator's global language/locale plist,
then restores its original bytes and reboots in finally. No build/install/erase.
Timeline proof is data evidence, NOT proof that pixels rendered correctly.
This implementation requires main's navigation/locale pilot before batch use.
"""

import argparse
from contextlib import contextmanager
import fcntl
import importlib.util
import json
import math
import os
import plistlib
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path


HOME_SCENES = (
    "home-screen-widgets", "wedding-countdown-app", "vacation-countdown-app",
    "anniversary-countdown-app", "theme-park-trip-countdown-app",
)
LOCK_SCENES = ("lock-screen-widgets", "christmas-countdown-app")
SCENES = HOME_SCENES + LOCK_SCENES
HOME_FAMILIES = {"systemMedium": 3, "systemLarge": 8}
LOCK_FAMILIES = {"accessoryRectangular": 0, "accessoryCircular": 1, "accessoryInline": 2}
FAMILIES = (*HOME_FAMILIES, *LOCK_FAMILIES)
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
APP_GROUP = "group.com.shayesapps.countdown"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def load_app_helpers():
    path = Path(__file__).resolve().with_name("capture-app.py")
    spec = importlib.util.spec_from_file_location("countdowns_capture_app", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load capture helpers: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"Expected a JSON object: {path}")
    return value


def utc_now():
    return datetime.now(timezone.utc)


def timestamp(value):
    require(isinstance(value, str), "Proof timestamp must be an ISO-8601 string")
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(result.tzinfo is not None, "Proof timestamp must include a timezone")
    return result.astimezone(timezone.utc)


def inside(path, root):
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def child_path(root, relative):
    require(isinstance(relative, str) and relative, "Missing relative path")
    value = Path(relative)
    require(not value.is_absolute() and ".." not in value.parts, "Unsafe relative path")
    result = root / value
    require(inside(result, root) and result.resolve() != root.resolve(), "Path escapes its root")
    return result


def atomic_write(path, content, mode=0o600):
    require(not path.is_symlink(), f"Refusing symlink destination: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    pending = Path(name)
    try:
        with os.fdopen(fd, "wb") as output:
            os.fchmod(output.fileno(), mode)
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        pending.replace(path)
    finally:
        pending.unlink(missing_ok=True)


def write_json(path, value):
    atomic_write(path, (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode())


def device_record(helpers, simulator):
    listing = json.loads(helpers.simctl("list", "devices", "--json"))
    matches = [dict(device, runtime=runtime)
               for runtime, devices in listing["devices"].items()
               for device in devices if device.get("udid", "").upper() == simulator]
    require(len(matches) == 1, "Simulator UUID does not identify exactly one device")
    device = matches[0]
    require(device.get("isAvailable") is True, "Capture simulator is unavailable")
    require(device.get("name", "").startswith("Countdowns V12"),
            "Refusing simulator without the 'Countdowns V12' name prefix")
    require(device.get("deviceTypeIdentifier") == DEVICE_TYPE, "Expected iPhone 17 Pro")
    require(device["runtime"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-27-"),
            "Expected an iOS 27 capture runtime")
    return device


def simulator_home(helpers, simulator, device):
    # simctl getenv returns the device data directory, not the host user's HOME.
    raw = Path(helpers.simctl("getenv", simulator, "HOME"))
    require(raw.is_absolute(), "Simulator HOME must be absolute")
    data = raw.resolve(strict=True)
    require(data.name == "data" and data.parent.name.upper() == simulator,
            "Simulator HOME must resolve to this UUID/data directory")
    if device.get("dataPath"):
        require(data == Path(device["dataPath"]).resolve(), "Simulator HOME/dataPath mismatch")
    return data


class SimulatorPreferences:
    """A scoped transaction on one verified simulator's existing preferences.

    Never writes SpringBoard preferences, IconState/listMetadata, or page layout.
    Main's prepared one-visible-page widget baseline must remain intact.
    """

    def __init__(self, helpers, simulator, data, evidence):
        self.helpers, self.simulator, self.data = helpers, simulator, data
        self.path = child_path(data, "Library/Preferences/.GlobalPreferences.plist")
        self.backup = child_path(evidence, "run-config/original-global-preferences.plist")
        self.record = child_path(evidence, "run-config/global-preferences-transaction.json")
        self.original = None
        self.touched = False
        self.mode = None
        self.details = None

    def stop(self):
        state = device_record(self.helpers, self.simulator)["state"]
        if state == "Booted":
            self.helpers.simctl("shutdown", self.simulator, timeout=90)
        else:
            require(state == "Shutdown", f"Unexpected simulator state: {state}")
        require(device_record(self.helpers, self.simulator)["state"] == "Shutdown",
                "Simulator must be shut down before writing preferences")

    def boot(self):
        state = device_record(self.helpers, self.simulator)["state"]
        if state == "Shutdown":
            self.helpers.simctl("boot", self.simulator, timeout=90)
        else:
            require(state == "Booted", f"Unexpected simulator state: {state}")
        self.helpers.simctl("bootstatus", self.simulator, "-b", timeout=180)
        require(device_record(self.helpers, self.simulator)["state"] == "Booted",
                "Simulator did not finish booting")

    def begin(self):
        require(self.path.is_file() and not self.path.is_symlink(),
                "Expected an existing, regular simulator global-preferences plist")
        # Do not overwrite recovery evidence from an interrupted prior invocation.
        if self.backup.exists() or self.record.exists():
            previous = read_json(self.record)
            require(self.backup.is_file() and previous.get("restored") is True
                    and previous.get("simulator") == self.simulator
                    and previous.get("preferencesPath") == str(self.path)
                    and previous.get("originalSHA256") == self.helpers.digest(self.backup),
                    "Unrestored/mismatched preference backup; main must recover it before retrying")
        self.touched = True  # Even a later backup/read failure must re-boot this device.
        self.stop()
        require(inside(self.path, self.data) and not self.path.is_symlink(), "Unsafe preferences path")
        original = self.path.read_bytes()
        require(isinstance(plistlib.loads(original), dict), "Global preferences must be a dictionary")
        self.mode = stat.S_IMODE(self.path.stat().st_mode)
        self.original = original
        atomic_write(self.backup, original, self.mode)
        self.details = {
            "simulator": self.simulator, "preferencesPath": str(self.path),
            "originalSHA256": self.helpers.digest(self.backup),
            "startedAt": utc_now().isoformat(), "restored": False,
        }
        write_json(self.record, self.details)

    def set_locale(self, code, apple_locale):
        require(self.original is not None and self.details is not None, "Preferences not backed up")
        self.stop()
        require(inside(self.path, self.data) and not self.path.is_symlink(), "Unsafe preferences path")
        # Read after shutdown so CFPreferences has flushed; preserve EVERY other field.
        current_bytes = self.path.read_bytes()
        current = plistlib.loads(current_bytes)
        require(isinstance(current, dict), "Global preferences must be a dictionary")
        current["AppleLanguages"] = [code]
        current["AppleLocale"] = apple_locale
        fmt = plistlib.FMT_BINARY if current_bytes.startswith(b"bplist") else plistlib.FMT_XML
        atomic_write(self.path, plistlib.dumps(current, fmt=fmt, sort_keys=False), self.mode)
        self.boot()

    def restore(self):
        if not self.touched:
            return
        # Best effort on process signals: SIGKILL/power loss still requires the backup.
        handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
        try:
            self.stop()
            if self.original is not None:
                require(inside(self.path, self.data) and not self.path.is_symlink(), "Unsafe restore path")
                atomic_write(self.path, self.original, self.mode)
                require(self.path.read_bytes() == self.original, "Preference restore verification failed")
            self.boot()
            if self.details is not None:
                self.details.update(restored=True, restoredAt=utc_now().isoformat())
                write_json(self.record, self.details)
            print("RESTORED original simulator global preferences; simulator booted.", flush=True)
        except Exception as error:
            raise RuntimeError(f"PREFERENCE RESTORE FAILED: {error}. Preserve backup {self.backup}; "
                               f"main must recover {self.path} before continuing.") from error
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)


def strict_app_proof(helpers, proof, fixture, apple_locale, launched_at):
    require(isinstance(proof, dict), "Missing native proof object")
    helpers.validate_proof(proof, fixture, apple_locale)
    require(proof.get("isLifetimeUser") is True and proof.get("isProUser") is True,
            "Lifetime and Pro proof must both be true")
    require(timestamp(proof.get("capturePreparedAt")) >= launched_at - timedelta(seconds=1),
            "Native proof predates this fixture launch")


def validate_timeline(proof, family, fixture, apple_locale, launched_at):
    require(isinstance(proof, dict), f"Missing {family} timeline object")
    expected = {
        "evidenceKind": "timeline-data", "family": family, "scene": fixture["scene"],
        "locale": fixture["locale"], "currentLocaleIdentifier": apple_locale,
    }
    for key, value in expected.items():
        require(proof.get(key) == value, f"{family}: wrong {key}")
    preferred = proof.get("preferredLocalizations")
    require(isinstance(preferred, list) and preferred and preferred[0] == fixture["locale"],
            f"{family}: wrong preferred localization")
    require(timestamp(proof.get("generatedAt")) >= launched_at - timedelta(seconds=1),
            f"{family}: stale timeline")
    events = fixture["events"]
    selected = events[:HOME_FAMILIES[family]] if family in HOME_FAMILIES else [events[LOCK_FAMILIES[family]]]
    require(proof.get("events") == [{"id": event["id"], "name": event["name"]} for event in selected],
            f"{family}: timeline event IDs/names do not match the actual fixture selection")
    config = proof.get("effectiveConfiguration")
    require(isinstance(config, dict), f"{family}: missing effective configuration")
    if family in HOME_FAMILIES:
        require(config.get("theme") == ("blue" if family == "systemMedium" else "custom"),
                f"{family}: wrong theme")
        require(config.get("showDates") is False and config.get("showList") is False,
                f"{family}: dates/list must be disabled")
        require(config.get("directionIndicators") is fixture["showDirection"],
                f"{family}: wrong direction indicators")
    else:
        require(config.get("showBackground") is True, f"{family}: background must be enabled")


def wait_for_proof(description, timeout, read_and_validate):
    deadline = time.monotonic() + timeout
    last_error = "not yet available"
    while time.monotonic() < deadline:
        try:
            return read_and_validate()
        except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
            # Atomic native writes may still be absent or from an older generation.
            last_error = str(error)
        time.sleep(0.25)
    raise RuntimeError(f"No valid {description} within {timeout}s: {last_error}; refusing to capture")


def png_dimensions(path):
    with path.open("rb") as source:
        header = source.read(24)
    require(len(header) == 24 and header[:8] == PNG_SIGNATURE
            and header[8:16] == b"\x00\x00\x00\x0dIHDR"
            and struct.unpack(">II", header[16:24]) == (1206, 2622),
            f"Expected a native 1206x2622 PNG: {path}")


def surface_for(scene):
    return ("home-screen", "springboard-launch") if scene in HOME_SCENES else ("lock-screen", "notification-center")


def resume_valid(args, helpers, index, job, device):
    if not args.resume:
        return False
    try:
        previous = read_json(job["evidence"])
        surface, method = surface_for(job["scene"])
        expected = {
            "locale": job["locale"], "scene": job["scene"], "surface": surface,
            "captureMethod": method, "evidenceKind": "timeline-data", "renderingVerified": False,
            "sourceCommit": args.source_commit, "referenceDate": index["referenceDate"],
            "simulator": args.simulator, "width": 1206, "height": 2622,
            "fixtureSHA256": job["fixtureSHA256"], "imageSHA256": helpers.digest(job["output"]),
        }
        require(all(previous.get(key) == value for key, value in expected.items()), "Outdated capture evidence")
        if job["scene"] in LOCK_SCENES:
            require(previous.get("statusBarOverridePhase") == "after-widget-render",
                    "Lock capture predates the corrected clock-override sequence")
            require(previous.get("lockScreenRefresh") == "wallpaper-gallery-reselect",
                    "Lock capture predates the localized wallpaper refresh")
        state = previous["deviceState"]
        require(all(state.get(key) == device.get(key) for key in ("name", "udid", "deviceTypeIdentifier", "runtime")),
                "Outdated simulator evidence")
        require(state.get("state") == "Booted" and state.get("AppleLanguages") == [job["locale"]]
                and state.get("AppleLocale") == job["appleLocale"], "Outdated locale evidence")
        launched_at = timestamp(previous["fixtureLaunchStartedAt"])
        require(launched_at <= timestamp(previous["capturedAt"]), "Invalid capture timestamps")
        png_dimensions(job["output"])
        strict_app_proof(helpers, previous["nativeProof"], job["fixture"], job["appleLocale"], launched_at)
        timelines = previous["timelineProofs"]
        required = HOME_FAMILIES if job["scene"] in HOME_SCENES else LOCK_FAMILIES
        require(isinstance(timelines, dict) and set(timelines) == set(required), "Incomplete timeline evidence")
        for family in required:
            validate_timeline(timelines[family], family, job["fixture"], job["appleLocale"], launched_at)
        return True
    except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError):
        # Old/corrupt proof is a cache miss, not a reason to abort the batch.
        return False


def containers(helpers, simulator, data):
    app = Path(helpers.simctl("get_app_container", simulator, helpers.BUNDLE_ID, "data")).resolve(strict=True)
    group = Path(helpers.simctl("get_app_container", simulator, helpers.BUNDLE_ID, APP_GROUP)).resolve(strict=True)
    require(inside(app, data / "Containers/Data/Application"), "Unexpected app data container")
    require(inside(group, data / "Containers/Shared/AppGroup"), "Unexpected shared app-group container")
    return app, group


def apply_status_bar(helpers, simulator, reference_date):
    # Interpret 09:41 in the host's local timezone on this date, then use UTC Z.
    local = datetime.combine(date.fromisoformat(reference_date), datetime.min.time()).replace(hour=9, minute=41)
    clock = local.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    helpers.simctl("ui", simulator, "appearance", "light")
    helpers.simctl("status_bar", simulator, "override", "--time", clock,
                   "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                   "--cellularMode", "active", "--cellularBars", "4",
                   "--batteryState", "discharging", "--batteryLevel", "100", "--operatorName", "")
    return clock


def show_surface(args, helpers, scene):
    # Main verified that AXe's Home button can succeed without leaving the app.
    # Only the prepared widget page is visible; do not perform a horizontal drag.
    helpers.simctl("launch", args.simulator, "com.apple.springboard")
    # SpringBoard and remote touch automation can become ready at different times
    # after a locale reboot. Retry only the known session-creation failure.
    time.sleep(4.0 if scene in LOCK_SCENES else 0.8)
    if scene in LOCK_SCENES:
        env = {key: value for key, value in os.environ.items() if not key.startswith("SIMCTL_CHILD_")}
        for attempt in range(3):
            if attempt:
                print(f"RETRY remote touch session ({attempt + 1}/3)", flush=True)
                helpers.simctl("launch", args.simulator, "com.apple.springboard")
                time.sleep(4.0 * attempt)
            result = subprocess.run(
                [str(args.axe), "drag", "--start-x", "150", "--start-y", "2",
                 "--end-x", "150", "--end-y", "770", "--duration", "0.5",
                 "--steps", "40", "--post-delay", "1", "--udid", args.simulator],
                env=env, capture_output=True, text=True, timeout=40, check=False,
            )
            if result.returncode == 0:
                return
            error = result.stderr.strip() or result.stdout.strip()
            session_timeout = ("Timed out creating" in error and "remote automation session" in error)
            if not session_timeout or attempt == 2:
                raise RuntimeError(f"AXe CoverSheet drag failed: {error}")


def refresh_lock_wallpaper(args):
    # After a language reboot, iOS can show an empty cached CoverSheet even when
    # providers have valid localized timelines. Opening the wallpaper gallery and
    # selecting the existing card refreshes its real widget hosts; no layout edit.
    env = {key: value for key, value in os.environ.items() if not key.startswith("SIMCTL_CHILD_")}
    commands = [
        ["touch", "-x", "201", "-y", "430", "--down", "--up", "--delay", "1.5"],
        ["tap", "-x", "201", "-y", "430", "--tap-style", "physical", "--post-delay", "2"],
    ]
    for command in commands:
        for attempt in range(3):
            result = subprocess.run([str(args.axe), *command, "--udid", args.simulator],
                                    env=env, capture_output=True, text=True, timeout=40, check=False)
            if result.returncode == 0:
                break
            error = result.stderr.strip() or result.stdout.strip()
            session_timeout = "Timed out creating" in error and "remote automation session" in error
            if not session_timeout or attempt == 2:
                raise RuntimeError(f"AXe wallpaper refresh failed: {error}")
            time.sleep(4 * (attempt + 1))
        time.sleep(1)


@contextmanager
def native_ui_lock():
    # Coordinate this tool's concurrent simulator jobs so AXe never initializes
    # two remote touch sessions at once. File locks release on process exit.
    path = Path(tempfile.gettempdir()) / "countdowns-v12-native-ui.lock"
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        require(os.fstat(fd).st_uid == os.getuid(), "Unexpected native UI lock owner")
        deadline = time.monotonic() + 180
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                require(time.monotonic() < deadline, "Timed out waiting for another capture's native UI gestures")
                time.sleep(0.25)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def capture(args, helpers, index, job, data, clock):
    require(index["referenceDate"] == date.today().isoformat(), "Reference date changed; regenerate fixtures")
    require(helpers.digest(job["fixturePath"]) == job["fixtureSHA256"], "Fixture changed during this batch")
    if job["scene"] in LOCK_SCENES:
        # A clock override active while CoverSheet initializes after a locale
        # reboot can produce January 1 with empty widgets despite valid timelines.
        # Render at the real clock first, then apply the presentation-only time.
        helpers.simctl("status_bar", args.simulator, "clear")
        helpers.simctl("ui", args.simulator, "appearance", "light")
    elif clock is None:
        clock = apply_status_bar(helpers, args.simulator, index["referenceDate"])
    app, group = containers(helpers, args.simulator, data)
    proof_path = child_path(app, "Documents/website-screenshot-proof.json")
    timeline_paths = {family: child_path(group, f"website-widget-timeline-{family}.json") for family in FAMILIES}
    # ONLY these six capture-owned records are removed. No app/widget/user data deletion.
    for path in (proof_path, *timeline_paths.values()):
        require(not path.is_symlink(), f"Refusing symlink proof path: {path}")
        path.unlink(missing_ok=True)
    fixture = job["fixture"]
    env = {key: value for key, value in os.environ.items() if not key.startswith("SIMCTL_CHILD_")}
    env.update({
        "SIMCTL_CHILD_screenshots": "true", "SIMCTL_CHILD_isProUser": "true",
        "SIMCTL_CHILD_websiteScreenshotFixture": json.dumps(fixture, ensure_ascii=False),
    })
    launch_args = ["-AppleLanguages", f"({job['locale']})", "-AppleLocale", job["appleLocale"],
                   "-isProUserKey", "YES", "-isLifetimeUserKey", "YES"]
    launched_at = utc_now()
    # Cold launches after a locale reboot can exceed simctl's usual 40-second
    # client deadline even though the app subsequently starts successfully.
    helpers.simctl("launch", "--terminate-running-process", args.simulator, helpers.BUNDLE_ID,
                   *launch_args, env=env, timeout=90)

    def read_app():
        proof = read_json(proof_path)
        strict_app_proof(helpers, proof, fixture, job["appleLocale"], launched_at)
        return proof

    native_proof = wait_for_proof("native lifetime-Pro proof", 35, read_app)
    if job["scene"] in LOCK_SCENES:
        with native_ui_lock():
            show_surface(args, helpers, job["scene"])
            refresh_lock_wallpaper(args)
    else:
        show_surface(args, helpers, job["scene"])
    required = HOME_FAMILIES if job["scene"] in HOME_SCENES else LOCK_FAMILIES

    def read_timelines():
        proofs = {}
        for family in required:
            proof = read_json(timeline_paths[family])
            validate_timeline(proof, family, fixture, job["appleLocale"], launched_at)
            proofs[family] = proof
        return proofs

    wait_for_proof("required widget timeline proof", 45, read_timelines)
    time.sleep(args.settle)
    if job["scene"] in LOCK_SCENES:
        clock = apply_status_bar(helpers, args.simulator, index["referenceDate"])
        time.sleep(1)
    # Re-read after settling so another fixture cannot silently replace valid evidence.
    timeline_proofs = read_timelines()
    native_proof = read_app()
    device = device_record(helpers, args.simulator)
    require(device["state"] == "Booted", "Capture simulator is no longer booted")
    preferences = plistlib.loads(child_path(data, "Library/Preferences/.GlobalPreferences.plist").read_bytes())
    require(preferences.get("AppleLanguages") == [job["locale"]]
            and preferences.get("AppleLocale") == job["appleLocale"], "Simulator locale settings changed")
    job["output"].parent.mkdir(parents=True, exist_ok=True)
    require(not job["output"].is_symlink(), "Refusing symlink PNG destination")
    pending = job["output"].with_name(f".{job['scene']}.{uuid.uuid4().hex}.pending.png")
    try:
        helpers.simctl("io", args.simulator, "screenshot", "--type=png", str(pending))
        png_dimensions(pending)
        require(helpers.digest(job["fixturePath"]) == job["fixtureSHA256"], "Fixture changed during capture")
        surface, method = surface_for(job["scene"])
        record = {
            "locale": job["locale"], "scene": job["scene"], "surface": surface,
            "captureMethod": method, "evidenceKind": "timeline-data", "renderingVerified": False,
            "device": "iPhone 17 Pro", "os": "iOS 27", "simulator": args.simulator,
            "sourceCommit": args.source_commit, "referenceDate": index["referenceDate"],
            "fixtureLaunchStartedAt": launched_at.isoformat(), "capturedAt": utc_now().isoformat(),
            "width": 1206, "height": 2622, "imageSHA256": helpers.digest(pending),
            "fixtureSHA256": job["fixtureSHA256"], "launchArguments": launch_args,
            "nativeProof": native_proof, "timelineProofs": timeline_proofs,
            "statusBarTimeUTC": clock, "settleSeconds": args.settle,
            "deviceState": {key: device[key] for key in ("name", "udid", "state", "deviceTypeIdentifier", "runtime")},
            "appearance": "light", "axe": str(args.axe),
        }
        record["deviceState"].update(AppleLanguages=preferences["AppleLanguages"], AppleLocale=preferences["AppleLocale"])
        if job["scene"] in LOCK_SCENES:
            record["statusBarOverridePhase"] = "after-widget-render"
            record["lockScreenRefresh"] = "wallpaper-gallery-reselect"
        # Final files are individually atomic. Resume rejects an interrupted hash mismatch.
        pending.replace(job["output"])
        write_json(job["evidence"], record)
    finally:
        pending.unlink(missing_ok=True)
    print(f"CAPTURED {job['locale']}/{job['scene']} · {method} · timeline-data (pixels unverified)", flush=True)


def selection(value, allowed, description):
    values = value.split(",") if value is not None else list(allowed)
    require(values and len(values) == len(set(values)) and not set(values) - set(allowed),
            f"Invalid or duplicate {description}")
    return values


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Already booted Countdowns V12 iPhone 17 Pro UUID")
    for option in ("fixtures", "output", "evidence", "axe"):
        parser.add_argument(f"--{option}", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--allow-simulator-settings", action="store_true", required=True,
                        help="Explicitly allow temporary simulator language/locale changes and shutdown/boot")
    parser.add_argument("--locales", help="Comma-separated exact locale codes; default all")
    parser.add_argument("--scenes", help="Comma-separated subset of the seven widget scenes; default all")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--settle", type=float, default=4.0)
    args = parser.parse_args()
    require(args.allow_simulator_settings, "Explicit simulator-settings consent is required")
    args.simulator = str(uuid.UUID(args.simulator)).upper()
    require(args.axe.is_absolute(), "--axe must be an absolute binary path")
    args.axe = args.axe.resolve(strict=True)
    require(args.axe.is_file() and os.access(args.axe, os.X_OK), "AXe must be an executable file")
    require(math.isfinite(args.settle) and 0.5 <= args.settle <= 30, "--settle must be 0.5–30 seconds")
    require(args.source_commit.strip(), "--source-commit cannot be empty")
    for name in ("fixtures", "output", "evidence"):
        setattr(args, name, getattr(args, name).expanduser().resolve())
    require(not inside(args.output, args.evidence) and not inside(args.evidence, args.output),
            "PNG output and private evidence must be separate, non-overlapping directories")
    for destination in (args.output, args.evidence):
        require(not inside(destination, args.fixtures) and not inside(args.fixtures, destination),
                "Capture destinations must not overlap fixture inputs")
    return args


def prepare_jobs(args, helpers, index):
    require(index["referenceDate"] == date.today().isoformat(), "Regenerate fixtures for today's local date")
    locales = selection(args.locales, index["locales"], "locales")
    scenes = selection(args.scenes, SCENES, "widget scenes")
    jobs = []
    for code in locales:
        entry = index["locales"][code]
        folder = entry["folder"]
        require(folder == code.lower() and Path(folder).name == folder, "Unexpected locale folder")
        apple_locale = index["appleLocales"][code]
        require(isinstance(apple_locale, str) and apple_locale, "Missing Apple locale identifier")
        for scene in scenes:
            path = child_path(args.fixtures, entry["fixtures"][scene])
            fixture = read_json(path)
            require(fixture.get("scene") == scene and fixture.get("locale") == code, "Fixture identity mismatch")
            require(fixture.get("screen") == "list" and isinstance(fixture.get("showDirection"), bool),
                    "Expected a widget list fixture with explicit direction setting")
            events = fixture.get("events")
            require(isinstance(events, list) and len(events) >= 3, "Widget fixtures need at least three events")
            require(all(isinstance(event, dict) and isinstance(event.get("id"), str) and event["id"]
                        and isinstance(event.get("name"), str) and event["name"].strip() for event in events),
                    "Missing fixture event IDs/names")
            require(len({event["id"] for event in events}) == len(events), "Duplicate fixture event IDs")
            jobs.append({
                "locale": code, "scene": scene, "appleLocale": apple_locale, "fixture": fixture,
                "fixturePath": path, "fixtureSHA256": helpers.digest(path),
                "output": child_path(args.output, f"{folder}/{scene}.png"),
                "evidence": child_path(args.evidence, f"{folder}/{scene}.json"),
            })
    return jobs


def main():
    args = parse_args()
    helpers = load_app_helpers()
    index = read_json(args.fixtures / "batch-index.json")
    jobs = prepare_jobs(args, helpers, index)
    device = device_record(helpers, args.simulator)
    require(device["state"] == "Booted", "Main must boot the prepared capture simulator first")
    data = simulator_home(helpers, args.simulator, device)
    for path in (args.fixtures, args.output, args.evidence):
        require(not inside(path, data) and not inside(data, path), "Batch paths must not overlap simulator data")
    containers(helpers, args.simulator, data)  # Fail before any settings changes if the app/group is absent.
    remaining = []
    for job in jobs:
        if resume_valid(args, helpers, index, job, device):
            print(f"VERIFIED {job['locale']}/{job['scene']}", flush=True)
        else:
            remaining.append(job)
    if not remaining:
        print("All requested captures verified; no simulator settings or UI changed.")
        return
    preferences = SimulatorPreferences(helpers, args.simulator, data, args.evidence)

    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"Signal {signum}; restoring simulator preferences")

    old_term = signal.signal(signal.SIGTERM, interrupted)
    try:
        preferences.begin()
        current_locale = None
        for job in remaining:
            if current_locale != job["locale"]:
                preferences.set_locale(job["locale"], job["appleLocale"])
                clock = (apply_status_bar(helpers, args.simulator, index["referenceDate"])
                         if job["scene"] in HOME_SCENES else None)
                current_locale = job["locale"]
            capture(args, helpers, index, job, data, clock)
    finally:
        try:
            preferences.restore()
        finally:
            signal.signal(signal.SIGTERM, old_term)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt as error:
        print(f"Capture interrupted: {error}", file=sys.stderr)
        sys.exit(130)
    except Exception as error:
        print(f"Widget capture failed: {error}", file=sys.stderr)
        sys.exit(1)
