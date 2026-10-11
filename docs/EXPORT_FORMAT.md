# Export format

GymApp exports two files. Both are complete, and neither needs the app to be read. They are
the input for anything built on this data, starting with the planned offline analysis tool
(decision #36).

| File | From | Contains |
|---|---|---|
| `GymApp-sets-<date>.csv` | Settings → Data → Export sets as CSV | one row per logged set |
| `GymApp-<id>.sqlite` | Settings → Backups & recovery → Share full backup | everything: exercises, programs, workouts, sets, notes, body entries, settings |

**Use the `.sqlite` backup for analysis.** The CSV is for other apps and spreadsheets: it
flattens the data and leaves out programs, the exercise library and body entries.

## Rules that apply to both

- **Loads are stored exactly as entered** (rulebook §1): a number plus its unit, kg or lb.
  Convert with 1 lb = 0.45359237 kg. Never assume one unit.
- **Load meaning depends on the exercise's load mode** (rulebook §2):

  | `loadMode` | Load means | Volume multiplier |
  |---|---|---|
  | `total` | the number on the bar, stack or machine | 1 |
  | `perHand` | one dumbbell; both hands work | 2 |
  | `perSide` | one side; reps are per side | 2 |
  | `bodyweightPlus` | added to body weight; negative = assistance | 1, on body weight + load |
  | `repsOnly` | no load (empty) | – |

- **Set types** (rulebook §3): `working`, `warmUp` (no volume, no records), `failed` (counts
  like working), `drop` (a further segment of the set before it: adds volume, never a record
  or a hard set).
- **Derived figures are never stored.** Volume, estimated 1RM (Epley, 1–12 reps), records and
  sets per muscle are computed from the sets using [the rulebook](TRAINING_RULEBOOK.md).
  `GymApp/Domain/TrainingMath.swift` is the reference implementation, and
  `tools/check_phase3.py` shows the same figures computed in Python.
- **Times** are UTC instants. A workout belongs to the *local* date it started (rulebook §6).

## CSV

UTF-8 without BOM, RFC 4180 (fields with `,` `"` or line breaks are quoted, quotes doubled),
CRLF line ends, a header row. Every completed set of every finished workout, oldest first.
Decimals always use a dot.

| # | Column | Notes |
|---|---|---|
| 1 | Date | local `yyyy-MM-dd HH:mm:ss` of the workout's start |
| 2 | Workout Name | |
| 3 | Duration | `1h 5m` or `45m` |
| 4 | Exercise Name | |
| 5 | Set Order | 1-based among working and failed sets; `W` warm-up, `D` drop segment |
| 6 | Weight | as entered, in column 13's unit; empty for `repsOnly`; negative = assisted |
| 7 | Reps | |
| 8 | Distance | always empty (no cardio yet) |
| 9 | Seconds | always 0 |
| 10 | Notes | the set's note |
| 11 | Workout Notes | |
| 12 | RPE | empty unless recorded |
| 13 | Weight Unit | `kg` or `lb` |
| 14 | Set Type | `working`, `warmUp`, `failed`, `drop` |
| 15 | Reps In Reserve | 0–3 (0 = max rep, 1–3 = MR −1/−2/−3); empty if not recorded |
| 16 | Labels | `;`-joined: `deload`, `injury`, `form` |
| 17 | Exercise Note | the note on this exercise in this session |
| 18 | Load Mode | see the table above |
| 19 | Equipment | `barbell`, `dumbbell`, `machine`, `cable`, … |
| 20 | Primary Muscles | `;`-joined |
| 21 | Effort | the workout's effort, 1–10 |
| 22 | Workout ID | joins rows of one workout |
| 23 | Exercise ID | stable across exports; `jefit:<sys>:<id>` for imported exercises |

Columns 1–12 match Strong's export, so apps that import Strong files can read it.

## SQLite backup

A plain SQLite 3 file in rollback-journal mode; open it read-only with any SQLite client.
Tables (GRDB migrations `v1`, `v2`):

- **exercise**: `id`, `name`, `equipment`, `loadMode`, `primaryMuscles` / `secondaryMuscles` /
  `instructions` (JSON arrays), `force`, `mechanic`, `category`, `bodyRegion`,
  `movementPattern`, `source` (`library`, `jefit`, `custom`), `libraryId` (the library
  exercise an imported one corresponds to), `stickyNote`, `defaultRestSeconds`,
  `preferredUnit`, `isFavorite`, `isArchived`, `createdAt`.
- **program**, **programDay**, **dayExercise**: templates. `programDay.copiedFromDayId` links
  a day to the day it was copied from, whose history it inherits (rulebook §7).
- **workout**: `startedAt`, `endedAt` (NULL while in progress: exclude these from history),
  `programDayId`, `title`, `note`, `effort`, `source` (`app`, `jefit`).
- **workoutExercise**: one exercise in one workout, in `position` order, with the targets it
  had then (`targetSets`, `repMin`, `repMax`, `restSeconds`) and a session `note`.
- **workoutSet**: `position`, `loadHundredths` (load × 100, in `unit`; NULL for reps-only),
  `unit`, `reps`, `type`, `completedAt` (NULL = planned, not logged: exclude), `rpe`,
  `note`, `repsInReserve`, `annotations` (JSON array).
- **exerciseNote**: dated notes per exercise.
- **bodyEntry**: `date` (`yyyy-MM-dd`), `weightHundredths` + `weightUnit`, `bodyFatPercent`,
  `measurements` (JSON object).
- **setting**: key/value strings (`weightUnit`, `weekStartsOn`, …).
- **importRun**: one row per JEFIT import.

**History** is `workout.endedAt IS NOT NULL` joined to `workoutSet.completedAt IS NOT NULL`.

A starting query, every logged set with what it needs for the rulebook:

```sql
SELECT w.startedAt, w.title, e.name, e.loadMode, s.position, s.type,
       s.loadHundredths / 100.0 AS load, s.unit, s.reps
FROM workoutSet s
JOIN workoutExercise we ON we.id = s.workoutExerciseId
JOIN workout w ON w.id = we.workoutId
JOIN exercise e ON e.id = we.exerciseId
WHERE w.endedAt IS NOT NULL AND s.completedAt IS NOT NULL
ORDER BY w.startedAt, we.position, s.position;
```

## Verified

- The CSV has one row per logged set: 7,751 for the imported history (`CSVExportTests`).
- A backup restored onto a fresh install has identical row counts in every table and
  identical progress and records for bench press, squat and deadlift
  (`BackupRoundTripTests`).
