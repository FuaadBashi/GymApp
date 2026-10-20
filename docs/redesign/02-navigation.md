# Redesign step 2: navigation map

Read from the code on 20 October 2026 (every NavigationLink, sheet and cover) and checked
in the simulator. Taps are counted from the app opening on Train; "+n" means steppers or
typing on top.

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

## The ten most common tasks

Chosen from the owner's history (17 sets and 5 exercises a session, about 4 sessions a week)
and the core jobs in [CORE_JOBS.md](../CORE_JOBS.md). The usage counts proposed in step 1 will
replace this judgement with real numbers.

| # | Task | Path today | Taps today | Target |
|---|---|---|---|---|
| 1 | Start the next workout | Train → Start | 1 | 1 |
| 2 | Log the prefilled set | Log | 1 | 1 (0 from the lock screen: Log there) |
| 3 | Change load or reps, then log | ± (n) → Log | 1 + n | 1 + n, controls in the thumb zone |
| 4 | See what to beat | On the card, under the set | 0 (scroll on small phones) | 0, never scrolled |
| 5 | Adjust or skip rest | Rest bar | 1 | 1 |
| 6 | Look at a lift's history mid-workout | Card ⋯ → History | 2 | 1 (tap the exercise name) |
| 7 | Swap an exercise mid-workout | Card ⋯ → Swap → pick | 3 + search | 2 + search |
| 8 | Finish | Finish → confirm | 2 | 2 |
| 9 | See an exercise of today's plan before training | Not possible from the day; Exercises → search → row | 2 + typing | 2 (Train → row) |
| 10 | Weekly review | Progress, then about five screens of scrolling; Reports via a small icon | 1 + scroll | 1, one screen with drill-downs |

Plan edits, less frequent but the complaint behind this step:

| Task | Path today | Taps today | Target |
|---|---|---|---|
| Change a day's targets | Train → day → row → edit → Save | 4 + n | 3 + n |
| Reorder a day | Train → day → Edit → drag → Done | 4 | 2 (drag in place) |
| Swap an exercise in the plan | No swap; Edit → delete → Add exercises → pick → drag into place | 6+ | 3 (row → Swap → pick) |
| Open a day's exercise page, history or cues | Not possible | — | 2 |

## The gaps, in order

1. **Day rows lead nowhere useful.** A row should open the exercise as it sits in the plan: its
   page (demonstration, cues, progress, history) with the day's targets at the top, and Swap
   and Remove beside them.
2. **Train's next-day list is not tappable.** Each exercise in the "Next up" card should open
   the same page.
3. **No swap in the plan.** Swap exists in a workout ("also in the program") but not in the day.
4. **Reorder needs Edit mode.** Rows should drag in place, with swipe actions for rare edits.
5. **Mid-workout history is two taps behind a menu.** The exercise name on the card should
   open its page as a sheet.
6. **Recaps and Reports hide behind icons.** They belong as visible entries in History and
   Progress.

## Proposed fix for gaps 1–4 (needs approval: it is code)

- `DayEditorView` rows become NavigationLinks to an exercise page in "plan" context:
  ExerciseDetailView with a header block for the day's targets (sets, reps, rest, note; the
  current sheet's fields, edited in place) and buttons Swap, Remove.
- Swap reuses the workout's swap picker and `ProgramWrites`; reorder uses `.onMove` without
  EditButton; Remove is a swipe action.
- Train's next-day rows link to the same page.
- UI tests: open a day → open an exercise → see cues and history → swap it → reorder, with the
  tap counts above asserted.
