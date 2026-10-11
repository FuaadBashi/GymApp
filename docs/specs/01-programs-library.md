# Phase 1: Programs and the exercise library

**Outcome:**
- The app has its real shell: five tabs and a theme of its own.
- You can browse and filter the library, read an exercise's full history and notes, and
  create your own exercises.
- You can build programs from a split, with each day's exercise picker filtered to that
  day's focus and a "Suggest a day" helper.

Logging stays in the prototype (Settings → Prototype) until phase 2.

**Read first:** [PRODUCT_BRIEF.md](../PRODUCT_BRIEF.md) ("Train" and "Exercises"),
[DECISIONS.md](../DECISIONS.md) #12 and #20–#25, and [TRAINING_RULEBOOK.md](../TRAINING_RULEBOOK.md)
§7 and §11. You also need everything from phase 0.

**Pattern for every screen in this phase:**
- **One view model per screen.** An `@Observable final class` (main actor, the default)
  holds the `AppDatabase` and the screen's state. It loads with
  `try await db.reader.read { … }` and writes with `try await db.writer.write { … }`.
- **Reload explicitly.** After every write it calls its own `reload()`. Do not use GRDB
  `ValueObservation` in this phase.
- **Queries and writes live in `GymApp/Data/`**, as `nonisolated enum` namespaces of
  static functions taking `Database`. Views never write SQL.

---

## Card 1.1: App shell, theme and settings

**Files:**

- create `GymApp/App/RootView.swift`, `GymApp/App/Theme.swift`,
  `GymApp/Data/AppSettings.swift` and `GymApp/Features/Settings/SettingsView.swift`
- change `GymApp/App/GymAppApp.swift`
- change `GymApp/Prototype/Views/HomeView.swift` (remove the import menu added in 0.6)
- create `GymAppTests/AppSettingsTests.swift`

**Steps:**

1. **`Theme.swift`.** Move the `Theme` enum out of `GymAppApp.swift` and replace its contents
   with these tokens:

   | Token | Value | Used for |
   |---|---|---|
   | `accent` | `Color(red: 0.78, green: 0.95, blue: 0.26)` ("volt") | tint, primary buttons, logged ticks, rest |
   | `onAccent` | `.black` | text and icons on `accent` |
   | `background` | `.black` | screens |
   | `card` | `Color(white: 0.11)` | cards |
   | `row` | `Color(white: 0.16)` | selected rows, chips |
   | `note` | `Color(red: 0.98, green: 0.83, blue: 0.38)` | sticky notes |
   | `upper`, `lower`, `core` | `Color(red: 0.45, green: 0.66, blue: 1.0)`, `Color(red: 1.0, green: 0.62, blue: 0.35)`, `Color(red: 0.75, green: 0.55, blue: 1.0)` | muscle tags by region |

   Also add:
   - `Theme.color(for region: BodyRegion) -> Color`: `fullBody` uses `accent`, `cardio`
     uses `.pink`.
   - `struct PrimaryButtonStyle: ButtonStyle`: full width, 54 pt tall, `accent` fill,
     `onAccent` semibold text, 16 pt corner radius; pressed means 0.97 scale and 0.85
     opacity.
   - `struct Chip: View`: a capsule label (`Theme.row` fill; `accent` fill and `onAccent`
     text when selected) with a tap action.

   The prototype keeps compiling: where it used `Theme.rest` and `Theme.logged`, use
   `Theme.accent`.
2. **`AppSettings.swift`.** A `nonisolated struct AppSettings: Equatable` with defaults:
   - `weightUnit` `.kg`
   - `weekStartsOn` `.sunday` (enum `sunday, monday`)
   - `defaultRestSeconds` 60
   - `defaultSets` 3
   - `defaultRepMin` 8, `defaultRepMax` 12
   - `lastTimeSource` `.sameDay` (enum `sameDay, anyWorkout`)

   Add `static func load(_ db: Database) throws -> AppSettings`, which reads the `setting`
   table and falls back to the default for missing or unparsable keys, and
   `func save(_ db: Database) throws`. The keys are the property names, values are strings,
   and enums use their raw values.
3. **`RootView.swift`.** A `TabView` using the iOS 18+ `Tab` API, with five tabs:

   | Tab | SF Symbol | View |
   |---|---|---|
   | Train | `figure.strengthtraining.traditional` | `TrainView` (card 1.6) |
   | History | `calendar` | placeholder |
   | Exercises | `dumbbell` | `ExercisesView` (card 1.3) |
   | Progress | `chart.xyaxis.line` | placeholder |
   | Settings | `gearshape` | `SettingsView` |

   - Until cards 1.3 and 1.6 land, their tabs show a placeholder too.
   - Each placeholder is a `ContentUnavailableView`:
     - History: "History arrives in phase 3", with the count of finished workouts in the
       database as its description.
     - Progress: "Progress arrives in phase 3".
   - `GymAppApp` shows `RootView` with `.tint(Theme.accent)` and
     `.preferredColorScheme(.dark)`.
4. **`SettingsView`.** A `Form`:
   - **Units:** kg/lb picker (`weightUnit`).
   - **Calendar:** week starts on Sunday or Monday.
   - **New exercises:** sets stepper (1–10), rep range (two steppers, keeping min ≤ max), and
     a rest picker (30–300 s, step 15).
   - **Last time shows:** same day / any workout.
   - **Data:**
     - "Import JEFIT export…", moved from HomeView, reusing `ImportService` and
       `ImportReportView`;
     - a read-only line with workout, set and exercise counts.
   - **Prototype:** a `NavigationLink` "Prototype workout (seed data)" opening the old
     `HomeView`.

   Every change saves immediately.

**Tests:**

- `AppSettings.load` on an empty database returns the defaults.
- Saving, then loading, round-trips every field.
- A stored `weekStartsOn = "tuesday"` loads as `.sunday`.

**Done when:** tests pass. On the simulator, all five tabs show, Settings changes persist
across relaunch, and the prototype opens from Settings. Take a screenshot of each tab.

**Out of scope:** the Train and Exercises content (later cards).

---

## Card 1.2: Queries and writes for exercises and programs

**Files:**

- create `GymApp/Data/ExerciseQueries.swift`, `GymApp/Data/ExerciseWrites.swift`,
  `GymApp/Data/ProgramQueries.swift` and `GymApp/Data/ProgramWrites.swift`
- create `GymAppTests/TestData.swift` (fixture builders) and `GymAppTests/DataLayerTests.swift`

**Types:**

```swift
nonisolated struct ExerciseFilter: Equatable {
    var searchText = ""
    var regions: Set<BodyRegion> = []      // empty = any
    var muscles: Set<Muscle> = []          // match primary or secondary
    var equipment: Set<Equipment> = []
    var force: Force? = nil
    var onlyDoneBefore = false
    var onlyFavorites = false
    var includeNonStrength = false         // stretching, plyometrics, cardio
}
nonisolated struct ExerciseListItem: Identifiable, Equatable {
    var exercise: ExerciseRecord
    var lastDoneAt: Date?
    var sessionCount: Int
    var lastSets: [WorkoutSetRecord]       // completed sets of the latest session, in order
    var id: String { exercise.id }
}
nonisolated struct ExerciseSession: Identifiable, Equatable {
    var workout: WorkoutRecord
    var workoutExercise: WorkoutExerciseRecord
    var sets: [WorkoutSetRecord]           // completed only, in position order
    var id: String { workoutExercise.id }
}
nonisolated struct DayDetail: Identifiable, Equatable {
    var day: ProgramDayRecord
    var items: [(dayExercise: DayExerciseRecord, exercise: ExerciseRecord)]  // in position order
    var id: String { day.id }
}
```

`DayDetail` holds tuples, so write its `==` by hand, comparing ids.

**"Finished" and "history"** in every query below mean workouts with `endedAt IS NOT NULL`
and sets with `completedAt IS NOT NULL`.

**`ExerciseQueries`:**

- `browse(_ db: Database, filter: ExerciseFilter) throws -> [ExerciseListItem]`:
  - **Excluded:** archived exercises, and library rows whose id is the `libraryId` of a
    non-archived `jefit` or `custom` exercise. The user's version replaces the library
    duplicate.
  - **Category:** unless `includeNonStrength`, only strength, powerlifting,
    olympicWeightlifting and strongman.
  - **Search:** split on whitespace; every term must occur in the name, case-insensitive.
  - **Filters:** empty sets mean any. `muscles` matches if any selected muscle is in the
    primary or secondary muscles.
  - **Order:** exercises with history first, by `lastDoneAt` descending; then the rest by
    name, case-insensitive.
  - **Implementation:**
    - Fetch the candidate exercises (about 1,070).
    - Fetch `exerciseId, MAX(startedAt), COUNT(DISTINCT workoutId)` in one grouped query
      over finished history.
    - Filter in Swift.
    - Fetch `lastSets` only for the items returned. No query inside a loop over all
      exercises.
- `sessions(_ db, exerciseId: String) throws -> [ExerciseSession]`: newest first.
- `lastSession(_ db, exerciseId: String, preferringDays dayIds: Set<String>) throws -> (ExerciseSession, isSameDay: Bool)?`
  (rulebook §7): the newest session whose workout's `programDayId` is in `dayIds`; if there
  is none, the newest session anywhere, with `isSameDay = false`.
- `notes(_ db, exerciseId:) throws -> [ExerciseNoteRecord]`: newest first.

**`ExerciseWrites`:**

- `createCustom(_ db, draft: ExerciseDraft, now: Date) throws -> ExerciseRecord`:
  - `ExerciseDraft` holds name, equipment, loadMode, primaryMuscles, secondaryMuscles,
    movementPattern, defaultRestSeconds and preferredUnit.
  - The new row has `id = "custom:\(UUID().uuidString)"`, `source = .custom`,
    `category = .strength` and `force`/`mechanic` nil.
  - `bodyRegion` is derived: the single region of all primary muscles; `fullBody` if they
    span regions or none are given.
  - Names are trimmed. A non-archived exercise whose trimmed name matches
    case-insensitively throws `ExerciseError.duplicateName(existingId)`.
- `update(_ db, exercise: ExerciseRecord)`:
  - Same name validation, excluding itself.
  - Changing `loadMode` on an exercise with any `workoutSet` throws
    `ExerciseError.loadModeLockedByHistory`. Its history would otherwise change meaning
    (rulebook §2).
- `setFavorite(_:id:_:)`, `setArchived(_:id:_:)`.
- `setStickyNote(_:id:text:)`: an empty string after trimming stores nil.
- `addNote(_:exerciseId:text:date:)`: stores the date as `yyyy-MM-dd`, `source = .app`.

**`ProgramQueries`:**

- `programs(_ db) -> [(program: ProgramRecord, dayCount: Int)]`: active first, then
  non-archived by `createdAt` descending, then archived by name.
- `days(_ db, programId:) -> [DayDetail]`: by position.
- `lineage(_ db, dayId:) -> [String]`: the day id followed by its `copiedFromDayId` chain,
  stopping at nil, at a repeat or after 10 hops.
- `lastDone(_ db, dayId:) -> Date?`: the newest `startedAt` of finished workouts whose
  `programDayId` is in the day's lineage.
- `nextDay(_ db, programId:) -> ProgramDayRecord?` (decision #12, rolling rotation):
  - the first day by position that has never been done;
  - otherwise the day with the oldest `lastDone`, breaking ties by lower position;
  - nil for a program with no days.
- `estimatedMinutes(for detail: DayDetail) -> Int` (rulebook §11 fallback):
  Σ `targetSets × (40 + restSeconds)` seconds, rounded to whole minutes.

**`ProgramWrites`:**

- `createProgram(_ db, name:split:fullBodyDays:makeActive:now:) -> ProgramRecord`. Days by
  split, all with the focus shown:

  | Split | Days (name, focus) |
  |---|---|
  | `fullBody` | "Full Body 1"…"Full Body N" (`fullBody`), N = `fullBodyDays` (2 or 3) |
  | `upperLower4` | Upper A, Lower A, Upper B, Lower B |
  | `upperLower6` | Upper A, Lower A, Upper B, Lower B, Upper C, Lower C |
  | `pushPullLegs3` | Push, Pull, Legs |
  | `pushPullLegs6` | Push A, Pull A, Legs A, Push B, Pull B, Legs B |
  | `custom` | "Day 1" (`custom`) |

  Upper and Lower days get focus `upper`/`lower`; Push, Pull and Legs days get
  `push`/`pull`/`legs`.
- `setActive(_ db, programId:)`: in one transaction, clears every other active program,
  then sets this one active and un-archived.
- `setArchived(_ db, programId:, _:)`: archiving the active program also deactivates it.
- `deleteProgram(_ db, programId:)`: only for `source = .app`, otherwise it throws.
  Workouts keep their data; their `programDayId` becomes nil through the foreign key.
- `addDay(_ db, programId:name:focus:)`: appends.
- `renameDay`, `setFocus`.
- `deleteDay`: its exercises cascade, and the remaining positions are renumbered 0…n-1.
- `addExercises(_ db, dayId:, exerciseIds: [String], settings: AppSettings)`: appends in the
  given order with `targetSets = settings.defaultSets`, `repMin`/`repMax` from settings, and
  `restSeconds` = the exercise's `defaultRestSeconds`.
- `updateItem(_ db, item: DayExerciseRecord)`, `removeItem` (renumber),
  `moveItem(_ db, dayId:, from: Int, to: Int)` (renumber).
- `copyDay(_ db, from sourceDayId:, into targetDayId:)`: deletes the target's items, inserts
  copies of the source's (new ids, same exercise, sets, reps, rest and note) and sets
  `target.copiedFromDayId = sourceDayId`. Copying a day into itself throws.

**`TestData.swift`.** Builders that insert straight into an in-memory database, so tests stay
short:

- `exercise(_ db, id:, name:, pattern: MovementPattern? = nil, region: BodyRegion = .upper, force: Force? = nil, loadMode: LoadMode = .total, archived: Bool = false, libraryId: String? = nil, source: ExerciseSource = .custom)`
- `program(_ db, name:, active:)`
- `day(_ db, programId:, name:, focus:, position:)`
- `finishedWorkout(_ db, dayId: String?, startedAt: Date, exercises: [(String, [(kg: Double, reps: Int)])])`

**Tests** (`DataLayerTests.swift`):

- **Dedupe:** with the library seeded and an exercise `jefit:1:12` whose `libraryId` is
  `lib:Barbell_Squat`, `browse` (no filters) does not contain `lib:Barbell_Squat`, but does
  contain `jefit:1:12`.
- **Search:** "incl bench" matches "Barbell Incline Bench Press" and "Smith Machine Incline
  Bench Press", not "Barbell Bench Press".
- **Order:** given three exercises last done on 1 Oct, 5 Oct and never, `browse` returns them
  in the order 5 Oct, 1 Oct, never.
- **Rotation:**
  - days A (done 3 Oct), B (done 5 Oct) and C (never) → `nextDay` is C;
  - after C is done on 6 Oct → A;
  - with A (3 Oct) and B (3 Oct) tied → A.
- **Lineage:** day X copied from Y, with a workout on Y at 5 Oct, gives `lastDone(X) == 5 Oct`.
- **Split templates:** `createProgram` builds the names and focuses in the table for each
  split, and `fullBodyDays: 3` gives three days.
- **Active program:** `setActive` on B, when A is active, leaves exactly one active: B.
- **Copying a day:** `copyDay` copies three items in order and sets `copiedFromDayId`.
  Copying into itself throws.
- **Custom exercises:**
  - creating "  Bench Press " when "bench press" exists (not archived) throws
    `duplicateName`;
  - a draft with primary muscles `[chest, triceps]` gets region `upper`;
  - one with `[quadriceps, chest]` gets `fullBody`.
- **History lock:** `update` that changes `loadMode` on an exercise with one logged set throws
  `loadModeLockedByHistory`.
- **Real export,** when present: after importing, `browse` with `onlyDoneBefore` returns 196
  minus the exercises with no imported sets. Compute that expected number in the test with
  SQL rather than hard-coding it, and assert the first item is the most recently done
  exercise (a SQL `ORDER BY` cross-check).

**Done when:** all tests pass.

**Out of scope:** UI.

---

## Card 1.3: Exercises tab

**Files:** create `GymApp/Features/Exercises/ExercisesView.swift`,
`GymApp/Features/Exercises/ExercisesViewModel.swift`,
`GymApp/Features/Exercises/ExerciseRow.swift` and
`GymApp/Features/Shared/MuscleTags.swift`. Change `RootView.swift`.

**Steps:**

1. `ExercisesView` is a `NavigationStack` titled "Exercises", with:
   - `.searchable(text:)` bound to `filter.searchText`;
   - a toolbar `+` that opens the custom exercise editor (card 1.5; until then the button is
     hidden).
2. **Filter bar.** A horizontally scrolling row of `Chip`s under the search field:
   - "Done before" and "Favorites" toggle their flags.
   - "Upper", "Lower" and "Core" toggle regions.
   - A "Muscles" chip opens a multi-select menu of `Muscle.allCases` by `displayName`.
   - An "Equipment" chip opens a multi-select menu.
   - A "Push/Pull" chip opens a menu: Any, Push, Pull.
   - A chip with a selection shows its count ("Muscles · 2").
3. **`ExerciseRow`.**
   - Name: `.headline`, one line.
   - Underneath, the `MuscleTags` for the primary muscles: small capsules tinted with
     `Theme.color(for: muscle.region)` at 20% opacity, with the text in that colour.
   - Then the equipment in `.secondary`.
   - Trailing: when there is history, the relative last-done date ("3 d ago",
     "2 mo ago") above the best set of the last session ("60×8"), both `.caption`
     monospaced digits.
   - A star when favourite.
4. **Loading.** `.task(id: filter)` reloads after a 200 ms debounce (`try await Task.sleep`),
   so typing does not query on every keystroke.
5. **Empty state.** A `ContentUnavailableView` with a "Clear filters" button.
6. Tapping a row pushes `ExerciseDetailView` (card 1.4; until then an empty destination).

**Done when:** on the simulator, after an import:
- "Done before" shows Cable Lat Pulldown (Wide Grip) and Barbell Bench Press near the top;
- searching "squat" lists Barbell Squat once (not the library duplicate);
- the "Lower" chip hides upper-body exercises.

Take screenshots.

**Out of scope:** the detail page and editor contents.

---

## Card 1.4: Exercise detail page

**Files:** create `GymApp/Features/Exercises/ExerciseDetailView.swift` and
`GymApp/Features/Exercises/ExerciseDetailViewModel.swift`.

**Steps:**

1. **Header.**
   - Name (`.title2.bold()`).
   - "Equipment · LoadMode.label".
   - `MuscleTags` for primary muscles, then secondary at 60% opacity.
   - Toolbar: a favourite star toggle, and a menu with Edit (non-library exercises), Archive
     or Unarchive, and "Duplicate as my exercise" (library exercises: opens the editor
     pre-filled from this one).
2. **Sticky note card** (`Theme.note` at 12% background): the `stickyNote`, or "Add a note
   you'll see every time" when empty. Tapping opens a sheet with a `TextEditor` and Save.
3. **Sections.** A segmented `Picker`: History, Notes, About.
   - **History:** `ExerciseQueries.sessions`, newest first. Each row has:
     - the date as `Tue 7 Oct 2026` and the workout title;
     - the sets as a line: `20×10 · 50×10 · 40×10`, warm-ups prefixed `W`;
       `bodyweightPlus` sets as `BW−45×6` or `BW+10×8`, `repsOnly` sets as `×12`;
     - the session's best `displayableE1RM`, right-aligned, as "1RM 66.7".
   - A top row reads "Charts and records arrive in phase 3".
   - **Notes:** `ExerciseQueries.notes`, newest first, each with its date, plus an "Add note"
     button.
   - **About:**
     - primary and secondary muscles;
     - movement pattern (if any);
     - category;
     - instructions as a numbered list;
     - for exercises with `libraryId`, "Library match: <library exercise name>".

**Done when:** on the simulator:
- Barbell Bench Press shows 79 sessions, newest 7 Oct 2026, with sets 20×10 · 50×10 · 40×10;
- Machine Assisted Pull-Up shows `BW−45×6` on 11 Oct;
- editing the sticky note survives relaunch.

Take screenshots.

---

## Card 1.5: Create and edit exercises

**Files:** create `GymApp/Features/Exercises/ExerciseEditorView.swift`.

**Steps:**

1. A `Form` in a sheet, used to create (draft defaults: equipment `.machine`, loadMode
   `.total`, rest = settings default, unit = settings unit) or to edit.
2. **Fields:**
   - Name.
   - Equipment (picker).
   - Load mode (picker), with a footer explaining the selected mode in one sentence:
     - total: "The number on the bar, stack or machine."
     - perHand: "One dumbbell's weight; volume counts both hands."
     - perSide: "One side's weight; reps are per side."
     - bodyweightPlus: "Weight added to your body weight; assistance is negative."
     - repsOnly: "No weight, just reps."
   - Primary muscles and Secondary muscles: each a `NavigationLink` to a multi-select list.
   - Movement pattern (picker including "None").
   - Default rest (30–300 s, step 15).
   - Unit (kg/lb).

   A read-only "Body region" row shows the derived region.
3. **Locked load mode.** When editing an exercise with history, the load-mode picker is
   disabled, with the footer: "Load mode can't change once an exercise has history.
   Create a new exercise instead."
4. **Saving.** Save calls `ExerciseWrites.createCustom` or `update`. A `duplicateName` error
   shows inline under the name field: "You already have an exercise called <name>."
5. **Wiring.** Connect the Exercises toolbar `+` (card 1.3) and the detail page's Edit and
   Duplicate actions (card 1.4).

**Done when:** on the simulator:
- creating "Cable Y Raise" (cable, total, shoulders, lateralRaise) shows it in the list under
  Upper;
- a second "cable y raise" shows the duplicate error;
- editing Barbell Squat's load mode is disabled.

---

## Card 1.6: Train tab and programs

**Files:**

- create `GymApp/Features/Train/TrainView.swift` and `GymApp/Features/Train/TrainViewModel.swift`
- create `GymApp/Features/Train/ProgramsListView.swift` and
  `GymApp/Features/Train/ProgramDetailView.swift`
- create `GymApp/Features/Train/NewProgramView.swift`
- change `RootView.swift`

**Steps:**

1. **`TrainView`** (a `NavigationStack` titled "Train"):
   - **With an active program:**
     - Its name as a section title.
     - A "Next up" card for `ProgramQueries.nextDay`. It shows:
       - the day name (`.title2.bold()`);
       - "N exercises · est. M min · last <date or 'never'>";
       - each exercise with its last-time summary from `ExerciseQueries.lastSession`
         (preferring the day's lineage when `lastTimeSource == .sameDay`), working sets
         joined by " · ".

       Then a `PrimaryButtonStyle` button, "Start <day>", disabled in this phase, with a
       caption: "Logging moves here in phase 2. Use Settings → Prototype meanwhile."
     - Below, every other day of the program as a compact card (name, exercise count, last
       done). Tapping one opens its day editor (card 1.7).
   - **With no active program:** a `ContentUnavailableView` "No program yet" with a "New
     program" button.
   - **Toolbar:** "Programs" (to `ProgramsListView`) and `+` (to `NewProgramView`).
2. **`ProgramsListView`:** sections Active, Programs and Archived, showing
   `ProgramQueries.programs`. JEFIT programs appear in Archived with a "JEFIT" caption.
   Swipe actions:
   - Archive or Unarchive;
   - Delete, for `app` programs only, with a confirmation dialog: "Delete <name>? Workouts
     you logged with it are kept."
3. **`ProgramDetailView`:**
   - Days in order, each tapping into the day editor.
   - Toolbar:
     - "Make active" when not active;
     - Rename (an alert with a text field);
     - "Add day" (custom name, focus picker).

   Days reorder with `.onMove` (positions renumbered by a `ProgramWrites` function you add
   for it: `moveDay`) and delete by swipe, with a confirmation.
4. **`NewProgramView`** (sheet):
   - A name field, pre-filled from the split ("Full Body", "Upper/Lower", "Push/Pull/Legs",
     "Custom").
   - The split as a vertical list of selectable cards, each showing its title and the
     generated day names joined by " · ".
   - For Full Body, a 2/3 days segmented control.
   - "Make active" (on by default).

   Create runs `createProgram` and pushes `ProgramDetailView`.

**Done when:** on the simulator, after an import:
- the Train tab shows "No program yet";
- creating "Full Body" with 3 days makes it active, and Train shows "Next up: Full Body 1",
  never done;
- the Programs list shows both JEFIT programs under Archived.

---

## Card 1.7: Day editor

**Files:** create `GymApp/Features/Train/DayEditorView.swift`,
`GymApp/Features/Train/DayEditorViewModel.swift` and
`GymApp/Features/Train/DayItemEditor.swift`.

**Steps:**

1. **Header:** the day name (tap to rename) and a focus `Menu` (all `DayFocus` cases with
   readable names).
2. **List of items:**
   - each row shows the name, "3 × 8–12 · rest 1:00" and the last-time summary;
   - `.onMove` reorders (`moveItem`) and swipe deletes (`removeItem`), with an `EditButton`
     in the toolbar;
   - tapping a row opens `DayItemEditor` (sheet): sets stepper 1–10, rep min and max
     steppers (keep min ≤ max by moving the other), rest picker 0–300 s (step 15), note
     field, Save.
3. **Footer buttons:**
   - "Add exercises" (`PrimaryButtonStyle`) opens the picker (card 1.8).
   - "Suggest a day" (secondary style, hidden when focus is `custom`) opens card 1.9.
4. **Toolbar menu:** "Copy from another day…" lists every day of every program, grouped by
   program, archived ones included. If this day already has items, ask: "Replace the N
   exercises in <day>?". Then run `copyDay`.

**Done when:** on the simulator:
- in the new Full Body program, "Full Body 1" copied from the JEFIT day "1FBD 1" shows its
  six exercises with last-time values from 7 Oct 2026;
- Train's Next up updates: Full Body 1 now has a last-done date through lineage, so Next up
  moves to Full Body 2, the first day never done;
- reordering and editing sets persist.

---

## Card 1.8: Exercise picker

**Files:** create `GymApp/Features/Train/ExercisePickerView.swift`.

**Steps:**

1. A sheet for one day. It reuses the search and filter bar from card 1.3 and calls `browse`.
2. **Focus filter.** A toggle "Only <focus> exercises", on by default and hidden for
   `fullBody` and `custom`, adds the day's focus rule:

   | Focus | Rule |
   |---|---|
   | upper | `bodyRegion == .upper` |
   | lower | `bodyRegion == .lower` |
   | push | `bodyRegion == .upper && force == .push` |
   | pull | `bodyRegion == .upper && force == .pull` |
   | legs | `bodyRegion == .lower` |

   Implement it by adding `focus: DayFocus?` to `ExerciseFilter` and applying it in `browse`.
   Add one test per row of the table to `DataLayerTests`.
3. **Selection.**
   - Rows are multi-select with a trailing checkmark.
   - Exercises already in the day appear disabled with the caption "In this day".
   - The bottom bar shows "Add N exercises" (`PrimaryButtonStyle`, disabled at 0) and calls
     `addExercises`.
   - A "New exercise" row at the top opens the editor (card 1.5); the created exercise
     comes back selected.

**Done when:** on the simulator:
- an Upper A day's picker shows no leg exercises until the toggle is switched off;
- a Push day lists Barbell Bench Press but not Cable Lat Pulldown;
- adding three exercises appends them in selection order.

---

## Card 1.9: Suggest a day

**Files:** create `GymApp/Data/DaySuggester.swift`,
`GymApp/Features/Train/SuggestDayView.swift` and `GymAppTests/DaySuggesterTests.swift`.

**Rules:**

```swift
nonisolated struct Slot: Equatable { let name: String; let patterns: [MovementPattern] }
nonisolated struct Suggestion: Identifiable, Equatable {
    let slot: Slot
    var exercise: ExerciseRecord?
    var alternatives: [ExerciseRecord]   // next 5 candidates, for swapping
    var reason: String
    var id: String { slot.name }
}
nonisolated enum DaySuggester {
    static func slots(for focus: DayFocus) -> [Slot]
    static func suggest(_ db: Database, dayId: String, now: Date) throws -> [Suggestion]
}
```

**Slots, in order:**

| Focus | Slots (name: patterns) |
|---|---|
| fullBody | Squat: squat · Press: horizontalPush, inclinePush · Vertical pull: verticalPull · Hinge or leg curl: hinge, kneeFlexion · Row: horizontalPull · Overhead press: verticalPush · Leg extension: kneeExtension · Biceps: bicepsCurl · Triceps: tricepsExtension, dip |
| upper | Press: horizontalPush, inclinePush · Row: horizontalPull · Overhead press: verticalPush · Vertical pull: verticalPull · Side delts: lateralRaise · Biceps: bicepsCurl · Triceps: tricepsExtension, dip |
| lower | Squat: squat · Hinge: hinge · Leg extension: kneeExtension · Leg curl: kneeFlexion · Single leg or glutes: lunge, hipThrust · Calves: calfRaise |
| push | Flat press: horizontalPush · Incline press: inclinePush · Overhead press: verticalPush · Side delts: lateralRaise · Chest fly: chestFly · Triceps: tricepsExtension, dip |
| pull | Vertical pull: verticalPull · Row: horizontalPull · Rear delts: rearDelt · Biceps: bicepsCurl · Traps or pullover: shrug, pullover |
| legs | the lower slots, then Abs: coreFlexion |
| custom | none |

**Choosing an exercise for each slot, in order:**

1. **Candidates** are non-archived exercises whose `movementPattern` is in the slot's
   patterns and that have finished history. Exclude any already in this day, and any already
   chosen for an earlier slot.
2. **Rank:**
   1. not used in any other day of the same program, first;
   2. `lastDoneAt` descending;
   3. distinct sessions in the 365 days before `now`, descending;
   4. name ascending.
3. The top candidate is `exercise`; the next five are `alternatives`.
4. **Reason text:**
   - "Not in your other days · last done 3 Oct" when rule 1 applied;
   - otherwise "Last done 3 Oct · 12 sessions this year";
   - with no candidate, `exercise = nil` and "Nothing in your history for this movement."

**Test fixture.** Program P has days D1 (fullBody, containing `bench`) and D2 (fullBody,
empty). All dates are in October of one year:

| Exercise | Pattern | History |
|---|---|---|
| squatA | squat | last done 10 Oct |
| squatB | squat | last done 1 Oct |
| bench | horizontalPush | last done 9 Oct, in D1 |
| incline | inclinePush | last done 2 Oct |
| pulldown | verticalPull | last done 8 Oct |
| rdl | hinge | never done |
| legCurl | kneeFlexion | last done 5 Oct |
| rowA | horizontalPull | last done 7 Oct, archived |
| rowB | horizontalPull | last done 3 Oct |
| legExt | kneeExtension | last done 6 Oct |
| curl | bicepsCurl | last done 4 Oct |
| pushdown | tricepsExtension | last done 4 Oct |

**Expected `suggest(D2)`:**

| Slot | Exercise |
|---|---|
| Squat | squatA |
| Press | incline |
| Vertical pull | pulldown |
| Hinge or leg curl | legCurl |
| Row | rowB |
| Overhead press | nil |
| Leg extension | legExt |
| Biceps | curl |
| Triceps | pushdown |

`Squat.alternatives == [squatB]`.

**UI** (`SuggestDayView`, a sheet):
- One row per slot: the slot name, the chosen exercise (or the reason, in `.secondary`), and
  a toggle that is on when there is an exercise.
- A "Swap" menu lists the alternatives.
- "Add selected" appends the toggled exercises in slot order with `addExercises`.

**Done when:** the tests pass. On the simulator, "Suggest a day" on the empty Full Body 3
proposes exercises from your history that are not in Full Body 1 or 2.

---

## Card 1.10: Phase close

1. Build your real program on the simulator from a clean install:
   - import the JEFIT export;
   - create "Full Body" (3 days, active);
   - copy 1FBD 1 into Full Body 1 and 2FBD 2 into Full Body 2;
   - suggest Full Body 3 and keep or swap the suggestions.

   Take screenshots of Train, each day and the Exercises tab.
2. In README.md, mark phase 1 **done** and update "What exists today".
3. In ROADMAP.md, tick phase 1.
4. In HANDOFF.md, record anything phase 2 needs to know.
