# Handoff

The state of the work. Read this first at the start of every session and update it last.
Each card is specified in [specs/](specs/); the rules for working on one are in
[specs/README.md](specs/README.md).

## Current

**Next card: 0.4.**

## Cards

### Phase 0: Foundation ([spec](specs/00-foundation.md))
- [x] 0.1 Domain types, and TrainingMath on load modes
- [x] 0.2 Database schema, records and AppDatabase
- [x] 0.3 Library and exercise-map files
- [ ] 0.4 JEFIT CSV reader
- [ ] 0.5 JEFIT importer
- [ ] 0.6 Wire the database into the app, and an import screen
- [ ] 0.7 Phase close

### Phase 1: Programs and the exercise library ([spec](specs/01-programs-library.md))
- [ ] 1.1 App shell, theme and settings
- [ ] 1.2 Queries and writes for exercises and programs
- [ ] 1.3 Exercises tab
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
