# Product brief

A private, offline training log for one person on one iPhone. It keeps what JEFIT does well:
exercises and how they are categorised, programs, set logging, summaries, the calendar, the
muscle view and the analytics. Everything else is dropped.

Written 11 October 2026, revised the same day after the first prototype. Decisions behind it
are in [DECISIONS.md](DECISIONS.md), the build order is in [ROADMAP.md](ROADMAP.md), and
every number the app shows is defined in [TRAINING_RULEBOOK.md](TRAINING_RULEBOOK.md).

## Who it is for

One lifter. What the design has to fit:

- Trains three times a week, full body, on **three separate full-body days**. Two exist in
  JEFIT (1FBD 1 with 6 exercises, 2FBD 2 with 10); the third gets built in this app. Sessions
  run 15–40 minutes, with one to three working sets per exercise. Mostly machines, plus
  barbell squat and bench and dumbbell rows.
- Changes programs: adds, removes and swaps exercises, and has run 5/3/1 and upper/lower
  before. The app has to make building and editing a program easy.
- Has four years of JEFIT history (492 workouts since August 2022). **All of it becomes the
  app's own data**, not a read-only archive. See [JEFIT_EXPORT.md](JEFIT_EXPORT.md).
- Logs in kg and wants lb a tap away.
- Uses straight sets. Supersets and drop sets should exist but stay out of the way.
- **Locks the phone or switches to music or messages between sets.** The rest timer has to
  alert with the phone locked, which is why this is a native app.
- iPhone 17 Pro Max on iOS 26.6.1. Maybe a watch later.
- Cares more about everything working than about looks, but wants it clean, easy to read,
  easy to get around, and **not a copy of JEFIT**.

## What the best apps do, and what we take

Researched 11 October 2026.

| App | Taken |
|---|---|
| Strong, Hevy | The whole workout as one scrolling list; a Previous column; one tap to complete a set; warm-up, drop and failure set types; plate and warm-up calculators; CSV export of everything |
| Fitbod, MacroFactor Workouts | Swap an exercise mid-workout for a similar one; gym profiles listing your equipment; a body map of recently trained muscles. After a swap, MacroFactor keeps the old exercise's history in view, which the plateau swap needs |
| MacroFactor, Alpha Progression | Progression targets from readable rules, not AI |
| Apple Music | The mini-player as the model for an in-progress workout |

Not taken: social features, AI-generated workouts, subscriptions.

## The app

Five tabs: **Train**, **History**, **Exercises**, **Progress**, **Settings**. A workout in
progress shows as a mini-player above the tab bar on every tab.

### Train: programs and the split picker

- **Train** shows the next day in your rotation and every day in the current program.
  Rotation is rolling (decision #12): FB1 → FB2 → FB3 → FB1, whatever the weekday.
- **New program:** pick a split, and the app creates its days:

  | Split | Days created |
  |---|---|
  | Full body | 2 or 3 days: Full Body 1, 2, 3 |
  | Upper/Lower, 4-day | Upper A, Lower A, Upper B, Lower B |
  | Upper/Lower, 6-day | Upper A, Lower A, Upper B, Lower B, Upper C, Lower C |
  | Push/Pull/Legs, 3-day | Push, Pull, Legs |
  | Push/Pull/Legs, 6-day | Push A, Pull A, Legs A, Push B, Pull B, Legs B |
  | Custom | Days you name, each with a focus you choose |

- **Adding exercises to a day** opens the library already filtered to that day's focus. An
  Upper day lists upper-body exercises first; "Show all" is one tap away. Exercises you have
  done before come first, with your last numbers beside them.
- **Suggest a day** fills a day with a balanced set of movements for its focus, drawn from
  exercises you have done before. An Upper day gets a horizontal push, horizontal pull,
  vertical push, vertical pull, biceps and triceps. You edit it from there.
- Per exercise in a day: target sets, rep range, rest and note. Reorder, add and remove at
  any time. Editing a program never changes past workouts (rulebook §10).
- Programs you stop using are archived, not deleted. Your old JEFIT programs arrive that way.

### Exercises: the library

- **876 exercises** from the open database, plus your own. Each has primary and secondary
  muscles, equipment, push/pull and compound/isolation, plus the movement pattern used by
  plateau swap.
- **Browse and filter** by muscle, equipment, push/pull and "done before"; search by name.
- **Create and edit custom exercises:** name, equipment, muscles, movement pattern, per-hand
  or total load, and what it tracks (weight × reps, reps, time, assisted).
- **Exercise page:** About (muscles, instructions), History (every session), Charts,
  Records and Notes.

### The workout screen

**A scrolling list, with a focus toggle.**

- **List (default):** every exercise is a card on one page. The current card is open; the
  others fold to one line showing a tick when done and last time's numbers. Tap a card to jump
  to it.
- **An open card shows:** the sticky note, a "today" chip with the target and last time, the
  set rows (Set, Previous, kg, Reps, ✓), + Add set, and a menu with swap, history, plate
  calculator and set type.
- **Focus mode:** one button switches to the current set alone, with huge numbers and steppers,
  last time and target, and an up-next strip. The same button switches back.
- **Bottom bar:** a round rest countdown with −15 s, +15 s and Skip while resting; otherwise
  "Log set 2 · 50 × 10".
- **Rest alerts:** a notification with vibration when rest ends, plus a countdown on the lock
  screen and Dynamic Island.
- **Kept from the prototype:** prefilled values ghosted until logged, ↑/↓ against last time,
  steppers plus tap-to-type, saving on every set, resuming after the app is killed.
- **Summary:** duration, volume against last time, which records were broken, every set with
  its estimated 1RM, the muscles trained, and an optional session note and effort rating.

### History and analytics

- **History tab:** a month calendar coloured by workout day, the week's count against your
  goal of 3 sessions, and every workout back to August 2022 as a list grouped by week.
- **Workout detail:** every set, volume, duration, records and notes. Editable: typos happen,
  and every figure recomputes (rulebook §10).
- **Exercise charts:** estimated 1RM, heaviest weight, best set and volume per session over
  time. Also a records table (rulebook §5) and every past session.
- **Progress tab:**
  - volume, sessions and training time per week;
  - hard sets per muscle per week on a body map, against target ranges (rulebook §6);
  - a feed of recent records;
  - consistency over months;
  - body weight, body fat and measurements, including the 66 JEFIT entries.
- **Plateau flags** (rulebook §8) appear on the exercise page and the Progress tab once plateau
  swap is built.

### Import and export

- **Export:**
  - a full backup, which restores everything exactly;
  - a CSV of every set, for spreadsheets and other apps;
  - an automatic backup after every workout, to a folder you choose.
- **Import:**
  - restore a backup (the current data is backed up first);
  - a JEFIT export (rerunning it adds nothing twice).

### Look and feel

- **A theme of its own:** dark, with a single accent colour that is not JEFIT's blue.
- **Easy to read:** large rounded numbers, big tap targets, muscle tags coloured by body
  region, proper charts and light haptics.
- **Cut from JEFIT:** the large exercise animation (a small image at most), the AI sparkle,
  share, and Kcal & HR until there is a watch.

## Your spin

### Plateau swap (your idea)

When an exercise stops progressing for about three weeks, the app suggests a near-identical
alternative: the same movement on a different implement. Flat barbell bench press → machine
chest press or seated chest press.

- "Stopped progressing" is defined in rulebook §8. It counts rep gains, not only weight
  increases, so 60 kg × 8 → 60 kg × 10 is progress.
- It is a suggestion, never automatic. Choose **swap** (from the next session), **keep for
  now** (snoozes it) or **dismiss**.
- Swapping edits the program; history is untouched. The movement's history shows both
  exercises side by side.
- It needs every exercise tagged with a *movement pattern*. The open dataset has no such
  field, so your exercises are tagged by hand first.

### Also planned

- **Sticky exercise note:** seat and pad positions and cues, shown every time.
- **Next-time targets** from a rule you pick, e.g. three sets of 10 at a weight → +2.5 kg next
  time.
- **Gym profile:** the equipment your gym has, so suggestions and swaps only offer what
  exists.
- **Short-session version** of a day, **plate calculator**, **warm-up ramp**.

**Never:** social features, points, upsells, AI coaching, nutrition, accounts, cloud sync.
