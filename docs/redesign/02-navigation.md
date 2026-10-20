# Redesign step 2: navigation map

On 20 October 2026, we read the map from the code (each NavigationLink, sheet and cover) and
checked it in the simulator. The tap counts start with the app open on Train. "+ n" means the
steppers or typing.

## The map today

```
Tab bar ─┬─ Train ──┬─ Next day card ─ Start / Resume ──────────────► Workout (full screen)
         │          ├─ Next day card (tap) ─► Day ─┬─ row ─► Targets sheet (sets, reps, rest, note)
         │          │                              ├─ Edit ─► reorder / delete rows
         │          │                              ├─ ⋯ ─► Copy from another day
         │          │                              └─ Add exercises ─► Exercise picker
         │          ├─ Other days ─► Day (as above)
         │          ├─ Programs ─► Programs ─► Program ─► Day
         │          ├─ + ─► New program / Empty workout
         │          ├─ Studio suggestions ─► accept / dismiss
         │          └─ Mini player ─► Workout
         │
         ├─ History ─┬─ Calendar day / week row ─► Past workout (edit sets, delete)
         │           └─ Recaps icon ─► Recaps ─► Month / Year
         │
         ├─ Exercises ─┬─ row ─► Exercise page ─┬─ Progress (chart point ─► Past workout, record ─► Past workout)
         │             │                         ├─ History / Notes / About
         │             │                         ├─ Form cue ─► Cue editor sheet
         │             │                         └─ ⋯ ─► Edit / Duplicate / Archive
         │             └─ + ─► New exercise
         │
         ├─ Progress ─┬─ record row ─► Past workout
         │            └─ Reports icon ─► Reports ─► Report
         │
         └─ Settings ─┬─ Backups & recovery ─► Recovery
                      └─ Import / Export

Workout (full screen) ─┬─ card ⋯ ─► Swap sheet / History sheet / Plate calculator / Warm-ups / Superset / Remove
                       ├─ Best tile ─► Beat table
                       ├─ Focus toggle, Add exercise, ⋯ (discard)
                       └─ Finish ─► confirm ─► End of workout ─► Past workout
Lock screen ─ Log (rest Live Activity)
```

## The ten most frequent tasks

We selected these tasks from the owner's history (17 sets and 5 exercises in a session, about
4 sessions in a week) and from the core jobs in [CORE_JOBS.md](../CORE_JOBS.md). The usage
counts from step 1 will replace this selection with real numbers.

| # | Task | Path today | Taps today | Target |
|---|---|---|---|---|
| 1 | Start the next workout | Train → Start | 1 | 1 |
| 2 | Log the prefilled set | Log | 1 | 1 (0 from the lock screen: Log there) |
| 3 | Change load or reps, then log | ± (n) → Log | 1 + n | 1 + n, with the controls in thumb reach |
| 4 | See what to beat | On the card, below the set | 0 (a scroll on small phones) | 0, never a scroll |
| 5 | Change or skip the rest | Rest bar | 1 | 1 |
| 6 | See the history of a lift during a workout | Card ⋯ → History | 2 | 1 (tap the exercise name) |
| 7 | Swap an exercise during a workout | Card ⋯ → Swap → select | 3 + search | 2 + search |
| 8 | Finish | Finish → confirm | 2 | 2 |
| 9 | See an exercise of today's plan before training | Not possible from the day; Exercises → search → row | 2 + typing | 2 (Train → row) |
| 10 | Weekly review | Progress, then about five screens of scroll; Reports through a small icon | 1 + scroll | 1: one screen with drill-downs |

Changes to the plan are less frequent. But they are the reason for this step:

| Task | Path today | Taps today | Target |
|---|---|---|---|
| Change the targets of a day | Train → day → row → edit → Save | 4 + n | 3 + n |
| Reorder a day | Train → day → Edit → drag → Done | 4 | 2 (drag in place) |
| Swap an exercise in the plan | No swap; Edit → delete → Add exercises → select → drag into place | 6 or more | 3 (row → Swap → select) |
| Open the page, history or cues of an exercise in a day | Not possible | — | 2 |

## The gaps, in order of priority

1. **Day rows go nowhere useful.** A row must open the exercise as it is in the plan: its page
   (demonstration, cues, progress, history), with the day's targets at the top, and Swap and
   Remove next to them.
2. **Train's next-day list does not respond to a tap.** Each exercise in the "Next up" card must
   open the same page.
3. **The plan has no swap.** A workout has Swap ("also in the program"), but a day does not.
4. **Reorder needs Edit mode.** You must be able to drag rows in place. Swipe actions are for
   rare changes.
5. **During a workout, history is two taps away, in a menu.** The exercise name on the card must
   open the exercise page as a sheet.
6. **Recaps and Reports are behind icons.** They must be visible rows in History and Progress.

## Proposed fix for gaps 1–4 (this is code, so it needs approval)

- `DayEditorView` rows become NavigationLinks to the exercise page in the "plan" context:
  ExerciseDetailView with a header block for the day's targets. The block has the fields of the
  current sheet (sets, reps, rest, note), and you edit them in place. Swap and Remove buttons
  are in the block.
- Swap uses the swap picker of the workout and `ProgramWrites`. Reorder uses `.onMove` with no
  EditButton. Remove is a swipe action.
- Train's next-day rows open the same page.
- UI tests: open a day, open an exercise, see its cues and history, swap it, reorder. The tests
  check the tap counts above.
