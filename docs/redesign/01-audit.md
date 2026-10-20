# Redesign step 1: inventory and audit

On 20 October 2026, we captured each screen in the simulator. The simulator had a copy of the
owner's data (471 workouts) and a workout in progress. Each screen is in
[screens/](screens/). The sheet below shows the phone screens side by side. The studio pages
are in screens/10.7-studio-*.jpg.

![Every phone screen](inventory-phone.png)

## The marks

- **Must:** you need it at that moment. It must be visible with no tap and no scroll.
- **Glance:** it is useful there. It can be smaller or closed, one tap away.
- **Rare:** you use it sometimes. Put it in a menu, a disclosure or another screen.

## Screens

| Screen | File | Purpose |
|---|---|---|
| Train | train.png | Start or resume the next day; see the other days |
| Day | train-day.png, train-day-item-sheet.png, train-day-menu.png | The exercises and targets of a program day |
| Programs | train-programs.png | Active and archived programs |
| Workout, list | workout-list.png | Log sets, one exercise after the other |
| Workout, resting | workout-rest.png | The same, with the rest bar |
| Workout, focus | workout-focus.png | One exercise, large controls |
| End of workout | workout-summary.png | Summary, comparisons, records |
| Lock screen | lock-screen-rest.png | Rest countdown and Log button |
| History | history.png | Calendar and weeks |
| Past workout | history-workout.png | One workout; you can edit it |
| Recaps | history-recap.png | Months and years |
| Exercises | exercises.png | Library with filters |
| Exercise page | exercise-top.png, exercise-progress.png | Demonstration, cues, progress, records |
| Progress | progress.png, progress-2.png, progress-3.png | 12-week charts, muscles, recovery, trends, records, body |
| Reports | progress-reports.png | The studio's weekly and monthly reports |
| Settings | settings.png, settings-2.png | Units, profile, defaults, Health, data |

## Element audit

### Train (you open it before each session)

| Element | Mark | Note |
|---|---|---|
| Next day name, and Start or Resume | Must | The one action on this screen. Good. |
| The next day's exercises, with last time | Glance | Useful. Today the list does not respond to a tap. |
| Estimated time, date last done | Glance | |
| Other days | Glance | Each one opens a day. |
| Programs button, + (new program, empty workout) | Rare | In the top bar. Good. |
| Studio suggestions | Glance | Only when there are suggestions. |
| Mini player (workout in progress) | Must | Good. On Train it repeats the Resume button. |

### Day

| Element | Mark | Note |
|---|---|---|
| Exercise rows: targets, rest, last time | Glance | |
| Tap on a row | — | Opens sets, reps, rest and note only. **You cannot open the exercise's page, history or cues, and you cannot swap the exercise.** |
| Edit (reorder, remove), ⋯ (copy from another day) | Rare | Reorder is behind Edit. Swap is not available. |

### Workout, current exercise card (between sets, one hand)

Today, the card shows these items from the top down:

1. Name and muscle.
2. Sticky note.
3. Today's suggestion.
4. Demonstration (a video, about a quarter of the screen) and its credit lines.
5. "Add a note for this workout".
6. Target line, then the set table.
7. Set type and notes.
8. This set's estimated 1RM, then the best tiles.
9. Steppers, then the reps-in-reserve chips.
10. The other sets, then Add set.

The floating Log/Rest bar is at the bottom.

| Element | Mark | Note |
|---|---|---|
| Selected set: load × reps, steppers | Must | **Starts about 60% down the screen** on a 6.9" phone. On a smaller phone it is below the fold. |
| Log button, rest countdown | Must | A floating bar. Good. |
| What to beat (best tiles) | Must | Visible since 19 October. The rest bar can cover its lower half. |
| Last time (LAST column) | Glance | Correct size since 19 October. |
| Today's suggestion | Glance | A full-width box above the demonstration. |
| Sticky note | Glance | Often long. It moves all items down. |
| Form cues | Glance | Only when you selected them. |
| Demonstration video and credits | Rare during a workout | **The largest item on the card, and above the sets.** |
| Workout note, set type, notes and labels, reps in reserve | Rare | Each one is a full-width line. |
| Card ⋯ menu: swap, history, warm-ups, superset, plate calculator, remove | Rare | Good as a menu. |
| Other exercises (closed cards) | Glance | Below the current card. You must scroll far to see them. |

### Workout, focus mode

Focus mode has a better order than the list: name, "Set 1 of 3", suggestion, this set's
estimated 1RM, best, steppers, reps in reserve, then the demonstration. Its Log action is the
floating bar. Focus mode needs no change. The list must use the same order.

### End of workout, History, past workout, recaps

| Element | Mark | Note |
|---|---|---|
| Summary: duration, volume, sets, records | Glance | The past workout shows them as **four equal tiles** (DESIGN.md, tell 3). |
| Records list, the sets of each exercise with estimated 1RM | Glance | |
| Calendar | Glance | Good. |
| List of weeks | Glance | Good. |
| Recaps | Rare | Behind a small icon at the top right. |

### Exercises and the exercise page

| Element | Mark | Note |
|---|---|---|
| Search, filter chips, rows with the last set | Must | Good. |
| Demonstration, cues | Glance | First on the page since card 10.6. |
| Best estimated 1RM, chart, records | Glance | |
| History, Notes, About segments | Rare | |

### Progress

| Element | Mark | Note |
|---|---|---|
| This week against last week: volume, sessions, time | Glance | Three similar bar charts, one above the other. |
| Muscles this week (body map, sets per muscle) | Glance | |
| Recovery, last 72 h | Glance | A second body map. |
| Movement-pattern trends, recent records | Glance | |
| Body weight, steps | Rare | |
| Reports | Rare | A small icon at the top right. |

Progress is one long scroll of about five screens, with two body maps. This is the page with
"too much at the same time".

### Settings

Units, profile, calendar, defaults for new exercises, the source of last-time values, Apple
Health, backups, import and export. All items are rare. The layout is good.

### Lock screen

Rest countdown, next set and Log. Must. Good.

### GymApp Studio (Mac)

Card 10.7 gave the studio a sidebar, a toolbar, ⌘K and an overview hero. The studio uses the
phone's colours. It does not use the phone's type scale, spacing or components yet, because the
two apps have no shared source.

## Summary of the audit

1. **Train → day → exercise is a dead end.** The day lists its exercises, but a tap only edits
   the targets. From a plan you cannot open the exercise page, history or cues, and you cannot
   swap the exercise.
2. **The workout card puts rare items above necessary items.** The demonstration, its
   credits, the sticky note and the workout note are above the set that you will lift.
3. **Progress is one long page.** All items have the same weight.
4. **Grids of equal tiles remain** on the past-workout summary.
5. **Small icons in the top bar hide useful screens** (Recaps, Reports).
6. **The two apps share their colours by hand,** not from one definition.

## Open items for this step

- **The session recording.** We wait for the owner's screen recording. Then we add each
  hesitation and each wrong tap here.
- **Usage counts on the device.** This is code, so it needs approval. The app counts each
  screen that you open and each button that you tap. It keeps the counts in its database and
  never sends them. A "Usage" line in Settings → Data exports the counts as CSV. Proposed
  table: `usageCount(key TEXT PRIMARY KEY, count INTEGER, lastAt TEXT)`, with keys such as
  `screen.workout`, `tap.log` and `tap.bestTile`. About 30 lines and one test.
