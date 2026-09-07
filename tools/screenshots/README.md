# Version 12 website screenshots

Reproduce real native captures with Python 3's standard library and Xcode's
Simulator tools. This is not a publishing pipeline. **All 391 revised captures are
complete, visually reviewed, and installed, with zero pending:** 230 app + 115 Home
widget + 46 Lock widget PNGs, covering 17 scenes in each of 23 languages with
lifetime Pro access. The completed manifest records 339 `pass` and 52
`pass_with_notes` reviews, including the Hindi addition, Arabic fix, and French
replacement below.

[`capture-manifest.json`](capture-manifest.json) records every raw-capture image
hash, fixture and capture-evidence hashes, lifetime Pro state, visual review, and
native UI notes. Hindi records also include the losslessly recompressed website
file's published hash.
[`build-provenance.json`](build-provenance.json) records installed app/widget binary
hashes and capture-source patch information. Its `baselineBinariesBySurface`
preserves the original builds; `revisions` separately records the Arabic and Hindi
builds, source-archive hashes, signing verification, and installed binary hashes.
Baseline app-only captures predate widget timeline instrumentation; their main Debug
dylib matches the baseline widget-capture build. The revised Arabic and new Hindi
images use their own binary proof. No deployment or publishing is part of this workflow.

## Per-capture source provenance

Five Arabic app scenes were recaptured from
`e1beaa05d97abcfa1097156ef53ecd1a2eb03351`, including the user's Arabic compact-mode
trailing-text alignment fix `8732552f07ba0de98084d168f20e8295cd961132`:
`compact-display`, `colors`,
`birthday-countdown-app`, `holiday-countdown-app`, and `pregnancy-countdown-app`.
Seventeen Hindi app and widget scenes were captured from
`a864f816db62c03aaf5d2ae622dc9be783ce31b3`, which includes native Hindi support and
the localized **काउंटडाउन** display name. The other 369 captures retain baseline
`c882f8c9f6588b836113d7d205e1ba193995644c`. This includes the French
`christmas-countdown-app` replacement, reviewed and promoted without the native
black island seen in its earlier capture.

The manifest's per-image `sourceCommit` and `captureRevisions` identify the five
Arabic replacements and 17 Hindi additions; the corresponding
`build-provenance.json` revisions have exactly those scopes. The manifest keeps
raw capture hashes, and the 17 Hindi records also keep the current website-file
hashes after lossless recompression. Its `runtimeFilesSHA256` values preserve the
tools used at capture time. The later
folder cleanup changed only the fixture generator's expected website paths;
the generated fixtures and screenshot bytes are unchanged. Keep the original
runtime hashes as capture provenance. Do not describe all captures as coming
from one source commit.

The coordinating review verified that the newer widget-icon changes do not affect
the captured styles: medium/large Home widgets use `ListCountdownView` with
20-point list artwork; basic Lock widgets use `LockScreenConfigurationProvider`
and circular `showProgress: false`, retaining 20-point artwork. The progress
provider is not used by these captures. The original 154 widget images retain valid
baseline provenance, and the seven Hindi widget images carry separate build and
timeline proof; the Arabic app fix did not require a widget reshoot.

## Isolated native build and fresh simulators

The original batch used native `develop` commit
`c882f8c9f6588b836113d7d205e1ba193995644c` with
[`native-capture.patch`](native-capture.patch). Apply the capture-only patch to a
separate temporary source tree; leave the original app repository untouched. The
existing capture tree is `/private/tmp/countdowns-v12-samples-app-01a05493`.
For baseline reproduction, run from the website repository root. For the five
revised Arabic scenes, set `SOURCE_COMMIT` to
`e1beaa05d97abcfa1097156ef53ecd1a2eb03351` before the archive command, apply the same
verified capture patch to a fresh temporary tree, and build separately. Limit that
app capture to `--locales ar` and the five scenes listed above; retain separate
evidence and the revision's binary provenance. For Hindi, use
`a864f816db62c03aaf5d2ae622dc9be783ce31b3`, capture all 17 scenes with `--locales hi`,
and record the app and both widget surfaces under one signed build revision.

```sh
WEBSITE_ROOT="$PWD"
NATIVE_REPO=/absolute/path/to/original/native/repository
SOURCE_COMMIT=c882f8c9f6588b836113d7d205e1ba193995644c
CAPTURE_SOURCE="$(mktemp -d /private/tmp/countdowns-v12-native.XXXXXX)"
git -C "$NATIVE_REPO" archive "$SOURCE_COMMIT" | tar -x -C "$CAPTURE_SOURCE"
git -C "$CAPTURE_SOURCE" apply --check "$WEBSITE_ROOT/tools/screenshots/native-capture.patch"
git -C "$CAPTURE_SOURCE" apply "$WEBSITE_ROOT/tools/screenshots/native-capture.patch"
```

Create **fresh iPhone 17 Pro / iOS 27.0 simulators**, with names beginning
`Countdowns V12`, using Xcode's installed runtime. **Do not clone simulators**:
clones have exhibited stale app and shared-group container links. Keep the path
and device guards enabled; recreate an invalid simulator instead of bypassing
checks. Use explicit UUIDs and separate simulators for concurrent capture jobs.

Boot each fresh simulator, then build and install the **signed Debug** app
(`Countdown` scheme, app version **12.0.0**, bundle `com.shayesapps.countdownApp`).
Select the Xcode installation containing iOS 27 before running these commands:

```sh
CAPTURE_SIM=FRESH-SIMULATOR-UUID
CAPTURE_BUILD="$(mktemp -d /private/tmp/countdowns-v12-build.XXXXXX)"
xcodebuild -project "$CAPTURE_SOURCE/Countdown.xcodeproj" -scheme Countdown \
  -configuration Debug -destination "id=$CAPTURE_SIM" \
  -derivedDataPath "$CAPTURE_BUILD" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcrun simctl install "$CAPTURE_SIM" "$CAPTURE_BUILD/Build/Products/Debug-iphonesimulator/Countdown.app"
```

Do not disable signing: the app and widget extension need working shared-container
access. The patch enables fixture/proof instrumentation for Debug Simulator use;
it does not make a production purchase or change production entitlements.

## Fixtures and coverage

`_data/screenshots.yml` defines **23 locales × 17 scenes = 391 PNG paths**, native
size **1206 × 2622**, and 12 guide mappings. Exact CLI/manifest locale codes:

```text
en ar ca da de es fi fr hi it ja ko nb nl pl pt pt-BR ru sk sv tr zh-Hans zh-Hant
```

Paths are `/assets/screenshots/<folder>/<scene>.png`. Use the locale folder
from `_data/locales.yml`, or `en` for English: folders are lowercase, including
`pt-br`, `zh-hans`, and `zh-hant`. Never substitute English images for another locale.
Keep the app version in the manifests rather than in the image directory name.
The seven superseded root-level PNGs and unused guide screenshot fields have been
removed; Git preserves the old images. The separate press-kit ZIP is unchanged.

| Family | `--scenes` value | Images across 23 locales |
| --- | --- | --- |
| App | `normal-display,compact-display,colors,editing,settings,birthday-countdown-app,holiday-countdown-app,retirement-countdown-app,pregnancy-countdown-app,event-countdown-app` | 230 |
| Home widgets | `home-screen-widgets,wedding-countdown-app,vacation-countdown-app,anniversary-countdown-app,theme-park-trip-countdown-app` | 115 |
| Lock widgets | `lock-screen-widgets,christmas-countdown-app` | 46 |

Generate fixtures for the capture machine's **current local date**. Generation is
deterministic for the supplied date and `fixtures/localizations.json`; the helpers
reject fixtures from another day. Keep fixtures, staging PNGs, and evidence outside
the website, with separate evidence directories for concurrent runs.

```sh
FIXTURES=/private/tmp/countdowns-v12-fixtures
python3 tools/screenshots/generate-fixtures.py --date "$(date +%F)" --output "$FIXTURES"
```

The generator writes 391 fixture JSON files and `batch-index.json`. Use the index's
Apple locale identifiers, including **`ar_SA@calendar=gregorian` for Arabic**;
plain `ar_SA` can change calendar behavior. Preserve exact locale codes in arguments.

## Native widget baseline

Prepare each widget simulator manually through the native UI before capture:

- Set a fixed blue wallpaper on Home and Lock screens, with light appearance.
- Home: keep **one visible page**, containing a medium and a large Countdowns
  widget filling six rows. Hide other pages without deleting their apps. Configure
  medium as blue and large as custom, with dates and lists hidden.
- Lock: save an inline, rectangular, and circular Countdowns widget on the blue
  wallpaper, with widget backgrounds enabled. Exit the wallpaper editor and gallery.
- Acknowledge initial system alerts. Verify the installed app and widget containers
  belong to this simulator, and visually check both saved surfaces.

The widget helper activates Home via `simctl launch … com.apple.springboard`.
For Lock scenes it drags down from Home's top edge to expose the saved
Cover Sheet widgets; evidence records `captureMethod: notification-center`.
The seven widget scenes must show real system widgets, not app lists or editors.

After a locale change/reboot, Cover Sheet can retain stale state and omit widgets
despite valid timeline proofs. In a controlled German capture, all three widgets
were absent even without a clock override; reopening the native wallpaper gallery
and selecting the current card **without editing it** made them render. Clock
ordering alone does not fix missing widgets. The helper now performs this native
gallery/reselect refresh for every Lock scene.

For Lock scenes, **clear the simulator status-bar override before fixture launch
and rendering**, refresh the saved wallpaper through the gallery, and allow the
widgets to render at the real clock. After timeline readiness and settling, request
09:41 for the fixture's reference date as a full UTC ISO timestamp with milliseconds
and `Z` (for example, `2026-08-30T13:41:00.000Z` for 09:41 local). The controlled
German capture accepted this override after the refresh. An early override has
also been observed with a January 1 date; neither timing nor timeline data proves
that the final pixels are correct.

Lock resume evidence must contain both
`lockScreenRefresh: wallpaper-gallery-reselect` and
`statusBarOverridePhase: after-widget-render`; evidence missing either is rejected
and recaptured. **Independent pixel QA remains mandatory**: verify the localized
date, all three widget families, and the saved surface rather than the gallery or
editor. Timeline readiness and resume fields do not replace visual review.

**Arabic, Hindi, Korean, and Traditional Chinese Lock clock exceptions:** iOS ignores
the requested 09:41 override on the observed `ar`, `hi`, `ko`, and `zh-Hant` Lock
surfaces. Hindi retains native 11:25/11:26 clocks, Traditional Chinese retains
8:55/8:56, and a Korean capture showed 9:00. Other locales, including Simplified
Chinese (`zh-Hans`), were observed at 09:41. Full-size visual review verified the
localized date, all three widgets, and layout for the accepted exceptions. They
retain authentic capture-time clocks with `pass_with_notes`; the manifest records
`clockOverrideEffective: false` for both Lock scenes in each affected locale.
The user did not require 09:41. No image editing or app-code change is needed to
force it. `statusBarTimeUTC` records the requested override, not proof of the visible
clock. Independent pixel QA remains mandatory for each accepted image, including
its date, language, widget contents, layout, and any clock exception.

**Native editor headings:** French, Italian, and Russian (`fr`, `it`, `ru`) use
native navigation-heading ellipses in `editing` and `event-countdown-app` at this
device width. Event content remains visible. These reviewed native UI notes are
recorded in the manifest; neither the app UI nor screenshot pixels were changed
to remove the ellipses.

**Portuguese circular unit:** in Portuguese and Brazilian Portuguese (`pt`,
`pt-BR`) `christmas-countdown-app` captures, the native circular widget unit appears
as `d…`, while the count **124** remains fully visible. Main visual QA reviewed
this native truncation; it is recorded in the completed manifest rather than
claiming the unit is fully displayed. No pixel or app-code change was made to hide it.

## Capture commands

App scenes (omit `--scenes` for all ten):

```sh
python3 tools/screenshots/capture-app.py \
  --simulator "$CAPTURE_SIM" --fixtures "$FIXTURES" \
  --output /private/tmp/countdowns-v12-app-pngs \
  --evidence /private/tmp/countdowns-v12-app-evidence \
  --source-commit "$SOURCE_COMMIT"
```

Widget scenes require an absolute AXe executable path and explicit permission to
change the dedicated simulator's settings. Run Home and Lock families separately:

```sh
HOME_SCENES=home-screen-widgets,wedding-countdown-app,vacation-countdown-app,anniversary-countdown-app,theme-park-trip-countdown-app
LOCK_SCENES=lock-screen-widgets,christmas-countdown-app
python3 tools/screenshots/capture-widgets.py \
  --simulator HOME-SIMULATOR-UUID --fixtures "$FIXTURES" \
  --output /private/tmp/countdowns-v12-home-pngs \
  --evidence /private/tmp/countdowns-v12-home-evidence \
  --source-commit "$SOURCE_COMMIT" --axe /absolute/path/to/axe \
  --allow-simulator-settings --scenes "$HOME_SCENES"
python3 tools/screenshots/capture-widgets.py \
  --simulator LOCK-SIMULATOR-UUID --fixtures "$FIXTURES" \
  --output /private/tmp/countdowns-v12-lock-pngs \
  --evidence /private/tmp/countdowns-v12-lock-evidence \
  --source-commit "$SOURCE_COMMIT" --axe /absolute/path/to/axe \
  --allow-simulator-settings --scenes "$LOCK_SCENES"
```

Both helpers accept `--locales en,de` (default all 23), `--scenes` subsets, and
`--resume` for matching image/fixture hashes and valid saved proofs. Settle defaults
are two seconds for app scenes and four for widgets. Use fresh output/evidence
folders after native patch changes; resume does not establish patch identity.
Do not change scripts, native instrumentation, or fixtures during a batch.

Concurrent Lock jobs serialize their Cover Sheet and wallpaper-gallery gestures
through the shared `countdowns-v12-native-ui.lock` file in Python's temporary
directory. This semaphore uses an owner-checked `flock`, waits at most 180 seconds,
and releases on exit; do not remove the lock file to bypass an active job.
Each AXe command has a 40-second timeout. Only the known remote automation session
creation error is retried, for at most three attempts with 4- and 8-second delays;
other errors fail immediately. Lock surface activation waits four seconds after
SpringBoard launch (Home waits 0.8 seconds). Widget-helper fixture launches allow
90 seconds; simulator shutdown/boot allow 90 seconds each, and boot readiness
allows 180 seconds. These command/lock limits are separate from the 35-second app
proof and 45-second timeline proof waits. The app-only helper uses a 40-second
`simctl` command timeout. After the late Lock clock request, the helper waits one
second and rechecks proofs before capturing; no timeout or retry proves rendering.

The widget helper shuts down only its dedicated simulator to update
`AppleLanguages` and `AppleLocale` in its own `.GlobalPreferences.plist`, preserving
all other fields. It backs up the original to
`<evidence>/run-config/original-global-preferences.plist`, then restores the original
preferences and boots in `finally`, including on capture failure. Host preferences
and SpringBoard page layout/list metadata are untouched. If forcibly killed before
cleanup, restore that backup while the simulator is shut down before reusing it.
Neither capture helper builds, installs, erases simulators, or publishes. The
workflow does not delete user data outside the dedicated fixture seed: native app
seeding replaces the dedicated demo events. Capture cleanup specifically clears
`Documents/website-screenshot-proof.json` and, for widgets, the five owned
`website-widget-timeline-{systemMedium,systemLarge,accessoryInline,accessoryCircular,accessoryRectangular}.json`
proof files. Use only dedicated capture simulators, not personal data stores.

## Proof and separate visual QA

Fresh captures clear only the app's website capture proof and, for widgets, its
five website timeline proof files. App readiness has a 35-second deadline and
requires the exact scene, locale, screen, localized event IDs/names, settings,
version 12.0.0, light appearance, **both lifetime and Pro access**, and disabled
iCloud sync/end notifications. Pro alone is insufficient.

Widgets additionally wait up to 45 seconds for fresh provider timeline records:
medium's first three events, large's first eight, and Lock rectangular/circular/
inline event indices 0/1/2, with matching locales, names, configuration, and generation
times. Evidence includes app/timeline proofs, timestamps, device state, fixture/image
SHA-256 hashes, and the supplied source commit. Missing proof fails the batch before
writing that capture. Timeline evidence is **`timeline-data`**, with
`renderingVerified: false`: it proves provider data, not pixels.

Each raw PNG comes directly from `simctl io screenshot`, checked as **1206 ×
2622** before atomic replacement. Checked-in PNGs may be losslessly recompressed
after preserving the raw evidence and hash; decoded pixels and dimensions must stay
unchanged. Keep PNGs **unframed**: no resizing, compositing, fake widget UI, or
baked-in device frame. Separately review every locale
and scene for correct language, event selection, layout, and saved widget surface.
Verify build provenance separately; a recorded source-commit argument is not proof
of the installed binary. Promote only reviewed PNGs to the exact manifest paths.

## Website checks; no publishing

`_includes/screenshot.html` uses exact locale/scene images and localized
`_data/screenshot_alts.yml` values, with no English fallback. `_sass/layout.scss`
adds the approved responsive phone bezel, island, and buttons; parent positioning
and transforms stay on the wrapper, not the native image. Homepage primary, guide,
and ideas heroes are eager; homepage secondary is decorative. Each homepage
preloads its localized `home-screen-widgets` image.

Build and validate both root and baseurl routing from the website repository:

```sh
rbenv exec bundle exec jekyll build --destination /private/tmp/countdowns-v12-site-review-01a05493
rbenv exec bundle exec ruby scripts/validate-screenshots.rb \
  --site /private/tmp/countdowns-v12-site-review-01a05493
rbenv exec bundle exec jekyll build --baseurl /preview --destination /private/tmp/countdowns-v12-site-preview-final-01a05493
rbenv exec bundle exec ruby scripts/validate-screenshots.rb \
  --site /private/tmp/countdowns-v12-site-preview-final-01a05493 --baseurl /preview
```

The validator checks all 391 source paths/dimensions and localized alts, plus image
and preload paths across **322 routes** (23 × home, ideas, and 12 guides), including
locale leakage, framing, and loading/accessibility attributes. `--verbose` lists all
failures. Missing files remain failures and must never be replaced with another
locale's capture.

The **2026-09-07 final** root and `/preview` builds and validators all exited **0**,
including the 17 Hindi additions, five revised Arabic images, and French Christmas
replacement. Each validator checked **391 source PNG paths, 391 localized alts,
322/322 routes, and 2,093 image/preload references**, with zero failures. The 17
Hindi built PNGs in each output match their `publishedImageSHA256` values; their
`imageSHA256` values retain the raw simulator bytes. Root and preview outputs match
the checked-in published files. The other 374 `imageSHA256` values remain capture-
time hashes from before the site's earlier lossless PNG recompression, so byte
equality is not expected for those published files. The public-output audit found no
tools, scripts, capture manifests, or private evidence in either build. The Hindi homepage,
Help Center, and longest guide were also reviewed in a browser at desktop and
390-pixel widths, including Devanagari line height and responsive navigation. This
records capture and static integration validation; browser review remains separate
from deployment or publishing.

Jekyll excludes `tools` and `scripts`; keep evidence outside public assets too.
This workflow does not deploy, publish, push, or modify the original native app.
