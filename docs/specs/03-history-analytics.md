# Phase 3: History and analytics (lean)

**Closed 12 October 2026.** All six cards done; see HANDOFF.md for notes.

**Outcome:** every finished workout since 2022 can be browsed, opened and corrected; each
exercise shows its progress and records; a Progress tab summarises recent training.

**Scope decision (12 October 2026):** lean. Deeper analysis, and anything that would use a
language model, belongs to a separate offline tool that reads the phase 4 export
(decision #36). Left out of this phase: the consistency heat strip and the body
measurements table.

**Read first:** rulebook §2–§6 and §10, decision #36, [03-05-outline.md](03-05-outline.md),
`Data/SummaryQueries.swift` (the pattern for derived figures), `Data/WorkoutWrites.swift`.

**Rules for the whole phase:**
- Every figure goes through `TrainingMath` or `SummaryQueries.muscles`; nothing derived is
  stored.
- History means finished workouts (`endedAt IS NOT NULL`) and completed sets.
- Weeks start on `AppSettings.weekStartsOn` and a workout belongs to the local date it
  started (rulebook §6).
- Query code is `nonisolated` and tested; views hold no arithmetic.

---

## Card 3.1: History queries

**Files:** create `GymApp/Data/HistoryQueries.swift` and `GymAppTests/HistoryTests.swift`.

```swift
nonisolated struct WorkoutListItem: Identifiable, Equatable {
    var workout: WorkoutRecord
    var duration: TimeInterval        // endedAt − startedAt
    var setCount: Int                 // completed, not warm-up, not drop
    var volumeKg: Double              // as SummaryQueries
    var exerciseNames: [String]       // position order
    var dayId: String?                // programDayId
    var id: String { workout.id }
}
nonisolated struct HistoryWeek: Identifiable, Equatable {
    var start: Date                   // local midnight of the first day of the week
    var workouts: [WorkoutListItem]   // newest first
    var id: Date { start }
}
nonisolated enum HistoryQueries {
    static func weekStart(of date: Date, weekStartsOn: WeekStart, calendar: Calendar = .current) -> Date
    static func weeks(_ db: Database, settings: AppSettings) throws -> [HistoryWeek]   // newest first, only weeks with workouts
    static func workoutDays(_ db: Database, inMonthOf date: Date) throws -> [Date: [String?]]  // local day → programDayIds
    static func sessionsThisWeek(_ db: Database, settings: AppSettings, now: Date) throws -> (done: Int, goal: Int?)
}
```

- `volumeKg` and `setCount` must equal `SummaryQueries.summary(...).volumeKg/.setCount` for
  the same workout. Compute them in one pass over all completed sets (the real history has
  7,751 sets; one query per workout is too slow), sharing the per-set arithmetic with
  `SummaryQueries` rather than re-deriving it.
- `goal` is the active program's `sessionsPerWeekGoal`, nil without an active program.

**Tests:** week start for Sunday and Monday settings, including a workout at 23:30 on the
last day of a week; `weeks` groups and orders correctly; list volume equals summary volume
for a workout with a `bodyweightPlus` set and a warm-up; `workoutDays` returns only the
month asked for; `sessionsThisWeek` counts finished workouts only.
With the real export (skipped without it): 468 workouts across the weeks, total sets equal
to the SQL count of completed non-warm-up, non-drop sets.

## Card 3.2: History tab

**Files:** create `GymApp/Features/History/HistoryView.swift`,
`HistoryViewModel.swift`, `MonthCalendar.swift`; change `App/RootView.swift` (replace the
placeholder).

- Top: a month calendar (`MonthCalendar`), week starting per settings, a dot under each day
  with a workout, coloured by program day (stable colour per day id from a small palette;
  grey for ad hoc and JEFIT workouts with no current day). Chevrons change month; tapping a
  day scrolls the list to that week.
- Under it: "This week: 2 of 3" when there is a goal, else "This week: 2".
- Then the weeks, newest first: a header "Week of 5 Oct · 3 workouts · 12,340 kg" and one
  row per workout: title, date and time, duration, sets, volume, and the exercise names in
  one secondary line.
- Rows open `WorkoutDetailView` (card 3.3; a stub until then). Reload on appear and when a
  workout finishes.
- Large lists: `List` with lazy rows; the real history must scroll smoothly.

**Done when:** on the simulator with the real import, the calendar shows October 2026 with
dots on the right days, the list starts with the newest workout, and scrolling to 2022 works.

## Card 3.3: Workout detail and editing

**Files:** create `GymApp/Features/History/WorkoutDetailView.swift`; change
`Data/WorkoutWrites.swift`; add tests to `GymAppTests/HistoryTests.swift`.

**Writes** (all keep `endedAt`, so the workout stays history):
- `rename(_ db, workoutId:, title:)`: trimmed; empty is rejected with `WorkoutError.emptyTitle`.
- `addLoggedSet(_ db, workoutExerciseId:, completedAt:)`: like `addSet` but completed, at the
  workout's `endedAt`.
- `deleteFinished(_ db, workoutId:)`: deletes the workout (rows cascade). The view confirms
  first (rulebook §10).
- Deleting the last set of an exercise in a finished workout removes that exercise.
  Deleting the last set of the workout is refused (`WorkoutError.lastSet`); delete the
  workout instead.

**View:** header (title, date, duration, effort, note, all editable through an Edit mode),
summary tiles reused from `SummaryView` (duration, volume with last time, sets, records), then
each exercise with its sets as `SetRow`-style rows. In Edit mode rows use `SetEditor`, sets can
be added or deleted, and set type can be changed. Every figure recomputes after each change
because the view reloads `SummaryQueries.summary`.

**Tests:** editing a set's load changes summary volume and can create or remove a record;
`deleteFinished` removes sets and leaves other workouts; `lastSet` refusal; rename trims and
rejects empty.

**Done when:** on the simulator, opening a 2024 workout shows its sets; changing a load
changes the volume tile; deleting asks first.

## Card 3.4: Exercise progress and records

**Files:** create `GymApp/Data/ExerciseStats.swift`,
`GymApp/Features/Exercises/ExerciseProgressView.swift`, `GymAppTests/ExerciseStatsTests.swift`;
change `ExerciseDetailView.swift` (a Progress section replacing the placeholder text) and its
view model.

```swift
nonisolated struct SessionPoint: Identifiable, Equatable {
    var workoutId: String; var date: Date
    var bestE1RM: Double?; var heaviestKg: Double?; var volumeKg: Double
    var id: String { workoutId }
}
nonisolated struct ExerciseRecords: Equatable {
    struct Mark: Equatable { var valueKg: Double; var reps: Int?; var date: Date; var workoutId: String }
    var heaviest: Mark?
    var bestE1RM: Mark?
    var bestVolume: Mark?
    var repRecords: [Mark]            // most reps at each distinct load (kg, rounded to 0.01), heaviest load first
}
nonisolated enum ExerciseStats {
    static func points(_ sessions: [ExerciseSession], loadMode: LoadMode, bodyWeightKg: (Date) -> Double?) -> [SessionPoint]  // oldest first
    static func records(_ sessions: [ExerciseSession], loadMode: LoadMode, bodyWeightKg: (Date) -> Double?) -> ExerciseRecords
}
```

- Built from `ExerciseQueries.sessions` (finished only). Bests through `TrainingMath.bests`,
  volume through `TrainingMath.volumeKg`. `bodyweightPlus` and `repsOnly` have no heaviest,
  1RM or rep records (§5), but do have volume (bodyweightPlus needs a body weight).
- Ties keep the earliest date (the record was set then).

**View:** a segmented metric picker (Est. 1RM, Heaviest, Volume), a range picker (3M, 1Y,
All), and a Swift Charts line with points; then the records list, each row linking to its
workout (`WorkoutDetailView`).

**Tests:** hand-calculated points and records for a three-session fixture including a
warm-up, a drop row and a tie; rep records per load. With the real export: for Barbell
Bench Press (`jefit:1:2`) the best e1RM equals a value computed independently in the test
from raw SQL rows with the Epley formula.

**Done when:** Barbell Bench Press shows a chart from 2022 to 2026 and records with dates.

## Card 3.5: Progress tab

**Files:** create `GymApp/Data/ProgressQueries.swift`, `GymApp/Features/Progress/*`,
`GymAppTests/ProgressTests.swift`; body-map artwork under `GymApp/Resources/BodyMap/` with
its licence in `PROVENANCE.md`; change `RootView.swift`.

- **Weekly bars**, last 12 weeks (per settings week start): volume, sessions and training
  time, as three small Swift Charts bar charts, each with "vs last week ±n%".
- **Muscles this week:** hard sets per muscle from `SummaryQueries.muscles` over the week's
  workouts, shown on a front/back body map (regions shaded by sets: 0, 1–5, 6–9, 10–20,
  over 20) and as a list with a 10–20 target band. A toggle switches to last week.
- **Recent records:** the last 20 records set (heaviest or est. 1RM beating every earlier
  session), newest first, linking to the workout.
- **Body weight:** a line chart from `bodyEntry`, an "Add weight" sheet (today, value, unit
  from settings) writing a `BodyEntryRecord` with `source = .app`.

**Artwork:** a freely licensed front/back anatomy outline (public domain, CC0, CC BY or
MIT). Record source URL, author and licence in `PROVENANCE.md`. Every muscle in `Muscle`
must map to at least one region; a test enforces this.

**Tests:** weekly totals equal the sum of `HistoryQueries` items for those weeks; weeks with
no workouts are present as zero; muscle sets for a fixture week; recent records order;
body-weight write and read back.

## Card 3.6: Phase close

1. Verify against the export by hand: a Python check (`tools/check_phase3.py`) computes, from
   the raw CSV and the reference importer, the best e1RM, heaviest load and best session
   volume for three exercises (bench press, leg press, lat pulldown); the app's figures on
   the simulator must match. Record both in HANDOFF.md.
2. JEFIT's own `EXERCISE RECORDS`: report how many match the app's best e1RM (JEFIT_EXPORT.md
   trap 6 expects about 155 of 195). A difference is reported, not fixed.
3. Screenshots of History, a workout detail, an exercise's Progress and the Progress tab.
4. README, ROADMAP and HANDOFF updated; phase 3 closed.
