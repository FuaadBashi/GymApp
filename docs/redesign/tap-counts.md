# Tap counts

`GymAppUITests/TapCountUITests` does each task on the in-memory UI-test fixture (one program
day of two lifts, a workout in progress when the task needs one). It counts each tap and each
scroll. Card R.10 runs the tests again after the redesign.

## Before the redesign (20 October 2026, card R.1)

| # | Task | Taps before | Target (02-navigation.md) |
|---|---|---|---|
| 1 | Start the next workout | 1 | 1 |
| 2 | Log the prefilled set | 1 | 1 (0 from the lock screen) |
| 3 | Change the load by one step, then log | 2 | 2, with the controls in thumb reach |
| 4 | See what to beat | 0 | 0 |
| 5 | Skip the rest | 1 | 1 |
| 6 | See the history of a lift during a workout | 2 | 1 |
| 7 | Swap an exercise during a workout | 3 | 2 |
| 8 | Finish | 2 | 2 |
| 9 | Open an exercise of today's plan | 2, through the Exercises tab (not possible from the day) | 2, from Train |
| 10 | Weekly review | 1 tap + 2 scrolls = 3 | 1, on one screen |
| — | Change a day's targets (+1 set) | 4 | 3 |
| — | Reorder a day | 4 | 2 |
| — | Swap an exercise in the plan | Not possible | 3 |

Notes:

- Task 10 uses the fixture's small history. With the owner's history, Progress is about five
  screens long (01-audit.md), so the real number of scrolls is larger.
- Task 9 has no direct route before the redesign. The count is for the Exercises tab, with the
  exercise visible in the list without a search.

## After the redesign (21 October 2026, card R.10)

| # | Task | Before | After | Target | Met |
|---|---|---|---|---|---|
| 1 | Start the next workout | 1 | 1 | 1 | Yes |
| 2 | Log the prefilled set | 1 | 1 | 1 | Yes (0 from the lock screen) |
| 3 | Change the load by one step, then log | 2 | 2 | 2 | Yes |
| 4 | See what to beat | 0 | 0 | 0 | Yes, now above the fold |
| 5 | Skip the rest | 1 | 1 | 1 | Yes |
| 6 | The page and history of a lift during a workout | 2 | 1 | 1 | Yes (tap the name) |
| 7 | Swap an exercise during a workout | 3 | 3 | 2 | No: still card ⋯ → Swap → select |
| 8 | Finish | 2 | 2 | 2 | Yes |
| 9 | Open an exercise of today's plan | 2, through Exercises | 1, from Train | 2 | Yes |
| 10 | Weekly review | 1 tap + 2 scrolls | 1 tap + 1 scroll | 1 | Better; one short scroll remains |
| — | Change a day's targets | 4 | 2 | 3 | Yes |
| — | Reorder a day | 4 | 4 | 2 | No: SwiftUI list reorder needs Edit mode |
| — | Swap an exercise in the plan | Not possible | 3 | 3 | Yes |

## A bug that the counts found

A row in a day answered a tap only on its text, not on the empty space in the row. A tap in the
middle of the row did nothing. This is one cause of the "clunky" feel. Fixed on 20 October:
the full row now answers a tap (`.contentShape(.rect)` in `DayEditorView.itemRow`). The test
taps the middle of the row, so the bug cannot come back without a failed test.
