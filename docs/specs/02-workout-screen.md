# Phase 2: Workout screen

**Outcome:** a full session is logged in the app, on the database, without touching JEFIT.
- The workout screen is a scrolling list of exercise cards with a focus-mode toggle.
- A mini-player above the tab bar shows a workout in progress.
- Rest alerts work with the phone locked.
- Exercises can be swapped or added mid-workout.
- The summary shows records and compares with last time.
- The prototype is deleted at the end of the phase.

**Read first:** [PRODUCT_BRIEF.md](../PRODUCT_BRIEF.md) ("The workout screen"), decisions
#23–#24, and rulebook §3, §5–§7, §9 and §10. Look at `GymApp/Prototype/` for behaviour
already proven there: the rest timer as an absolute end time, ghosted prefilled values and
↑/↓ comparisons. **Do not copy its storage or its one-exercise-per-page layout.**

---

## Card 2.1: Workout engine

**Goal:** every workout operation as a database write, tested without UI.

**Files:** create `GymApp/Data/WorkoutQueries.swift`, `GymApp/Data/WorkoutWrites.swift` and
`GymAppTests/WorkoutEngineTests.swift`.

**Types:**

```swift
nonisolated struct WorkoutSnapshot: Equatable {
    var workout: WorkoutRecord
    var items: [Item]
    nonisolated struct Item: Identifiable, Equatable {
        var workoutExercise: WorkoutExerciseRecord
        var exercise: ExerciseRecord
        var sets: [WorkoutSetRecord]          // position order, completed and planned
        var previous: ExerciseSession?        // rulebook §7, finished sessions only
        var previousIsSameDay: Bool
        var id: String { workoutExercise.id }
        var plannedSets: [WorkoutSetRecord] { sets.filter { $0.completedAt == nil } }
    }
    var completedSetCount: Int
    var totalSetCount: Int
}
nonisolated struct SetEdit: Equatable {
    var loadHundredths: Int?
    var unit: WeightUnit
    var reps: Int
    var type: SetType
}
nonisolated enum WorkoutError: Error, Equatable {
    case alreadyInProgress, notFound, swapAfterLogging, invalidReps
}
```

**`WorkoutQueries`:**

- `inProgress(_ db) -> WorkoutRecord?`: the one with `endedAt IS NULL`.
- `snapshot(_ db, workoutId:, settings:) -> WorkoutSnapshot`:
  - `previous` is computed with `ExerciseQueries.lastSession`, preferring the workout's day
    lineage when `settings.lastTimeSource == .sameDay`;
  - it only considers finished workouts that started before this one.

**`WorkoutWrites`** (every function takes `_ db: Database` first):

- `start(dayId: String?, settings:, now:) -> WorkoutRecord`:
  - Throws `alreadyInProgress` if `inProgress` is not nil.
  - Creates the workout:
    - `source = .app`, `startedAt = now`;
    - `title` = the day's name, or "Workout";
    - `programDayId = dayId`.
  - For each day item in order, creates a `WorkoutExerciseRecord`:
    - `dayExerciseId`, `targetSets`, `repMin`, `repMax` and `restSeconds` copied from the item;
    - its planned sets come from **prefill**.
- **Prefill** (private, used by start, add and swap). With `previous` as in `snapshot`:
  1. **Copy last time.** Rows start as the previous session's completed sets, in order:
     the same `loadHundredths`, `unit`, `reps` and `type`, with `completedAt = nil`.
  2. **Pad up to the target.** If there are fewer rows than `targetSets` (or
     `settings.defaultSets` when there is no target), append copies of the last row as
     `.working`. When there are no rows at all, create `targetSets` rows with:
     - load `nil` for `repsOnly`, otherwise `0`;
     - `unit = exercise.preferredUnit`;
     - `reps = repMin` (`settings.defaultRepMin` when there is no target);
     - type `.working`.
  3. **Keep extras.** More rows than the target stay: last time had extra sets.
- `logSet(setId:, now:)`:
  - Sets `completedAt = now`.
  - If the set's workout exercise has `restSeconds > 0`, sets the workout's
    `restEndsAt = now + restSeconds` and `restDurationSeconds = restSeconds`.
- `unlogSet(setId:)`: sets `completedAt = nil` and leaves the rest untouched.
- `updateSet(setId:, edit: SetEdit)`: throws `invalidReps` for reps < 0.
- `addSet(workoutExerciseId:, settings:)`: appends a planned copy of the last set's load,
  unit and reps, or a default row when there are no sets.
- `deleteSet(setId:)`: renumbers positions 0…n-1.
- `addExercise(workoutId:, exerciseId:, settings:)`: appends with `restSeconds` = the
  exercise's default and no targets, then prefills.
- `swapExercise(workoutExerciseId:, to exerciseId:, alsoInProgram: Bool, settings:)`:
  - Throws `swapAfterLogging` if any set of it is completed.
  - Otherwise deletes its planned sets, sets the new `exerciseId` and prefills again.
  - With `alsoInProgram` and a `dayExerciseId`, also points that day item at the new
    exercise.
- `removeExercise(workoutExerciseId:)`: renumbers.
- `moveExercise(workoutId:, from:, to:)`: renumbers.
- `adjustRest(workoutId:, by seconds: Double, now:)`:
  - No-op when `restEndsAt` is nil.
  - If the new end ≤ `now`, clears both rest fields.
  - Otherwise moves `restEndsAt` and adds `seconds` to the duration.
- `clearRest(workoutId:)`.
- `finish(workoutId:, now:) -> WorkoutRecord?`:
  1. Delete every planned set.
  2. Delete workout exercises with no sets.
  3. Renumber the remaining exercises and sets.
  4. If nothing remains, delete the workout and return nil (rulebook §10: a workout with
     nothing logged is discarded silently).
  5. Otherwise set `endedAt = now`, clear rest, and return the workout.
- `discard(workoutId:)`: deletes it; the rows below cascade.
- `setNoteAndEffort(workoutId:, note: String?, effort: Int?)`.

**Tests** (`WorkoutEngineTests`, with `TestData` from card 1.2):

- **Prefill from the same day.** A day item bench (targetSets 3) whose last finished
  workout on the same day had 20×10, 50×10, 40×10 gets three planned sets with exactly
  those values, all with `completedAt == nil`.
- **`lastTimeSource = .anyWorkout`.** A newer session of bench on another day is used
  instead.
- **Padding.** Last time 2 sets and target 3 gives a third set copying the second.
- **No history.**
  - Target 3, repMin 8 gives three sets of load 0 × 8.
  - A `repsOnly` exercise gets loads of nil.
- **One workout at a time.** A second `start` throws `alreadyInProgress`.
- **Logging and rest.**
  - `logSet` at t gives `completedAt == t` and `restEndsAt == t + 90` for rest 90.
  - `adjustRest(-100)` with 90 s left clears rest.
- **Finishing.**
  - Finishing with one of three sets logged leaves exactly one set.
  - Finishing with nothing logged returns nil and leaves no workout row.
- **Swapping.**
  - Swapping after logging throws `swapAfterLogging`.
  - Swapping before logging prefills from the new exercise's history.
  - `alsoInProgram` updates the day item's `exerciseId`.
- **History visibility.** A finished workout appears in `ExerciseQueries.sessions`; an
  in-progress one does not.

**Done when:** tests pass.

**Out of scope:** UI; notifications.

---

## Card 2.2: Active workout model and resume

**Files:** create `GymApp/Features/Workout/ActiveWorkoutModel.swift`. Change
`GymApp/App/RootView.swift`, and `GymApp/App/AppEnvironment.swift` (add the model to the
environment). Move `GymApp/Services/RestNotifier.swift` unchanged; it is reused.

**Steps:**

1. Create the model, one instance for the app, made in `GymAppApp` and injected with
   `.environment(model)`:

   ```swift
   @Observable final class ActiveWorkoutModel {
       private(set) var snapshot: WorkoutSnapshot?
       var currentItemId: String?          // the card that is open
       var selectedSetId: String?          // the row the editor and Log button act on
       var focusMode = false
       var isPresented = false             // full-screen workout showing
       private(set) var justFinishedWorkoutId: String?
       init(db: AppDatabase)
       func resumeIfNeeded() async         // at launch: load the in-progress workout, if any
       func start(dayId: String?) async throws
       func log(_ setId: String) async
       // …one async method per WorkoutWrites operation, plus:
       func restDidEnd() async             // countdown hit zero with the app open
       func finish() async                 // sets justFinishedWorkoutId, clears snapshot
       func discard() async
   }
   ```

2. **After every write**, reload the snapshot, then update notifications through
   `RestNotifier`:
   - when `restEndsAt` is set, schedule the alert at that time; the body is the next planned
     set, "Next: <exercise>, set N — 50 kg × 10", searching from the current item onward
     and wrapping round;
   - when it is nil, cancel the alert.

   Request notification permission on the first `start`.
3. **Current item and selection.**
   - After `start`, the current item is the first with a planned set, and the selected set
     is its first planned set.
   - After `log`, the selection moves to the next planned set of the same item.
   - When the item has none left, `currentItemId` advances to the next item with planned
     sets, and the selection follows.
   - Tapping a card or a row overrides both.
4. **Errors** surface as `lastError: String?`, shown as an alert by the screen. Present
   `alreadyInProgress` as "Finish or discard the workout in progress first."
5. `RootView` calls `resumeIfNeeded()` in `.task`.

**Done when:**
- Unit tests pass. Add `ActiveWorkoutModelTests` with an in-memory database, covering
  selection advancing across items and the notification body text. Inject a fake notifier
  through a small `protocol RestScheduling` that `RestNotifier` conforms to.
- Killing the app mid-workout and relaunching restores the workout, with its rest countdown
  still correct.

---

## Card 2.3: Workout screen, list mode

**Files:** create `GymApp/Features/Workout/WorkoutView.swift`,
`GymApp/Features/Workout/ExerciseCard.swift`, `GymApp/Features/Workout/SetRow.swift` and
`GymApp/Features/Workout/SetEditor.swift`.

**Layout** (presented full screen when `model.isPresented`):

- **Header:**
  - a minimise button (`chevron.down`) sets `isPresented = false`;
  - the title and elapsed time (`Text(startedAt, style: .timer)`);
  - a ring showing `completedSetCount / totalSetCount`;
  - a focus toggle (`scope`);
  - a menu with Add exercise and Discard workout;
  - "Finish".
- **Body:** a `ScrollViewReader` with a `LazyVStack` of `ExerciseCard`, one per item. When
  `currentItemId` changes, scroll it into view.
- **`ExerciseCard`, collapsed** (not current): the name, "2/3" with a tick when all its sets
  are completed, and the previous session as "Previous: 20×10 · 50×10". Tapping makes it
  current.
- **`ExerciseCard`, expanded** (current):
  - **Title row:** the name, `MuscleTags`, and a `…` menu: Swap exercise, History,
    Plate calculator (barbell, ezBar and smith only), Remove.
  - **Sticky note**, when present. Tapping it edits it, saving through `ExerciseWrites`.
  - **Today chip:** "Target 3 × 8–12 · Previous 7 Oct (same day)", or "(another day)", or
    "No history yet".
  - **Column header:**
    - `SET`;
    - `PREVIOUS`;
    - the load column, labelled by the unit, `+KG` for `bodyweightPlus`, and hidden for
      `repsOnly`;
    - `REPS`;
    - a tick column.
  - **`SetRow` per set:**
    - **Label:** `W` for warm-up, `D` for drop, otherwise the working-set number (warm-ups
      don't take a number). `F` is shown as a small red badge beside the number.
    - **Previous:** the previous session's set at the same position, as "50×10".
    - **Load and reps:** `.secondary` while planned, `.primary` once completed.
    - **Tick:** a 44 pt circle that fills with `Theme.accent` and shows a checkmark when
      completed. Tapping it toggles log and unlog.
    - **Comparison:** completed rows with a previous value show ↑ (`Theme.accent`),
      ↓ (orange) or = (secondary). Compare by `TrainingMath.e1RM`, or by raw load for
      `bodyweightPlus`.
    - **Gestures:** a context menu sets the type; a swipe deletes.
  - **`SetEditor`** appears directly under the selected row:
    - two steppers, load (± `equipment.stepKg`, converted to lb when the unit is lb: 5 lb
      for dumbbells, otherwise 5) and reps (±1);
    - each value is tappable to type (an alert with a text field, accepting `,` or `.`);
    - buttons repeat on long press (`.buttonRepeatBehavior(.enabled)`);
    - a unit toggle (kg/lb) sets the row's unit **without converting the number**
      (rulebook §1: loads are stored as entered).
  - **"+ Add set".**
- **Footer:** a "+ Add exercise" button, then space for the bottom bar (card 2.5).

**Done when:** on the simulator, starting Full Body 1:
- shows all exercises, with the first card open and its rows prefilled from 7 Oct;
- logging moves selection down the rows, then to the next card, which scrolls into view;
- a planned row stays grey until ticked;
- a lb unit toggle keeps the number.

Screenshots.

---

## Card 2.4: Focus mode

**Files:** create `GymApp/Features/Workout/FocusView.swift`.

**Steps:** when `model.focusMode`, `WorkoutView` shows `FocusView` in place of the list
(same header and bottom bar):

- The current exercise name (`.largeTitle.bold()`) and "Set N of M".
- Two large stepper panels for load and reps, with numbers at 56 pt rounded monospaced. The
  same tap-to-type and repeat behaviour as `SetEditor`.
- The lines "Previous 50×10 · Target 8–12", and the sticky note if any.
- "Done" lists this exercise's completed sets with their ↑/↓/= marks.
- An "Up next" strip at the bottom shows the next item's name and previous summary. Tapping
  it moves to that exercise.
- Swiping left or right on the panel moves to the next or previous item.

**Done when:** toggling between list and focus keeps the same selection, and logging in focus
mode advances exactly as in list mode.

---

## Card 2.5: Bottom bar and rest

**Files:** create `GymApp/Features/Workout/WorkoutBottomBar.swift` and
`GymApp/Features/Workout/RestRing.swift`.

**Steps:**

1. **Resting** (`restEndsAt` is set):
   - `RestRing` is a circular track with `Theme.accent` progress (remaining / duration) and
     the remaining time `m:ss` inside;
   - −15 s and +15 s buttons, and Skip;
   - recompute every 0.25 s with `TimelineView`, from `restEndsAt` (rulebook §9), never by
     decrementing.
2. **Not resting:**
   - "Log set N · 50 kg × 10" (`PrimaryButtonStyle`) for the selected set;
   - when the current item has no planned sets, "Next: <exercise>";
   - when nothing is planned anywhere, "Finish workout".
3. `.task(id: restEndsAt)` sleeps until the end, then calls `model.restDidEnd()` and plays
   `.sensoryFeedback(.warning, …)`. Logging a set plays `.success`.

**Done when:**
- On the simulator: log a set, press −15 s three times, then send the app home; the
  "Rest over" notification is delivered while the app is suspended. Confirm in the log:

  ```bash
  xcrun simctl spawn "iPhone 17 Pro Max" log show --last 2m --style compact \
    --predicate 'process == "SpringBoard" AND eventMessage CONTAINS "rest-timer"'
  ```
- Returning to the app shows no stale rest bar.

---

## Card 2.6: Start, mini-player and navigation

**Files:** create `GymApp/Features/Workout/MiniPlayer.swift`. Change `RootView.swift` and
`TrainView.swift`.

**Steps:**

1. **Start.**
   - Enable Train's "Start <day>" button: `try await model.start(dayId:)`, then
     `model.isPresented = true`.
   - Add a toolbar item "Empty workout" that starts with `dayId: nil`.
   - Remove the phase 1 caption.
2. **Full-screen presentation.** In `RootView`:
   - `.fullScreenCover(isPresented: $model.isPresented)` shows `WorkoutView`;
   - after `finish()`, the same cover shows the summary (card 2.8) until Done.
3. **Mini-player.**
   - Attach it with `.tabViewBottomAccessory(isEnabled: model.snapshot != nil) { MiniPlayer() }`
     on the `TabView` (iOS 26 SDK, already checked).
   - It shows:
     - the workout title;
     - the current exercise;
     - either the rest countdown (`Theme.accent`) or the elapsed time;
     - a compact "Log" button for the selected set.
   - Read `@Environment(\.tabViewBottomAccessoryPlacement)`: when it is `.inline` (tab bar
     minimised), show only the countdown or elapsed time and the exercise name.
   - Tapping it sets `isPresented = true`.
4. While a workout is in progress, Train's Start buttons read "Resume <title>".

**Done when:** on the simulator:
- start, then minimise: the mini-player shows above the tab bar on every tab;
- the rest countdown is visible in it;
- tapping it reopens the workout;
- after finishing, the mini-player disappears.

Screenshots.

---

## Card 2.7: Swap, add, history and plate calculator

**Files:**

- create `GymApp/Features/Workout/SwapExerciseView.swift`,
  `GymApp/Features/Workout/ExerciseHistorySheet.swift` and
  `GymApp/Features/Workout/PlateCalculatorView.swift`
- create `GymApp/Domain/PlateMath.swift` and `GymAppTests/PlateMathTests.swift`

**Steps:**

1. **Swap.**
   - The picker from card 1.8, pre-filtered to the current exercise's `movementPattern` (a
     chip "Same movement", on by default).
   - A toggle: "Also change it in <day name>".
   - It calls `swapExercise`; after a set is logged the menu item is disabled, with the
     caption "Swap before logging; add an exercise instead".
2. **Add exercise.** The picker from card 1.8, with no focus filter; it calls `addExercise`.
3. **History sheet.** The History section of `ExerciseDetailView` (card 1.4) for this
   exercise, in a `.medium`/`.large` sheet.
4. **`PlateMath`.**

   ```swift
   nonisolated enum PlateMath {
       struct Result: Equatable { var perSide: [Double]; var achieved: Double; var shortBy: Double }
       static func plates(target: Double, bar: Double, available: [Double]) -> Result?
   }
   ```

   - Returns nil when `target < bar`.
   - `perSide` is greedy from the largest plate (unlimited pairs of each) for
     `(target − bar) / 2`.
   - `achieved = bar + 2 × Σ perSide`; `shortBy = target − achieved`, 0 when exact.
   - **Defaults:**
     - kg plates `[25, 20, 15, 10, 5, 2.5, 1.25]`, bars barbell 20, ezBar 10, smith 0;
     - lb plates `[45, 35, 25, 10, 5, 2.5]`, bars 45, 25, 0.

   Add `platesKg` and `platesLb` to `AppSettings`, as comma-separated strings.
5. **Plate calculator.** A sheet showing the selected set's load: the plates per side as
   coloured rounded rectangles sized by weight, "Bar 20 kg", and when short, "Closest:
   62.5 kg (0.5 kg short)".

**Tests:**

- `plates(target: 100, bar: 20, kg)` → per side [25, 15], achieved 100, short 0.
- `62.5` → [20, 1.25].
- `63` → [20, 1.25], achieved 62.5, short 0.5.
- `20` → [], achieved 20.
- `15` → nil.
- `225` lb with bar 45 → [45, 45].

**Done when:** tests pass; the swap appears in the program when the toggle is on; the
history sheet opens over the workout.

---

## Card 2.8: Summary

**Files:** create `GymApp/Features/Workout/SummaryView.swift`,
`GymApp/Data/SummaryQueries.swift`, `GymApp/Data/BodyQueries.swift` and
`GymAppTests/SummaryTests.swift`.

**Rules:**

- `BodyQueries.weightKg(_ db, onOrBefore date: Date) -> Double?`: the latest body entry with
  `date ≤` that day that has a weight, converted to kg. Used for `bodyweightPlus` volume
  (rulebook §2).
- `SummaryQueries.summary(_ db, workoutId:) -> WorkoutSummary`:
  - `duration` = `endedAt − startedAt`.
  - `volumeKg` = Σ `TrainingMath.volumeKg` per exercise. Each set's kg is
    `loadHundredths / 100`, converted from lb when needed.
  - `previousVolumeKg`: the same, for the last finished workout before this one whose
    `programDayId` is in this workout's day lineage. nil if none.
  - `records`: per exercise, compare `TrainingMath.bests` of this workout's sets with the
    bests of all its finished sets before this workout started. Report "Heaviest" when
    `heaviestKg` is strictly greater, and "Best est. 1RM" when `bestE1RM` is greater by more
    than 0.01. Report nothing when there was no prior history.
  - `muscles`: hard sets per muscle (rulebook §6), sorted by count descending:
    - every completed set that is neither `.warmUp` nor `.drop` adds 1 to each primary
      muscle and 0.5 to each secondary;
    - a `.drop` row is part of the set before it (rulebook §3).

**Layout:**
- "Workout complete", then the title and date.
- A 2×2 grid: Duration, Volume (with "last time X kg" under it), Sets, Records.
- A records list (trophy icon, exercise, kind, "60 kg, was 57.5 kg").
- Muscles trained, as `MuscleTags` with counts.
- Each exercise with its sets and estimated 1RMs.
- An effort picker (1–10, optional) and a note field. Done saves them through
  `setNoteAndEffort` and dismisses.

**Tests:**

- With body weight 90 kg recorded before the workout:
  - an assisted pull-up −45×6 and a bench press 60×8 give volume 270 + 480 = 750;
  - prior bench best of 57.5×8 gives records [Heaviest 60 (was 57.5), Best est. 1RM 76.0
    (was 72.83)].
- Muscles for 2 bench sets (primary chest; secondary triceps and shoulders) give chest 2,
  triceps 1, shoulders 1.
- A workout with no earlier workout on its day lineage has `previousVolumeKg == nil`.

**Done when:** tests pass, and the summary after a simulator session shows the right counts.

---

## Card 2.9: Lock-screen countdown (Live Activity)

**Needs a new Xcode target, which is a project-file change.** Do this card last in the
phase. The rest alert already works without it (decision #5).

**Before the card:** in Xcode, File → New → Target → **Widget Extension**:
- name `GymAppWidgets`;
- tick **Include Live Activity**;
- untick **Include Configuration App Intent**;
- embed in GymApp.

Build once to confirm the template compiles. Commit that on its own: "Add the widget
extension target".

**Steps:**

1. Create a shared file in **both** targets (Target Membership: GymApp and GymAppWidgets),
   `RestActivityAttributes.swift`:
   - `struct RestActivityAttributes: ActivityAttributes` with `workoutTitle: String`;
   - its `ContentState` has `exerciseName: String`, `restEndsAt: Date`, `nextSetText: String`.
2. Replace the template's Live Activity UI:
   - **Lock screen:** the exercise name, the countdown with
     `Text(timerInterval: Date.now...restEndsAt, countsDown: true)`, and `nextSetText`.
   - **Dynamic Island compact:** a timer icon (leading) and the countdown (trailing).
   - **Minimal:** the countdown.
   - **Expanded:** all three.
   - Tint with the volt accent.
3. Add `INFOPLIST_KEY_NSSupportsLiveActivities = YES` to the GymApp target's build settings,
   Debug and Release.
4. In `ActiveWorkoutModel`:
   - start an activity when rest starts;
   - update it on adjust;
   - end it on skip, on rest end and on finish or discard.

   Ignore errors from `Activity.request`, but log them. A free Apple ID may not permit Live
   Activities on a device; that is checked in phase 5.

**Done when:** on the simulator, the lock screen (Device → Lock) shows the countdown during
rest, and it disappears when rest ends.

---

## Card 2.10: Remove the prototype and close the phase

1. Delete `GymApp/Prototype/` and `tools/make_prototype_seed.py`. Remove the
   `PrototypeSeed.json` line from `.gitignore`, the Settings link, and anything still
   referencing `ProtoEquipment`.
2. Log one full session of your real Full Body day on the simulator, end to end. Take
   screenshots of the list, focus mode, rest and the summary.
3. Update README.md:
   - phase 2 **done**;
   - "What exists today" rewritten;
   - Build: drop the seed paragraph.
4. Tick phase 2 in ROADMAP.md, and record learnings in HANDOFF.md.
5. **Stop.** Phase 3 is specified in full, in a separate planning session, before any of it
   is built. [03-05-outline.md](03-05-outline.md) is the starting point. Record in
   HANDOFF.md that phase 2 is closed and phase 3 is waiting for its spec.
