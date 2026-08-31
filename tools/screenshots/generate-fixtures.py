#!/usr/bin/env python3
"""Generate native websiteScreenshotFixture JSON; never build or capture anything.

Usage: python3 tools/screenshots/generate-fixtures.py --date 2026-08-30 --output /tmp/fixtures
Inputs are resolved relative to this script, independently of the working directory.
Output: <code.lower()>/<scene>.json plus batch-index.json (written last).
Calendar-year subtraction clamps Feb 29 to Feb 28 when necessary. Annual holidays
include the reference day itself; Christmas Eve belongs to the selected Christmas.
"""

import argparse
import calendar
import json
import re
from datetime import date, timedelta
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_DIR = SCRIPT_DIR.parents[1]
APPLE_LOCALES = {
    "en": "en_US", "ar": "ar_SA@calendar=gregorian", "ca": "ca_ES", "da": "da_DK",
    "de": "de_DE", "es": "es_ES", "fi": "fi_FI", "fr": "fr_FR",
    "it": "it_IT", "ja": "ja_JP", "ko": "ko_KR", "nb": "nb_NO",
    "nl": "nl_NL", "pl": "pl_PL", "pt": "pt_PT", "pt-BR": "pt_BR",
    "ru": "ru_RU", "sk": "sk_SK", "sv": "sv_SE", "tr": "tr_TR",
    "zh-Hans": "zh_CN", "zh-Hant": "zh_TW",
}
SCENES = (
    "normal-display", "compact-display", "colors", "editing", "settings",
    "home-screen-widgets", "lock-screen-widgets", "wedding-countdown-app",
    "vacation-countdown-app", "anniversary-countdown-app",
    "theme-park-trip-countdown-app", "birthday-countdown-app",
    "holiday-countdown-app", "retirement-countdown-app",
    "pregnancy-countdown-app", "event-countdown-app", "christmas-countdown-app",
)
LABELS = frozenset((
    "birthday", "vacation", "ourWedding", "holidays", "milestones",
    "halloween", "christmas", "togetherSince", "anniversary", "honeymoon",
    "weddingDay", "packing", "flight", "themePark", "parkDay", "tickets",
    "birthdayParty", "celebrate", "newYear", "retirement", "lastWorkday",
    "newChapter", "babyArrival", "nextScan", "babyShower", "summerParty", "concert",
))
DAY_UNITS = ("3",)
DETAILED_UNITS = ("3", "4", "5", "6")
WEEK_UNITS = ("2", "3")
HOLIDAYS_ID = "website-list-holidays"
MILESTONES_ID = "website-list-milestones"


def require_keys(actual, expected, description):
    actual, expected = set(actual), set(expected)
    if actual != expected:
        raise ValueError(
            f"{description}: missing {sorted(expected - actual)}, "
            f"unexpected {sorted(actual - expected)}"
        )


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def load_labels():
    source = SCRIPT_DIR / "fixtures" / "localizations.json"
    labels = json.loads(source.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    if not isinstance(labels, dict):
        raise ValueError("localizations.json must contain an object")
    require_keys(labels, APPLE_LOCALES, "Localization locales")
    for code, translated in labels.items():
        if not isinstance(translated, dict):
            raise ValueError(f"{code}: labels must be an object")
        require_keys(translated, LABELS, f"{code} labels")
        for key, value in translated.items():
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"{code}/{key}: expected a nonempty translated label")
    return labels


def validate_manifest():
    """Read only the manifest's simple locales/path mapping, not arbitrary YAML.

    Its quoted paths are JSON strings. Reject unsupported syntax instead of
    silently skipping entries or requiring an external YAML dependency.
    """
    source = REPO_DIR / "_data" / "screenshots.yml"
    entries = {}
    in_locales = False
    locale = None
    for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line == "locales:":
            if in_locales:
                raise ValueError("Duplicate manifest locales section")
            in_locales = True
            continue
        if not in_locales:
            continue
        locale_match = re.fullmatch(r"  ([A-Za-z][A-Za-z0-9-]*):\s*", line)
        if locale_match:
            locale = locale_match[1]
            if locale in entries:
                raise ValueError(f"Duplicate manifest locale: {locale}")
            entries[locale] = {}
            continue
        scene_match = re.fullmatch(r'    ([a-z0-9-]+):\s*("[^"\n]+")\s*', line)
        if locale is None or scene_match is None:
            raise ValueError(f"{source.name}:{number}: unsupported locales mapping syntax")
        scene, encoded_path = scene_match.groups()
        if scene in entries[locale]:
            raise ValueError(f"Duplicate manifest scene: {locale}/{scene}")
        entries[locale][scene] = json.loads(encoded_path)

    require_keys(entries, APPLE_LOCALES, "Manifest locales")
    if len(SCENES) != 17 or len(set(SCENES)) != 17:
        raise ValueError("Expected exactly 17 unique generator scenes")
    for code, scenes in entries.items():
        require_keys(scenes, SCENES, f"{code} manifest scenes")
        for scene, path in scenes.items():
            expected = f"/assets/screenshots/{code.lower()}/{scene}.png"
            if path != expected:
                raise ValueError(f"{code}/{scene}: expected {expected}, got {path}")


def parse_date(value):
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise argparse.ArgumentTypeError("date must use YYYY-MM-DD")
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def years_before(value, years):
    year = value.year - years
    day = min(value.day, calendar.monthrange(year, value.month)[1])
    return date(year, value.month, day)


def next_annual(reference, month, day):
    candidate = date(reference.year, month, day)
    return candidate if candidate >= reference else date(reference.year + 1, month, day)


def make_scenes(code, labels, reference):
    def event(key, emoji, target, color, *, units=DAY_UNITS, list_id=None,
              count_up=False, yearly=False, occurrence=False):
        return {
            # IDs are assigned by position in each final scene, never by title.
            "name": labels[key], "emoji": emoji, "date": target.isoformat(),
            "units": list(units), "listId": list_id, "colorIndex": color,
            "allowsCountUp": count_up, "repeatYearly": yearly,
            "showOccurrenceNumber": occurrence,
        }

    def after(days):
        return reference + timedelta(days=days)

    birthday_date = years_before(after(30), 38)
    together_date = years_before(reference, 3)
    halloween_date = next_annual(reference, 10, 31)
    christmas_date = next_annual(reference, 12, 25)
    new_year_date = next_annual(reference, 1, 1)
    birthday = event("birthday", "🎂", birthday_date, 1, yearly=True, occurrence=True)
    vacation = event("vacation", "✈️", after(60), 2)
    wedding = event("ourWedding", "💍", after(110), 7)
    together = event("togetherSince", "❤️", together_date, 9, count_up=True)
    halloween = event("halloween", "🎃", halloween_date, 6)
    christmas = event("christmas", "🎄", christmas_date, 3)
    new_year = event("newYear", "🎆", new_year_date, 9)
    baseline = [birthday, vacation, wedding,
                dict(halloween, listId=HOLIDAYS_ID),
                dict(christmas, listId=HOLIDAYS_ID),
                dict(together, listId=MILESTONES_ID)]
    lists = [{"id": HOLIDAYS_ID, "name": labels["holidays"]},
             {"id": MILESTONES_ID, "name": labels["milestones"]}]
    scenes = {}

    def add(scene, events, *, compact=True, with_lists=False, screen="list", direction=False):
        if scene in scenes:
            raise ValueError(f"Duplicate generated scene: {scene}")
        scenes[scene] = {
            "scene": scene, "locale": code, "screen": screen, "compact": compact,
            "listsEnabled": with_lists, "showDates": False, "showDirection": direction,
            "lists": lists if with_lists else [],
            "events": [dict(item, id=f"website-event-{index}",
                            listId=item["listId"] if with_lists else None)
                       for index, item in enumerate(events, 1)],
        }

    add("normal-display", [dict(item, colorIndex=None, units=list(DETAILED_UNITS))
                           for item in baseline[:3]], compact=False)
    add("compact-display", [dict(item, colorIndex=None) for item in baseline], with_lists=True)
    for scene in ("colors", "settings", "home-screen-widgets", "lock-screen-widgets"):
        add(scene, baseline, with_lists=True, screen="settings" if scene == "settings" else "list")
    add("editing", [wedding], screen="editor")
    add("wedding-countdown-app", [wedding, event("honeymoon", "✈️", after(115), 2), together])
    add("vacation-countdown-app", [vacation, event("packing", "🧳", after(45), 6),
                                   event("flight", "🛫", after(60), 1)])
    add("anniversary-countdown-app", [
        together, event("anniversary", "💕", years_before(after(45), 2), 7, yearly=True),
        event("celebrate", "🥂", after(45), 6),
    ], direction=True)
    add("theme-park-trip-countdown-app", [
        event("themePark", "🎢", after(45), 9), event("tickets", "🎟️", after(30), 1),
        event("parkDay", "🎡", after(46), 6),
    ])
    add("birthday-countdown-app", [birthday, event("birthdayParty", "🎉", after(31), 9),
                                   event("celebrate", "🥳", after(31), 6)])
    add("holiday-countdown-app", [halloween, christmas, new_year])
    add("retirement-countdown-app", [
        event("retirement", "🌅", after(180), 2, units=DETAILED_UNITS),
        event("lastWorkday", "💼", after(179), 1, units=DETAILED_UNITS),
        event("newChapter", "⛵", after(181), 9, units=DETAILED_UNITS),
    ], compact=False)
    add("pregnancy-countdown-app", [
        event("babyArrival", "👶", after(129), 2, units=WEEK_UNITS),
        event("nextScan", "🩺", after(16), 1, units=WEEK_UNITS),
        event("babyShower", "🧸", after(73), 9, units=WEEK_UNITS),
    ])
    add("event-countdown-app", [event("concert", "🎵", after(90), 9)], screen="editor")
    add("christmas-countdown-app", [christmas, new_year,
                                    event("holidays", "🎁", christmas_date.replace(day=24), 7)])
    require_keys(scenes, SCENES, f"{code} generated scenes")
    return scenes


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", required=True, type=parse_date, metavar="YYYY-MM-DD",
                        help="required reference date; never defaults to today's date")
    parser.add_argument("--output", required=True, type=Path, help="fixture output directory")
    args = parser.parse_args()
    try:
        labels = load_labels()
        validate_manifest()
        # Validate and resolve the complete batch before writing any output.
        batch = {code: make_scenes(code, labels[code], args.date) for code in APPLE_LOCALES}
        output = args.output.expanduser().resolve()
        index = {
            "referenceDate": args.date.isoformat(), "fixtureCount": len(batch) * len(SCENES),
            "scenes": list(SCENES), "appleLocales": APPLE_LOCALES, "locales": {},
        }
        # An interrupted rerun must not leave an old index advertising completion.
        index_path = output / "batch-index.json"
        if index_path.exists():
            index_path.unlink()
        for code, scenes in batch.items():
            folder = code.lower()
            paths = {}
            for scene in SCENES:
                relative = f"{folder}/{scene}.json"
                write_json(output / relative, scenes[scene])
                paths[scene] = relative
            index["locales"][code] = {"folder": folder, "fixtures": paths}
        write_json(index_path, index)
    except (OSError, ValueError, OverflowError) as error:
        parser.exit(1, f"Fixture generation failed: {error}\n")
    print(f"Generated {index['fixtureCount']} fixtures ({len(batch)} locales × {len(SCENES)} scenes) "
          f"for {args.date.isoformat()} in {output}")
    print(f"Batch index: {index_path}")


if __name__ == "__main__":
    main()
