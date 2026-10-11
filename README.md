# GymApp

A private, offline training log for one iPhone, built in SwiftUI. It keeps the training side
of JEFIT (exercises and how they're categorised, programs, set logging, the calendar and the
analytics) and drops the social feed, points, upsells and account. Everything lives on the
phone; nothing is sent anywhere.

**What exists today:** a prototype of the workout screen running on real data. It has two
full-body days seeded from my JEFIT export, last-time values, per-exercise notes, a rest timer
that alerts with the phone locked, and a workout that survives the app being killed
mid-rest. The project builds with GRDB and a test target, and all 199 JEFIT exercises are
classified for import. **What doesn't yet:** the database, the in-app import, programs,
history and analytics. [The roadmap](docs/ROADMAP.md) has the order and what "done" means for
each phase.

## Review guide

Start with [the training rulebook](docs/TRAINING_RULEBOOK.md): every number the app shows is
defined there. [The decisions](docs/DECISIONS.md) explain the constraints, and
[the JEFIT export notes](docs/JEFIT_EXPORT.md) cover the import format and its traps. In code,
[`TrainingMath`](GymApp/Domain/TrainingMath.swift) implements the rulebook and
[`Load`](GymApp/Domain/Load.swift) stores weights exactly as entered.

## Status

| Phase | Focus | State |
|---|---|---|
| – | Workout-screen prototype on JEFIT data | done |
| 0 | Database, full JEFIT import, exercise library | **next**; exercise classification done |
| 1 | Programs and the exercise library | not started |
| 2 | Workout screen | not started |
| 3 | History and analytics | not started |
| 4 | Import, export and backups | not started |
| 5 | On the phone | not started |

## The constraints this repo is shaped around

- **The gym has no signal and the Mac is at home.** Workouts live on the phone and are written
  after every set, so a session survives iOS killing the app while I'm in another app.
- **The phone is locked between sets.** Rest is stored as an absolute end time plus a local
  notification, so the alert fires whether the app is open, backgrounded or killed. That is
  why this is native and not a web app.
- **No paid Apple membership.** It installs with a free Apple ID. The install expires every
  seven days and is re-sent from Xcode; the data survives the re-send.
- **A chart is only as honest as its definitions.**
  - Dumbbell loads are per hand.
  - Assisted pull-ups count as body weight minus the assistance.
  - Warm-ups never count towards volume or records.
  - A load stays exactly as entered: 45 lb stays 45 lb.
  - Records, volume and estimated 1RM are computed from logged sets, never stored.

## Four years of history

The JEFIT export is the starting data, and it has traps:

```
JEFIT export, Aug 2022 – Oct 2026
  workouts                       492
  exercise entries             2,552
  exercises                      197 logged, plus 2 custom never used
  set rows vs summary string     781 agree, 115 disagree -> set rows win
                                 (checked against JEFIT's own history screen)
  assisted exercises               4, logged as positive help -> stored as negative
  bodyweight "weights"           JEFIT's 10 kg default, dropped on import
```

[`tools/build_jefit_map.py`](tools/build_jefit_map.py) classifies every exercise by
equipment, load mode, muscles and movement pattern. Its rules sit in one reviewable file,
with explicit overrides where they get an exercise wrong.

## Build

Requires Xcode 26 and the iOS 26 simulator.

```bash
git clone https://github.com/FuaadBashi/GymApp.git
cd GymApp
xcodebuild -project GymApp.xcodeproj -scheme GymApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

The prototype reads `GymApp/Prototype/PrototypeSeed.json`, which is generated from a personal
JEFIT export and kept out of the repository. Without it, the app opens and says what is
missing. To build one from your own export:

```bash
python3 tools/make_prototype_seed.py path/to/jefit-export.csv --days "Day 1" "Day 2"
```

## Tests

```bash
xcodebuild test -project GymApp.xcodeproj -scheme GymApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

## Layout

```
GymApp/App/          entry point, app delegate, theme
GymApp/Domain/       Load, SetType, TrainingMath (the rulebook in code)
GymApp/Services/     rest-timer notifications
GymApp/Prototype/    the workout-screen prototype, replaced phase by phase
GymApp/Resources/    data bundled with the app (JEFIT exercise map)
GymAppTests/         unit tests (Swift Testing)
tools/               JEFIT parsing, exercise classification, prototype seed
third_party/         free-exercise-db, public domain
docs/                brief, decisions, roadmap, rulebook, export notes
```
