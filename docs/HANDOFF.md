# Handoff

The state of the work. Read this first at the start of every session and update it last.
Each card is specified in [specs/](specs/); the rules for working on one are in
[specs/README.md](specs/README.md).

## Current

**Next card: 3.1.** Unattended run authorised 12 October: lean phase 3, then phase 4 and the phase 5 code; spec and build card by card, push after every card, judgement calls under Open questions.

**Phase 2 closed: Card 2.10 complete locally (11 October 2026).**
The post-phase-2 additions are implemented and tested locally, with initial media
coverage for eight barbell and bodyweight lifts; see [02a-additions.md](specs/02a-additions.md).
Choose an independent backup folder on the actual phone. Phase 3 awaits a full spec and has not started.
The user authorised committing all pending work on 11 October; phase-2 closure and
the additions are recorded together in Git. No phase-3 implementation was started here.

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
- [x] 1.4 Exercise detail page
- [x] 1.5 Create and edit exercises
- [x] 1.6 Train tab and programs
- [x] 1.7 Day editor
- [x] 1.8 Exercise picker
- [x] 1.9 Suggest a day
- [x] 1.10 Phase close

### Phase 2: Workout screen ([spec](specs/02-workout-screen.md))
- [x] 2.1 Workout engine
- [x] 2.2 Active workout model and resume
- [x] 2.3 Workout screen, list mode
- [x] 2.4 Focus mode
- [x] 2.5 Bottom bar and rest
- [x] 2.6 Start, mini-player and navigation
- [x] 2.7 Swap, add, history and plate calculator
- [x] 2.8 Summary
- [x] 2.9 Lock-screen countdown (Live Activity)
- [x] 2.10 Remove the prototype and close the phase

### Phase 3: History and analytics, lean ([spec](specs/03-history-analytics.md))
- [ ] 3.1 History queries
- [ ] 3.2 History tab
- [ ] 3.3 Workout detail and editing
- [ ] 3.4 Exercise progress and records
- [ ] 3.5 Progress tab
- [ ] 3.6 Phase close

### Phases 4–5 ([outline](specs/03-05-outline.md))
Specified when phase 3 closes.

## Requested after phase 2

Recorded in [post-phase-2 additions](specs/post-phase-2-additions.md): exact-exercise
stills and demonstrations; set and session-exercise notes; deload, max rep, MR - 1/2/3,
injury, form and warm labels; layered local and independent backup/recovery of all edits,
including unfinished workouts offline. Implemented under [02a-additions.md](specs/02a-additions.md).
Max rep = zero reps left; MR −1/−2/−3 = one/two/three reps left in the tank, confirmed
by the user. Backup/recovery moved forward from phase 4. Media coverage expansion and
physical-device/cloud-provider failure checks remain open.

## Session notes

Newest first. One entry per card: what was done, anything surprising, anything the next
card should know.

- **Media and failure checks (11 Oct)**: Exact offline media now covers eight movements: bench press, back squat, deadlift, bent-over row, incline bench press, standing overhead press, pull-up and hanging leg raise (FitnessScape CC BY 3.0; see Resources/ExerciseMedia/PROVENANCE.md). Variants that differ (seated press, reverse-grip row, Romanian deadlift, assisted pull-up) deliberately get no media. `ExerciseMediaPlayback` stops hover playback when Reduce Motion turns on; explicit Play still works. Failure tests: full primary rolls back the edit and keeps the workout and last good copy; full backup storage keeps the committed workout and earlier copies; an unavailable external folder sets pending and a retry succeeds once it returns (fixed a stale-bookmark refresh); an interrupted restore leaves the primary and pending candidate in place. Found and fixed: every snapshot left a `.partial-shm` sidecar (the WAL backup's shared memory file outlived the rename); sidecars are now removed after publish or abort, with a WAL-pool test that fails without the fix. Startup reclaims staged partials left by a killed copy. Simulator: planted a half-written copy, killed and relaunched the app; the partial and old sidecars were gone, all 9 snapshots pass quick_check, the newest holds 468 workouts / 7,751 sets. Fresh-install restore earlier reproduced 471 workouts / 7,783 sets with every table matching. 122 tests pass. **Still needs the phone:** choosing the outside backup folder, cloud-provider availability (iCloud Drive/Files), real-disk full and signing; pointer hover needs an iPad or trackpad.
- **A1–A3 additions (11 Oct)**: Added FULL synchronous primary writes, verified portable SQLite snapshots after changed commits, retention (30 latest plus monthly), external-folder bookmarks/hash/read-back validation, pending/retry status, share/export copies, validated staged restore and safety archives including damaged primary/WAL and displaced drafts. Startup can recover from a selected backup without deleting broken primary data. Atomic drafts replay unfinished number/type/metadata/summary edits on launch; a newer draft cannot be erased by an older save. Migration v2 adds set note, nullable reps-in-reserve 0–3 and independent deload/injury/form annotations. Session exercise notes remain separate from sticky notes; metadata appears in workout/summary/exercise history and is not inherited as today's annotation. Warm uses existing warm-up type. MR labels do not invent reps or affect existing maths. Explicit media-ID mappings cover barbell bench press and back squat with bundled FitnessScape CC BY 3.0 real footage/stills, tap/hover playback and attribution; no substitution for different/custom variants. 114 tests in 15 suites passed (`/tmp/gymapp-additions-tests.log`), including migration, backup/restore, damaged primary, unavailable external folder, retention, rollback, metadata and interrupted-draft replay. Isolated simulator `GymApp Additions` used a read-only copy of original history: terminated/relaunched before note Done, confirmed note/MR−1/form survived; exercise note and warm-up selection persisted in both primary and latest backup, one unfinished session and 30 retained copies. Squat still/play/stop and restore preview verified visually. Screenshots: additions-notes-labels.png, additions-exercise-media.png, additions-recovery.png. Pointer hover/Reduce Motion behavior, physical full-disk/kill-during-copy and cloud-server upload not verified on a physical device. External folder selection is still required on the real phone. Narrowed `.gitignore` personal-data rule to `/data/`: it had also excluded Swift source in GymApp/Data. No commits/pushes; preserved separate phase-2/Live Activity work.

- **2.10 phase close (11 Oct)**: Reviewed workout lifecycle, persistence, summary calculations and rest activity behavior. Prototype directory, seed script, ignored seed entry, Settings link and `ProtoEquipment` references are absent. Rechecked the persisted Full Body 1: finished, 13/13 sets across six exercises, rest cleared; loads reproduce 3,808.3 kg. Visually checked existing list/focus/rest screenshots and `summary.png` (the earlier Full Body 3 leg-press summary: 3 sets, 1,770 kg, 0 records). `full-body-summary.png` was mislabelled and actually shows the History placeholder; it is not summary evidence. The owner requested using existing session evidence while parallel simulator work continues. Before that reply, resumed Full Body 2, captured `phase-2-close-list.png`, `phase-2-close-focus.png`, `phase-2-close-rest.png`, and verified terminate/relaunch mid-rest (0:57 → 0:39); that verification workout remains unfinished, with seven sets logged. Review fixed finish/discard clearing the visible session after failed database writes; trigger-based regression tests verify the session and persisted sets survive. Launch also exposed a WAL safety-copy issue in the concurrent recovery additions; portable copies now use DELETE journal mode, with a DatabasePool regression test. Verified the existing on-disk database opens and resumes without deleting data. Final suite: 112 tests in 15 suites passed (`** TEST SUCCEEDED **`, `/tmp/gymapp-2-10-complete-tests.log`); `git diff --check` passed. README and ROADMAP mark phase 2 done. Separate additions continue; phase 3 waits for its spec. Changes left uncommitted.

- **2.9 expiry follow-up (11 Oct)**: Accepted clearing on return rather than requiring removal while suspended. Added `context.isStale` presentation: lock screen/expanded Island show “Rest over”, compact shows “Ready”, minimal shows a checkmark. Notification and next-set details are retained. Verified locked countdown, alert at expiry, system-driven “Rest over” without reopening, and removal after return; screenshot `docs/screenshots/live-activity-rest-over.png`. iOS scheduled its stale refresh about 60 seconds after the deadline on this simulator, so 0:00 can remain during that system-controlled delay; the revised criterion explicitly permits it. All 98 tests passed on rerun (`** TEST SUCCEEDED **`); the first run hit the existing 0.2-second extension test timing race while locked. No tests weakened. The Full Body 2 verification workout now has two squat sets logged. Changes remain uncommitted. Card 2.10 still awaits final review.

- **2.9 original verification**: Created GymAppWidgets through Xcode's Widget Extension wizard, with Include Live Activity on and configuration App Intent/control off; embedded in GymApp. Untouched template built successfully. Shared RestActivityAttributes is compiled into both targets; the extension now contains only the rest Live Activity. Lock screen and Dynamic Island UI use the absolute end time and volt accent. ActiveWorkoutModel requests, updates and ends activities, restores an existing activity on resume, logs request errors, and owns expiry independently of WorkoutView. App and extension deployment targets are 26.1 and marketing versions both 0.1. All 98 tests passed, including minimised expiry and cancellation of the earlier deadline after extension. Lock-screen countdown verified; screenshot docs/screenshots/live-activity-rest.png. Locked expiry check failed: after 60 s of rest while locked, the notification arrived but the activity remained at 0:00 (docs/screenshots/live-activity-expired-locked.png). Returning to GymApp cleared rest and ended the activity; locking again confirmed it was gone. The simulator has a Full Body 2 verification workout in progress, with one squat set logged. No finished history was deleted.
- **2.10 (partial)**: The interrupted Full Body 1 session had already reached its summary. Verified the saved workout is finished, with all 13 sets completed across 6 exercises and no rest end remaining. Bench values are 20×10, 50×10, 40×10. Volume is 3,808.3 kg, displayed as 3,808 kg, equal to last time; no new records. Saved docs/screenshots/full-body-summary.png; list, focus and rest screenshots from cards 2.3–2.5 remain available. README and ROADMAP now describe the implemented screens and removed prototype. After the full test run and relaunch, Train shows Full Body 2 next and no mini-player. All 96 tests passed (`** TEST SUCCEEDED **`); existing unused-write-result and App Intents metadata warnings remain. Card 2.9 remains outstanding, so phase 2 is not marked closed.
- **2.8**: Summary: SummaryQueries (volume with body weight, previous volume from the day lineage, records vs earlier bests, hard sets per muscle), BodyQueries.weightKg, SummaryView (tiles, records, muscles via FlowLayout, exercises, effort 1–10 and note). RootView's cover shows the summary after finish until Done. The prototype was deleted here rather than in 2.10 (its SummaryView.swift clashed by file name): GymApp/Prototype, tools/make_prototype_seed.py, the .gitignore line and the Settings link are gone. Simulator: 3 × 59×10 leg press → volume 1,770 kg, 3 sets, quads 3 / glutes 1.5 / hamstrings 1.5; Done returns to Train with Full Body 1 next up.
- **2.7**: Swap (WorkoutExercisePicker with Same movement chip, Also change it in <day>), add exercise, ExerciseHistorySheet (the full detail view in a medium/large sheet), PlateMath + PlateMathTests, PlateCalculatorView, platesKg/platesLb settings. Collection[safe:] moved to WorkoutView.swift. ExerciseFilter gained movementPattern.
- **2.6**: Start/Resume on Train, Empty workout in the + menu, fullScreenCover in RootView, MiniPlayer via tabViewBottomAccessory(isEnabled:). That API needs iOS 26.1, so the deployment target is now 26.1 (phone is on 26.6). Simulator: mini-player shows rest countdown; kill + relaunch mid-rest resumed with the countdown still right (0:43 → 0:33 ten seconds later).
- **2.5**: WorkoutBottomBar + RestRing (TimelineView 0.25 s from restEndsAt). Simulator: logged a set, −15 s ×3, sent home; SpringBoard delivered rest-timer at 20:00:37 with body 'Next: Machine Leg Press, set 2 — 59 kg × 10'. No stale bar on return.
- **2.4**: FocusView: big steppers, Set N of M, Done list with comparisons and unlog, Up next strip, horizontal swipe between exercises. Same selection as the list.
- **2.3**: Workout list: ExerciseCard (collapsed summary / expanded set table with Today line, sticky note, context menu for set type, delete), SetRow (W/D labels, F badge, ↑/↓/= via SetComparison), SetEditor (steppers with repeat, tap-to-type, unit toggle keeps the number). Built together with 2.4–2.7 because WorkoutView references all of them; one commit.
- **2.2**: ActiveWorkoutModel (Features/Workout): one instance made in RootView (it needs the opened database) and passed with .environment(model); resumeIfNeeded in RootView .task. Every op = write, reload, sync the rest alert through RestScheduling (RestNotifier conforms; already lived in Services). Selection advances set → next item with planned sets, wrapping. SetFormat.long gives the notification text. Simulator kill-and-relaunch check deferred to 2.6, when Start exists; covered by a resume unit test.
- **2.1**: Workout engine: WorkoutQueries (inProgress, snapshot with lineage-aware previous) and WorkoutWrites (start with prefill, log/unlog/update/add/delete set, add/swap/remove/move exercise, rest adjust, finish keeps only logged sets and drops empty workouts, discard, note/effort). 14 engine tests. finish clamps endedAt to >= startedAt for the CHECK constraint.
- **1.10**: Phase 1 closed. Clean install + import, new Full Body (3 days, active), FB1 ← 1FBD 1 (6 exercises, last 7 Oct), FB2 ← 2FBD 2, FB3 from Suggest a day (9 slots filled, none overlapping FB1/FB2); FB3 is next up. Screenshot in docs/screenshots/train.png. For phase 2: Train's Start button is still a stub pointing at the prototype; DayDetail and TrainViewModel.card give the day's items and last-time sets; ProgramQueries.lineage must be used for last-time lookups. Decision #36: phase 3 analytics may move to a separate offline tool, so keep the phase 4 export complete.
- **1.9**: Suggest a day: DaySuggester slots and ranking, swap menu, add selected.
- **1.8**: Exercise picker: focus toggle, multi-select in tap order, In this day rows, New exercise.
- **1.7**: Day editor: rename, focus menu, item list (edit sheet, reorder, delete), Add exercises / Suggest a day, and Copy from another day (nested menu by program, confirm before replace). Simulator: copying JEFIT 2FBD 2 into Full Body 2 gave 10 exercises with last-time values from 11 Oct through lineage. Card hit areas use .contentShape(.rect). Picker and suggestions are stubs until 1.8 and 1.9.
- **1.6**: Train tab (Next up with last-time summaries, other days), Programs list (Active, Programs, Archived; swipe to archive or delete app programs), Program detail (reorder, delete, make active, rename, add day), New program split picker. Routing uses TrainRoute through one NavigationStack path. TrainViewModel.card() is shared with Program detail. Simulator: a new Full Body (3 days) shows Next up Full Body 1, never done; the JEFIT programs are under Archived. Rows inside List use .buttonStyle(.plain) to avoid accent-tinted text.
- **1.5**: Exercise editor (create, edit, duplicate from library) with muscle multi-select and the derived region shown. The load mode is locked when there is history. Duplicate names are rejected, library names included, shown inline (checked on the simulator with 'barbell squat'). Simulator taps landing mid-typing can save a truncated name: pause before tapping Save when testing.
- **1.4**: Exercise detail page: header, sticky note (edit sheet), History/Notes/About. Simulator: Barbell Bench Press shows 79 sessions, newest 7 Oct 2026 20×10 · 50×10 · 40×10, warm-ups marked W. Sticky-note save covered by a unit test. Noticed: JEFIT's Barbell Bench Press has no libraryId in the map, so 'Barbell Bench Press - Medium Grip' from the library still lists beside it; linking top exercises to library entries in build_jefit_map.py OVERRIDES would remove such duplicates (see Known issues).
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

None for card 2.9: expiry behavior settled in decision #37.

## Known issues

- Some JEFIT exercises have an obvious library equivalent that name matching missed (e.g. Barbell Bench Press ↔ "Barbell Bench Press - Medium Grip"), so both appear in Exercises. Fix by adding `libraryId` overrides in `tools/build_jefit_map.py` for the most used exercises, then regenerating the map and the reference expectations.

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
