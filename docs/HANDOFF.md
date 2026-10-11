# Handoff

The state of the work. Read this first at the start of every session and update it last.
Each card is specified in [specs/](specs/); the rules for working on one are in
[specs/README.md](specs/README.md).

## Current

**Next card: 1.4.**

## Cards

### Phase 0: Foundation ([spec](specs/00-foundation.md))
- [x] 0.1 Domain types, and TrainingMath on load modes
- [x] 0.2 Database schema, records and AppDatabase
- [x] 0.3 Library and exercise-map files
- [x] 0.4 JEFIT CSV reader
- [x] 0.5 JEFIT importer
- [x] 0.6 Wire the database into the app, and an import screen
- [x] 0.7 Phase close

### Phase 1: Programs and the exercise library ([spec](specs/01-programs-library.md))
- [x] 1.1 App shell, theme and settings
- [x] 1.2 Queries and writes for exercises and programs
- [x] 1.3 Exercises tab
- [ ] 1.4 Exercise detail page
- [ ] 1.5 Create and edit exercises
- [ ] 1.6 Train tab and programs
- [ ] 1.7 Day editor
- [ ] 1.8 Exercise picker
- [ ] 1.9 Suggest a day
- [ ] 1.10 Phase close

### Phase 2: Workout screen ([spec](specs/02-workout-screen.md))
- [ ] 2.1 Workout engine
- [ ] 2.2 Active workout model and resume
- [ ] 2.3 Workout screen, list mode
- [ ] 2.4 Focus mode
- [ ] 2.5 Bottom bar and rest
- [ ] 2.6 Start, mini-player and navigation
- [ ] 2.7 Swap, add, history and plate calculator
- [ ] 2.8 Summary
- [ ] 2.9 Lock-screen countdown (Live Activity)
- [ ] 2.10 Remove the prototype and close the phase

### Phases 3–5 ([outline](specs/03-05-outline.md))
Specified in full after phase 2 closes.

## Session notes

Newest first. One entry per card: what was done, anything surprising, anything the next
card should know.

- **1.3**: Exercises tab with search (200 ms debounce), filter chips (ExerciseFilterBar, reused by the picker in 1.8) and rows showing last done plus the session's best set. Features/Shared/Formatting.swift holds display names, MuscleTags and SetFormat (BW−45×6, ×20 for reps only). Detail and editor are stubs until 1.4 and 1.5. Simulator: newest-first order; 'squat' lists Barbell Squat once.
- **1.2**: Data layer in GymApp/Data. Deviation from the spec: DayDetail.items is [DayItem] (a struct of dayExercise + exercise), not a tuple array, so it is Equatable without a hand-written ==. ExerciseFilter already has focus (card 1.8), and its rule plus tests are in place. lastSession takes an optional 'before' date for phase 2. DayString formats yyyy-MM-dd for notes. TestData.swift has the fixture builders. 60 tests, including browse against the real export.
- **1.1**: RootView with five tabs (History shows the count of finished workouts waiting); Theme.swift with volt accent, PrimaryButtonStyle, SecondaryButtonStyle and Chip; AppSettings in the setting table; SettingsView saves on every change (verified: defaultSets survives relaunch) and now owns the JEFIT import. The prototype opens full screen from Settings with a Close button; the DEBUG -importJEFIT launch argument moved to RootView. 46 tests.
- **0.7**: Phase 0 closed. Full suite green (43 tests). From a clean simulator install: import gives 468 workouts and 7,751 sets; a second import inserts only the import-run row; the prototype still runs. For phase 1: run anything that writes in the background through a test off the main actor (specs/README conventions). On a re-import, skip counts for cardio logs are lower, because already-imported workouts are skipped whole. That is expected.
- **0.6**: Database opens at launch (AppStartup) and seeds the library; HomeView menu imports from Files; DEBUG -importJEFIT <path> imports at launch. Simulator: 468 workouts and 7,751 sets imported; a second run inserts only the import-run row. That second run first failed with UNIQUE program.externalId: a protocol cast in the importer returns nil off the main actor (main-actor-isolated conformance), and only the background path hit it. Fixed with key paths; added a test that imports twice through ImportService off the main actor, and checked that test fails on the old code. Rule added to specs/README conventions. 43 tests.
- **0.5**: Importer mirrors reference_import.py step by step; rounding is half-to-even to match Python's round(). run() takes optional fileName/fileSHA256 for the import-run row. ImportReport is Hashable (ImportRunRecord needs it). Real export imports in 0.45 s and matches every count, skip reason, spot-checked workout and exercise best. 42 tests.
- **0.4**: Byte-level RFC 4180 tokeniser over the whole file, then section/block walk. GymAppTests/Fixtures.swift holds fixture paths, including the real export and hasRealExport. The real-export test ran (not skipped): every documented row count matches. 37 tests.
- **0.3**: Shared fields are a protocol (ExerciseDefinition) with two concrete Decodable structs; BundledExercises loads either file and names it on failure. LibrarySeeder uses insert(onConflict: .ignore). 32 tests.
- **0.2**: Schema.swift holds the spec SQL verbatim as migration v1; Records.swift has one nonisolated struct per table; AppDatabase as specified. ImportRunRecord.report is a String until 0.5. SchemaTests.swift also defines a small Make helper for test records. 28 tests.
- **0.1**: Domain enums in ExerciseTypes.swift; TrainingMath now takes LoadMode and skips drop segments in records; PastSet moved to Domain. The prototype maps ProtoEquipment to a LoadMode. 17 tests.

## Open questions

Questions a card raised that the spec did not answer. Do not guess; record them here and
stop.

- *(none)*

## Known issues

- *(none)*

## Useful commands

```bash
# Tests
xcodebuild test -project GymApp.xcodeproj -scheme GymApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | tail -30

# Regenerate generated data (only when its inputs change)
python3 -I tools/build_library.py
python3 -I tools/build_jefit_map.py data/jefit/jefit-export-2026-10-11.csv
python3 -I tools/reference_import.py data/jefit/jefit-export-2026-10-11.csv
python3 -I tools/reference_import.py GymAppTests/Fixtures/jefit_mini.csv --no-spot-checks \
  --out GymAppTests/Fixtures/jefit_mini_expected.json

# Simulator
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl install "iPhone 17 Pro Max" <path to GymApp.app>
xcrun simctl launch "iPhone 17 Pro Max" com.fuaadshurie.GymApp
xcrun simctl uninstall "iPhone 17 Pro Max" com.fuaadshurie.GymApp   # clean start
```
