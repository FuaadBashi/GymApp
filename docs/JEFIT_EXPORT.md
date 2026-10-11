# JEFIT export

What JEFIT's CSV export contains, how it maps onto this app, and the traps found in the
11 October 2026 export. The file is kept at `data/jefit/jefit-export-2026-10-11.csv`, which is
gitignored because it holds personal data.

## Contents

| Section | Rows | Span | What it is |
|---|---|---|---|
| WORKOUT SESSIONS | 492 | Aug 2022 → Oct 2026 | One per workout: start/end (Unix seconds), total, workout and rest time, volume |
| EXERCISE LOGS | 2,552 | Aug 2022 → Oct 2026 | One per exercise per workout. `logs` holds the sets as `kg x reps` |
| EXERCISE SET LOGS | 1,934 | Dec 2024 → Oct 2026 | One per set: weight in lb, reps, set type, timestamp |
| ROUTINES | 2 routines, 32 days, 198 exercises | | Days with each exercise's sets, rest and target reps |
| NOTES | 247 | Oct 2022 → Aug 2025 | Nearly all attached to an exercise: seat levels, cues, how a set went |
| PROFILE | 66 | Aug 2022 → Dec 2025 | Body weight, body fat, circumferences, height |
| EXERCISE RECORDS | 203 | | JEFIT's best estimated 1RM per exercise |
| CARDIO LOGS | 25 | | Treadmill, cycling, walking |
| CUSTOM EXERCISES | 6 | | |
| FAVORITE EXERCISES | 3 | | |
| SETTING | 1 | | kg, cm, 60 s rest, 10 reps, week starts Sunday |

The 217 exercise names reduce to 197 exercises, because JEFIT renamed some over time.
55 exercises cover 90% of everything logged since January 2025.

The current routine days are **1FBD 1** (6 exercises) and **2FBD 2** (10 exercises),
alternating. Earlier days (5/3/1, upper/lower, "comeback") remain in the routine but have
not been used recently.

## Format

- Sections open with `### NAME ###` and close with a line of `#`.
- ROUTINES repeats its header before every row, with blank lines between. Three tables
  interleave in file order: routine, then a day, then that day's exercises.
- An exercise is identified by `(belongSys, eid)`: `belongSys` 1 is JEFIT's library and 0 a
  custom exercise. The name can change under the same id ("Wide Grip Lat Pulldown" became
  "Cable Lat Pulldown (Wide Grip)"), and some names have trailing spaces.
- Links between tables:
  - An exercise log's `belongsession` points to a session's `_id`. All 2,552 link.
  - An exercise log's `day_item_id` points to a routine exercise's `_id`, whose `belongplan`
    is the day. Only 716 link, because older days were deleted.
  - A set log's `exercise_log_id` points to an exercise log's `_id`.
- A session's `day_id` is always 0. The routine day a workout followed is known only through
  `day_item_id`.

## Units and figures

- `logs` is in kg, carrying float residue from JEFIT's internal pounds: `39.9999`,
  `79.9998`. Round to 0.01 kg on import.
- Set logs hold `weight_lbs` (44.0924 is 20 kg).
- JEFIT's estimated 1RM is Epley, the same formula as rulebook §4. An exercise log's `record`
  is that session's best.

## Traps

1. **The two set sources disagree, and the set rows win.** Of 896 exercise logs that have
   set rows, 781 agree with the `logs` string. 101 differ in values and 14 in the number of
   sets. On 27 Dec 2024, Cable Tricep Pushdown has `logs` 27×4, 22.5×8, 25×5, but set rows
   27×15, 36×12, 45×10. JEFIT's own history screen shows the set rows (checked 11 Oct 2026,
   and Cable Reverse Curl that day agrees). **Rule:** where an exercise log has set rows,
   they are canonical. The `logs` string is used only for logs without set rows, which
   means everything before 14 Dec 2024.
2. **Assisted exercises are logged as positive assistance.** "Machine Assisted Pull-Up,
   58 kg" means 58 kg of help. This affects four exercises: Machine Assisted Pull-Up, its
   Hammer Grip variant, Machine Assisted Chin-Up and Machine Assisted Dip. The importer
   negates them (rulebook §2).
3. **Bodyweight exercises carry placeholder weights.** Hanging Knee Raise logs `10x7`, while
   its set rows have no weight. 80 sets have weight 0 and 52 have 0 reps.
4. **Warm-ups are mostly unmarked.** Only 18 sets are flagged warm-up. The usual ramp
   (bar × 10, then a middle weight, then working sets) is not, so imported volume includes
   warm-ups. PRs and plateau checks use the best set and are unaffected.
5. **Dates.** 50 logs carry a `mydate` different from their session's start date, and
   37 days have two sessions. Use the session's start time.
6. **JEFIT's records do not all recompute.** 155 of 195 match the best Epley figure from the
   logs; 40 do not, probably because of deleted logs and rounding. Records are not imported;
   they are derived (rulebook §5).
7. **The first export was a different JEFIT account.** It had a different user id, lb and
   inches, and no workouts.

## Mapping

| JEFIT | Here |
|---|---|
| Session | Workout: start, end, duration |
| Exercise log, with its set rows (or `logs` before Dec 2024) | That exercise's sets within the workout |
| Set type `warm-up` / `failure` | Warm-up / failed (rulebook §3) |
| `(belongSys, eid)` | A mapping table from JEFIT exercise to library exercise |
| Routine days | Routine days. The two current days are active; the rest are archived |
| Notes on an exercise | That exercise's note history. The newest becomes the sticky note, for you to edit |
| Profile | Body entries |
| Records | Not imported; derived |

**Exercise mapping.** Each JEFIT exercise is matched by name to the open exercise library
where possible, then hand-checked; anything left becomes a custom exercise. Start with the
55 that matter and take the long tail in bulk.

**Importer rules.**

- It runs in the app: pick the CSV in Files.
- Importing the same export twice changes nothing.
- It reports counts and lists every row it skipped, with the reason.
- Imported rows keep their JEFIT ids, so any figure can be traced back to the export.
