# Phase 7: Records, the workout flow and goals

**Specified 14 October 2026** from the owner's answers in that day's review. Research behind
the numbers: [ANALYTICS_RESEARCH.md](../ANALYTICS_RESEARCH.md) section 6.

Decisions this phase rests on:

- **Estimated 1RM is the personal best** that drives badges, banners and the "beat my best"
  table. Heaviest weight, most reps at a weight and best session volume stay recorded and
  shown as records, without badges.
- **Time-window bests** follow JEFIT: a set is first checked against the all-time best
  (volt). If it doesn't beat it, it is checked against the best of the last 1, 6 and 12
  months, and the longest window it beats is shown (gold). A window is shown only when its
  best is below the all-time best, so after a gap of under a month the all-time best stays
  the mark.
- **Banners are in the screen**, never system notifications.
- **Back from the end screen reopens the workout**: it becomes unfinished again, so sets can
  be added or fixed, or the workout deleted. Records recompute because they are derived.
- **Supersets** follow Hevy: logging A1 jumps to A2 with no rest (or a short rest set per
  group), and the full rest starts after the last exercise of the group. Groups of three or
  more work the same way.
- **Warm-ups** are built per exercise, switchable on and off during a workout. The day's
  first exercise, when it is a barbell squat, bench or deadlift pattern, gets the strength
  ramp; every other exercise gets the short ramp.

## Card 7.1: Time-window bests

- `TrainingMath.bestStatus(e1RM:history:at:)` (rulebook §5 addition, written into
  TRAINING_RULEBOOK.md as §5a): given a set's e1RM, the exercise's earlier finished sets
  and the set's date, return `.allTime`, `.window(months: 1 | 6 | 12)` or `.none`, with the
  value it beat. Windows are 30, 182 and 365 days before the set. Rules as above. A tie is
  not a best (`> 0.01 kg`, as `recentRecords`).
- `ExerciseStats.marks(sessions:)` also returns best e1RM for each window, heaviest, most
  reps per load and best session volume (existing records keep their definitions).
- **Tests:** a lift trained weekly never shows a window best; after a 3-month gap, sets
  below the all-time best but above the 1-month and 6-month bests report `.window(6)`;
  after a 3-week gap the all-time best stays the mark; ties report `.none`.

## Card 7.2: Best banners and set badges in the workout

- When a set is logged, its status comes from 7.1 against finished history **plus the sets
  already logged in this workout**. A banner slides in at the top of the workout screen for
  three seconds: "New best est. 1RM · 92.5 kg" (volt, trophy) or "Best in 6 months · 85 kg"
  (gold, clock). A success haptic plays for an all-time best, a light one for a window best.
- The set row keeps a small trophy (volt) or clock (gold) after the banner goes.
- Unlogging or editing the set re-evaluates and removes the badge if it no longer holds.
- **Tests:** model-level: logging a best sets the banner state; unlogging clears the badge.

## Card 7.3: Best hints and "beat my best"

- Under the selected set's editor: this set's e1RM against the all-time best, and against
  the window best only when that differs ("e1RM 88.3 · best 92.5 · 6-month best 86").
- Tapping the best opens a sheet: one row per rep count in the exercise's rep range (the
  day item's range, else the settings default), each with the lightest load that beats the
  all-time best, rounded **up** to the exercise's step (the learnt increment from the
  studio's rule, ported as `TrainingMath.step(loads:)`: the most common positive gap
  between distinct loads used, else 2.5 kg). Tapping a row fills the selected set. A button
  opens the exercise's history.
- **Tests:** rows for 8–12 reps against a 100 kg best with 2.5 kg steps (expected values in
  the test from Epley by hand); `step(loads:)` on 4.5 kg machine stacks.

## Card 7.4: Fixing sets easily

- Each logged set row gets a visible edit control (pencil), not only the long-press menu:
  change load, reps and type, unlog, or delete. Every change writes immediately and
  records, banners and badges follow (they are derived).
- **Tests:** editing a logged set from 590 to 59 kg removes the record it had made in
  `recentRecords` and in the summary.

## Card 7.5: The end screen

- Opens after Finish. From top: title and date; tiles for duration, total kg, sets and
  records, each with the change against **the last time this day was done** (falling back
  to the last workout); the body map of today's muscles; then every exercise with its sets
  in small text, today against last time (e1RM and volume change), volt highlight and
  trophy for an all-time best, gold for a window best.
- Tapping an exercise opens its sets for editing (7.4), including delete.
- **Back to workout** reopens the workout (`WorkoutWrites.reopen(db, workoutId:)`: clears
  `endedAt`, refused if another workout is in progress); from there it can be continued,
  finished again or deleted. **Done** closes the screen. No delete on the end screen itself.
- **Tests:** reopen then finish keeps every set; reopen is refused while another workout is
  in progress; the comparison uses the same-day lineage first.

## Card 7.6: Supersets

- Migration **v5**: `dayExercise.supersetGroup TEXT` and `workoutExercise.supersetGroup TEXT`
  (null = none) and `supersetRestSeconds INTEGER` on both (rest between members, default 0).
- Day editor and workout: "Superset with…" on an exercise's menu groups it with another;
  "Remove from superset" ungroups. Grouped exercises show a shared bracket.
- Logging a set of a member that is not the group's last: no full rest; the screen moves to
  the next member's next planned set, with the member rest if set. After the last member:
  the last member's full rest, then back to the first member.
- Starting a workout from a day copies the groups.
- **Tests:** rotation order A1 → B1 → A2 → B2 with rest only after B; a group of three;
  ungrouping restores normal rest.

## Card 7.7: Warm-up builder

- In the workout, each exercise's menu has **Warm-up sets** on/off. On adds unlogged
  `warmUp` sets before the first working set; off removes the unlogged warm-up sets it
  added. The working weight is the first working set's load.
- Strength ramp (the day's first exercise when its movement pattern is squat, hinge or
  horizontal push and its equipment is barbell): empty bar × 10 (20 kg; skipped if the
  working weight is under 30 kg), 50% × 5, 70% × 3, 85% × 1. Short ramp (every other
  exercise): 50% × 8, 80% × 3. Loads round to the exercise's step (7.3); a step that rounds
  to the same load as the one before is dropped.
- A per-exercise default (on/off) is remembered on the day item.
- Warm-up sets never count toward volume, hard sets or records (rulebook §2, §6).
- **Tests:** ramp for a 100 kg barbell bench first in the day; short ramp for a 40 kg
  machine row with 5 kg steps; toggling off leaves logged warm-ups alone.

## Card 7.8: Goals and standards

- **Profile** (Settings → Profile): sex, birth year, height. Stored on the phone only;
  body weight comes from BodyQueries (typed or Apple Health).
- **Goals:** on an exercise's Progress page, set a target e1RM. The page shows the goal,
  the gap, and a projected date from **this exercise's own history**: a saturating fit
  (e1RM = a − b·e^(−t/c)) over the last 12 months, with a range from the fit's spread;
  "not enough data" under 6 sessions over 8 weeks, and "not reachable at the current rate"
  when the target is above the fit's ceiling. No population-based forecast.
- **Standards:** gym-lifter tiers (Untrained, Beginner, Novice, Intermediate, Proficient,
  Advanced, Exceptional, Elite, World class) for squat, bench, deadlift, overhead press,
  row and pull-up from a table generated by `tools/build_strength_standards.py` and checked
  in as `GymApp/Resources/strength-standards.json`, with the source and licence recorded.
  **Before building, confirm the source's licence allows bundling** (FitnessVolt states
  CC BY 4.0 for its Symmetric Strength population); if it doesn't, stop and ask.
- **Tests:** the fit on synthetic data; tier lookup at exact boundaries; no projection under
  the data minimum.

## Card 7.9: Reports in the app

- The studio writes weekly and monthly reports (phase 8) as `GymApp-reports.json` into the
  backup folder. The app reads them like suggestions and shows a **Reports** page under
  Progress: a list by week and month, each opening to its sections.
- **Tests:** parsing; a malformed report is skipped, not fatal.

## Card 7.10: Phase close

Device checks with screenshots of the banner, the end screen and a superset; HANDOFF;
README.
