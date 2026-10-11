# Roadmap

Build order agreed 11 October 2026, updated to prioritise the additions after phase 2. Each phase ends with something usable and a list of what
"done" means. JEFIT stays in use alongside until phase 5.

Phases 0–2 are specified card by card in [specs/](specs/), and progress is tracked in
[HANDOFF.md](HANDOFF.md). Phases 3–5 are outlined and get full specs when phase 2 closes.

The prototype was removed in card 2.8; the workout screens now use the database.

## Phase 0: Foundation

**Done 11 October 2026.** The full real export imports in under a second and matches the
reference on every count, skip reason and spot check.

Everything else reads from this.

- SQLite database through GRDB (decision #8), with tables for exercises, programs, days, day
  exercises, workouts, sets, notes and body entries. Rulebook invariants are enforced as
  CHECK constraints where they can be.
- Bundle the open exercise library: 876 exercises with muscles, equipment, push/pull and
  mechanic, and a body region (upper, lower, core) for each.
- In-app JEFIT import (JEFIT_EXPORT.md) covering all workouts, sets, notes, body entries and
  programs. Your JEFIT exercises keep their names and take their classification (equipment,
  load mode, muscles, movement pattern) from the checked-in exercise map (decisions #28–#29).

**Done when:**
- The import reports 468 workouts, 2,541 exercise entries and 7,751 sets, matching
  `tools/reference_import.py`.
- The other 24 workouts are reported with their reasons: 20 are empty in JEFIT and 4 are
  cardio only. Every other skipped row has a reason too.
- Spot checks match JEFIT's history screen: 27 Dec 2024 and the last three sessions.
- Rerunning the import changes nothing.

## Phase 1: Programs and the exercise library

**Done 11 October 2026.** From a clean install with the JEFIT import, the Full Body program was
built in the app: Full Body 1 and 2 copied from JEFIT's 1FBD 1 and 2FBD 2 with their history,
and Full Body 3 filled by "Suggest a day" from exercises not already in the other two days.
Full Body 3, never done, is next up.

- Exercises tab: browse, filter by muscle, equipment, push/pull and "done before"; search.
- Create and edit custom exercises.
- Basic exercise page: About, History list and Notes. Charts come in phase 3.
- New program with the split picker; days created per split.
- Adding exercises to a day filters to the day's focus; "Suggest a day" fills a balanced day
  from your history.
- Edit days: sets, rep range, rest and note per exercise; reorder; add; remove. Archive
  programs.
- Train tab: the next day in the rotation and the current program's days.

**Done when:** you can build FB3 in the app, and the current program runs FB1 → FB2 → FB3 →
FB1.

## Phase 2: Workout screen

- [x] **Phase 2 complete — 11 October 2026.**

Session flow and final review verified. Full Body 1
finished on the simulator with 13 sets and 3,808 kg. The Live Activity extension was added in Xcode (decision #35) and its locked countdown
is verified. The rest alert fires at expiry; the activity shows “Rest over” on the system’s stale
refresh and clears on return (decision #37). Verified while locked; the simulator delayed
the visual refresh by about a minute, which is accepted.

- The list of exercise cards, with the focus toggle.
- Mini-player above the tab bar for a workout in progress.
- Rest bar; lock-screen and Dynamic Island countdown, verified on a free account.
- Swap an exercise mid-workout; add an exercise; set types; plate calculator.
- Summary, with records and comparison against the last session of the day.

**Done when:** a full session can be logged without touching JEFIT, including after the app
is killed mid-rest.

## Additions after phase 2

[Requirements](specs/post-phase-2-additions.md): exact-exercise stills with on-demand
movement demonstrations, set and session-exercise notes, richer set labels, and layered
recovery of all edits online or offline. These are implemented before phase 3, with initial
media coverage for barbell bench press and back squat. Expand curated exact-variant media
coverage separately; other exercises honestly show missing media. External backups need
the owner to choose a folder. Device/cloud-provider failure checks remain outstanding.
Their cards are in [02a-additions.md](specs/02a-additions.md). Bring the required backup and recovery work forward from
phase 4; phase 4 can then cover remaining import/export work.

## Phase 3: History and analytics

May be cut down (decision #36): deep analysis could move to a separate offline tool that
reads the export, leaving the app with history and the basic per-exercise figures.

- History tab: calendar, week grouping, count against goal, every workout since 2022.
- Workout detail, editable, with every figure recomputing.
- Exercise page charts: estimated 1RM, heaviest weight, best set and volume; records table.
- Progress tab: weekly volume, sessions and time; sets per muscle on a body map; recent
  records; consistency; body stats.

**Done when:** the figures for a sample of exercises agree with a hand calculation from the
export, and JEFIT's records match where JEFIT_EXPORT.md trap 6 says they should.

## Phase 4: Import, export and backups

- Full backup export and restore (the current data is backed up before any restore).
- CSV export of every set.
- Automatic backup after every workout to a folder you choose; keep the last 30 plus one per
  month (decision #9).

**Done when:** a backup taken on the phone restores onto a fresh install with nothing lost,
and that test has actually been run.

## Phase 5: On the phone

- Free Apple ID signing, Developer Mode, first install.
- Expiry warning two days before the 7-day install lapses (decision #3).
- First real sessions alongside JEFIT, then JEFIT is dropped.

The phone install itself can happen any time after you add your Apple ID to Xcode. This phase
is about trusting the app, which needs phase 4 first.

## Later

Plateau swap (rulebook §8), next-time targets, gym profile, warm-up ramp, short sessions,
supersets and drop sets in the UI, progress photos, Apple Watch, Apple Health.
