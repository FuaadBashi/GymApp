# Training rulebook

This document defines every figure that the app shows. The code must agree with it. If the
code and this document do not agree, that is a bug. A chart that compares numbers of
different kinds is worse than no chart.

## §1 Units and stored loads

1. The app stores a load exactly as you enter it: a whole number of hundredths, plus the
   unit. It stores 62.5 kg as `6250, kg` and 45 lb as `4500, lb`.
2. The app converts loads only for display and for totals. It **never stores** a converted
   load, because a stored conversion changes 45 lb into 44.99 lb.
3. 1 lb = 0.45359237 kg, exactly.
4. For totals (volume, PR comparisons, plateau checks), the app converts each load to kg
   first. Then it shows the result in the preferred unit.
5. Each exercise keeps the unit of its last logged set. Thus lb dumbbells and kg machines can
   be in the same history.

## §2 What a logged load means

Each exercise has a **load mode**. The load mode tells what the logged number means. After an
exercise has history, its load mode cannot change, because a change would change the meaning
of the past sets.

| Load mode | Typical exercises | The number you log | Load in calculations | Volume |
|---|---|---|---|---|
| `total` | Barbell (with the bar), machine, cable, Smith, plate | The full load | As logged | × 1 |
| `perHand` | Two dumbbells at the same time | One dumbbell | As logged | × 2 |
| `perSide` | One-arm row, single-leg press | One side; reps are per side | As logged | × 2 |
| `bodyweightPlus` | Pull-up, dip, chin-up, assisted machines | Added weight, or assistance as a negative number | Body weight + the logged number, never below 0. Body weight is the latest entry on or before the workout date | × 1 |
| `repsOnly` | Push-up, knee raise, plank | Nothing | None | Not counted |

Each machine is a different exercise. The app never compares one machine with another. A
plate that you hold during a partial-body-weight movement (weighted crunch, back extension) is
`total`, because the plate is the only load that changes.

If there is no body-weight entry, whole-body exercises use reps only. The app tells you this.
It does not invent a figure.

## §3 Set types

| Type | Volume | Hard set (for muscle counts) | PRs and plateau |
|---|---|---|---|
| Working (default) | Yes | 1 | Yes |
| Warm-up | No | 0 | No |
| Drop set (a working set and its drops) | Each segment counts | 1 for the full drop set | Only the first segment |
| Failed or partial | The reps you did | 1 | The reps you did |

The app stores a drop set as its first segment (a working or failed row), then one `drop` row
for each other segment. A `drop` row adds volume and nothing else. That gives "1 for the full
drop set" and "only the first segment".

A superset is a group of exercises, not a set type. It changes no calculation.

**Effort labels (11 October).**

- Max rep means 0 reps in reserve. MR −1, MR −2 and MR −3 mean 1, 2 and 3 reps in reserve.
- The app stores the effort label apart from the actual reps, the RPE and the set type.
- Max rep does not mean a failed rep.
- Deload, injury and form are separate labels. They can be on the same set as an effort label.
- Warm uses the warm-up type.
- Labels do not change any calculation. 60 kg × 8 at MR −1 gives 8 reps and 480 kg of volume,
  not 9 reps.
- Notes and labels belong to that set or session. The app does not copy them into a new
  workout as facts.

## §3a Warm-up ramps

You turn on warm-ups for each exercise (card 7.7). The app then adds them before the first
working set that is not logged yet. It uses the load and unit of that set.

- The **strength ramp** applies to the first exercise of the day when that exercise is a
  barbell squat, a hinge or a horizontal push: the bar × 10 (only when the working load is
  30 kg / 65 lb or more), then 50% × 5, 70% × 3, 85% × 1.
- The **short ramp** applies to each other loaded exercise: 50% × 8, 80% × 3.
- Each load rounds to the nearest learnt step (§7a, default 2.5).
- The app removes a warm-up load that does not go up, that reaches the working load, or that is
  at or below the bar in the strength ramp.

Warm-ups are `warmUp` sets, so they never count (§3).

## §4 Estimated 1RM

- Epley: `load × (1 + reps / 30)`. For one rep, the estimate is the load.
- The app shows it as a PR only for sets of 1–12 reps. Above 12 reps the estimate is not
  accurate enough to show.
- Plateau checks (§8) use it for 1–20 reps. There, a consistent figure is more important than an
  accurate one.

## §5 Personal records

The app finds records for each exercise from working and failed sets. It never uses warm-ups or
`drop` segments. It never finds records for `bodyweightPlus` or `repsOnly` exercises. The app
calculates all records from the history each time. Thus a corrected set can add or remove a
PR.

- **Heaviest load**, at any reps.
- **Best estimated 1RM** (§4).
- **Rep PR:** the most reps at a given load.
- **Best session volume.**

## §5a Time-window bests

Badges, banners and the "beat my best" table use the **best estimated 1RM** (§4, from the sets
that §5 counts). The app compares a new logged set with each earlier counted set of the
exercise. This includes sets from earlier in the same workout.

1. **All-time best:** the set's estimated 1RM is more than 0.01 kg above the best so far.
2. **Window best:** this applies only if you stopped training this exercise for 30 days or
   more at some time after the all-time best (the gap up to this set also counts). Then the set
   can be a window best. The window is the longest of the last 12, 6 and 1 months (365, 182 and
   30 days) whose best is below the all-time best. The set must be more than 0.01 kg above that
   window's best.
3. If neither rule applies, the set is not a best. A first set ever has nothing to beat.

Thus a lift that you train with no month off shows only all-time bests. After a long break, the
return gives smaller bests on the way back. The app still records heaviest load, rep PRs and
best session volume (§5). These do not give badges.

### §5b The set being entered, against the bests

On the workout screen, the selected set shows its estimated 1RM. The app calculates it again
each time the values in the editor change (Epley, §4). For more than 12 reps it shows "no
estimate".

Below that, the app shows the all-time best. When rule 2 of §5a applies, it also shows the
window best. Each best shows the set that made it (weight × reps) and the difference: "X kg
above", "X kg below" or "level with it" (within 0.01 kg).

**Best last time.** If no window best applies and you last did the lift 30 days or more ago,
the app also shows the best set of that last session. After a long break, this is the nearer
target. The app shows it only when it is below the all-time best.

When you tap a best, its beat table opens. For each rep count in the day's range, the table
shows the lightest load, in the exercise's learnt step (§7a), whose estimated 1RM is more than
0.01 kg above that best.

## §6 Volume and sets per muscle

- **Volume** = Σ (calculation load × reps) over the sets that count for volume (§2, §3), in kg.
  JEFIT uses a different definition, so the two figures do not agree.
- **Hard sets per muscle:** each set counts its effort (§6a), from 0 to 1, times 1 for each
  primary muscle and 0.5 for each secondary muscle.
- **Week:** starts on the day set in Settings (default Sunday). A workout belongs to the local
  date on which it started, also when it continues after midnight.

## §6a How hard a set was (22 October; effort labels changed 23 October)

A set does not always count as a full hard set. The app judges each set against the same
exercise's recent work. The result is a number from 0 to 1. Recovery, the weekly sets per muscle,
the muscles on the end-of-workout screen, and the studio's balance and reports all use it.

1. **Warm-up and drop rows** count 0, as in §3.
2. **Labels win over the calculation:**
   - deload or injury: 0, because the set was light on purpose;
   - any effort label (max rep, MR −1, MR −2 or MR −3): 1, at any load.
3. **Otherwise, compare with the recent best.** The reference is the best Epley e1RM (§4) of the
   exercise's working and failed sets in other finished workouts that started in the
   **56 days** before this workout. The set's own e1RM is divided by that reference:
   - 85% or more: 1;
   - 60% or less: 0;
   - in between, a straight line. For example, 72.5% counts 0.5.
4. **No reference counts 1:**
   - a new exercise, or none of it in the last 56 days;
   - body-weight and reps-only exercises, which have no honest e1RM.

The e1RM includes the reps, so a light load taken for many reps can still count as hard.
For example, 40 kg × 20 has an e1RM of 66.7 kg.

Example: bench at 60 kg × 5 last week and 40 kg × 5 today. 46.7 ÷ 70 = 67%, so each of today's
sets counts 0.27.

The "sets" figure on a workout is still the number of sets logged. Only the hard-set counts use
this rule.

The app (`TrainingMath.effort`, `EffortQueries`) and the studio (`rulebook.set_effort`,
`stats.session_hard_sets`) check the same cases in `GymAppTests/Fixtures/effort_cases.json`.

## §7 Last-time values

When an exercise opens in a workout, "last time" is its most recent logged session:

1. In the **same routine day** (default), or in **any workout**. Settings controls this.
2. If the same routine day has no history for the exercise, the app uses any workout and
   tells you this.

"Same routine day" includes the days that it was copied from. A day made with *Copy from…*
keeps its source (`copiedFromDayId`). Thus a new "Full Body 1", copied from JEFIT's "1FBD 1",
gets the history of that day. It does not start empty.

## §7a Load step

The load step is the smallest change of load that an exercise usually makes. The app learns it
from the loads that you used: it is the most frequent positive gap between the different loads
(in kg, to 0.01). If two gaps are equally frequent, the smaller gap is the step. If there is no
gap, the step is 2.5 kg. For an exercise logged in lb, the step converts to the nearest 2.5 lb,
and is at least 2.5 lb. The studio uses the same tie rule. It learns the step in the unit
that you entered and ignores gaps of more than 20 kg.

## §8 Plateau swap

**Progress score.** For one session of one exercise, the score is the best estimated 1RM (§4)
of its working sets of 1–20 reps. For a reps-only exercise, it is the most reps in one set.

**Plateau.** The window *W* is 3 weeks by default (you can set 2–6). An exercise is on a
plateau when all these conditions are true:

1. You did it in 3 sessions or more in the last *W* weeks.
2. You did it 1 time or more in the *W* weeks before that.
3. The best score in the last *W* weeks is **not higher** than the best score in the *W* weeks
   before.

One more rep counts as progress. The app compares with the previous window, not with the
all-time best. Thus a return from a break does not show all exercises as plateaus at the same
time.

**Candidates.** These are exercises with the same movement pattern that share a primary muscle.
They must not be archived or marked "avoid". If gym availability is set, they must also be
available. The app puts first the exercises that you never did or did least recently. Then it
puts the exercises with the most history. It shows three or fewer, each with the reason.

**Behaviour.** The app shows the plateau at the end of the session and on the exercise screen.
It never makes a change without you.

- **Swap** replaces the exercise in the routine from the next session.
- **Keep for now** stops the check for *W* weeks.
- **Dismiss** stops the check for that exercise until you turn it on again.

The explanation always has this form: *"Best set in the last 3 weeks (3 sessions): 60 kg × 10.
Best in the 3 weeks before: 60 kg × 10."*

**Built on the phone (25 October 2026).** The window is fixed at 3 weeks for now. The app gives
the scores as an estimated 1RM, or as reps for body-weight lifts. It shows them in three places:

- on the exercise screen, under the best figure;
- in Progress → *Stalled lifts*, for the lifts of the active program;
- on Train, as a **deload prompt** when two or more program lifts are on a plateau at once: "a
  deload week: same exercises, about 10% lighter and one set fewer". The 10% is the studio's
  `deload_fraction`.

Swap, Keep for now and Dismiss are not built yet. A mid-workout swap already exists.

**Movement pattern.** Each exercise has a tag (`movementPattern`) that names the movement that
it trains. The tags are precise, so a swap gives an equivalent exercise. The full list is in
`specs/00-foundation.md`, card 0.1. Examples:

- Flat horizontal press: barbell bench, dumbbell bench, machine chest press, seated chest press.
- Incline press is a different pattern (`inclinePush`).
- Horizontal pull: seated cable row, machine row, dumbbell one-arm row.
- Squat pattern: barbell squat, hack squat, leg press.
- Knee flexion: prone leg curl, seated leg curl.

## §9 Rest timer

- Rest starts when you mark a set as done. The app stores the end of the rest as an absolute
  time. Thus a locked phone or a change of app cannot make the timer wrong.
- The duration comes from the exercise's rest setting (default 60 s). You can change or skip
  it during the rest.
- When the rest ends, a local notification with sound and vibration comes. It comes when the
  app is open, when it is in the background and when the phone is locked.

## §10 Templates, history and corrections

- A routine is a template. A finished workout is history. A change to a routine never changes
  a finished workout.
- A logged session keeps the routine's targets from that time. Thus "hit the target" stays
  correct in the history.
- A new name for an exercise applies everywhere, because it is the same exercise. Different
  equipment or a different machine is a different exercise.
- You can edit a finished workout to correct an error. Each figure from it changes to agree.
- The app archives an exercise with history. It never deletes it.
- **Caution:** the app deletes a workout with logged sets only after you confirm. It discards
  an empty workout without a question.

## §11 Estimated session time

The estimate is the median duration of your last three completed sessions of that routine
day. With fewer than three sessions, it is Σ over the sets of (40 s + the rest of that
exercise).

## §12 Feedback (UI notes)

Each feeling has one meaning only (card 9.3):

- **Set logged:** a light tap. The tick moves up and down one time.
- **All-time best:** the success haptic. The volt trophy moves in the banner and on the set.
- **1/6/12-month best:** a soft tap. The gold clock moves.
- **Rest over:** the warning haptic and the notification. The bell shakes next to the Log
  button.
- **Reps left selected:** the selection tick.

Under Reduce Motion the app shows no animations. Haptics follow the system setting.

## §13 Today's suggestion

Each exercise in a workout shows one suggested load × reps for its working sets. If an accepted
studio target is active, the app shows the studio's target instead. "Fill sets" puts the
suggestion into each planned set that is not a warm-up.

The app calculates the suggestion from the exercise's finished sessions. It uses the unit of
the last logged set and the learnt step (§7a). Reps-only and
body-weight-plus lifts get no suggestion. The app uses the first rule that applies:

1. **First session after a break** (30 days or more since you last did the lift): 90% of the
   last session's top load (80% after 90 days or more), rounded down to the step. Reps: the
   bottom of the rep range.
2. **Return after a break:** this applies when a break of 30 days or more is within the last 6
   sessions and the last top load is still below the top load from before the break. Add one
   step or 5% of the pre-break load, whichever is larger. Round up to the step. Never go above
   the pre-break load. Reps: the bottom of the range.
3. **Double progression** (as the studio's `next_target`, Plotkin 2022): if each working set at
   the last session's top load reached the top of the rep range, add one step and go back to the
   bottom of the range. If not, keep that load and aim for one rep more than the lowest of
   those sets. Never go above the top of the range.
4. **Reps in reserve:** this applies when each working set at that top load has reps in reserve
   logged and the smallest value is 2 or more. Then rule 3 moves two times as fast: two steps of
   load, or two reps more than the lowest set (never above the top of the range). If a set has
   no reps in reserve logged, rule 3 does not change. The studio's `next_target` uses the same
   rule.

The studio's plateau rule (a deload or a swap after 21 days with no increase) stays in the
studio. Its result comes to the app as an accepted target.

## §15 Rebuilding after a break (25 October 2026)

After a break, lifts fall below their peak. The app shows how much of the peak is back.

- **Peak:** the lift's best Epley e1RM (§4) of all time.
- **Now:** its best e1RM in finished workouts of the last **28 days**.
- **Shown when** the lift was trained in those 28 days and "now" is below **95%** of the peak.
  It reads "60% of 124 kg", with the peak's month and year.
- **Where:** the exercise page, under the best figure, and Progress → *Back to your best*. That
  list shows up to six lifts, furthest from the peak first.
- **The charts** of e1RM and heaviest weight draw a dashed line at the best value in the shown
  range.

## §16 Keeping the habit (25 October 2026)

Long breaks cost the most strength: in this log, 3–5 month breaks took 20–60% off the main lifts.
They start as a slide, so the app watches the slide. It uses a forgiving rule, "never miss
twice", not a streak.

- **The goal** is the active program's sessions per week.
- **One short week** (a completed week below the goal): Train shows "Never miss twice", with the
  sessions this week still needs.
- **Two or more short weeks in a row:** Train says how many, and that long breaks started like
  this.
- **A slide:** the last 4 completed weeks average 60% or less of the 8 weeks before, and those 8
  averaged 2 or more a week. Train names both figures.
- **Nothing is shown** once this week meets the goal, or before there is any history.
- **The reminder:** one notification at the usual start hour (the median of the last ten
  workouts), on the day the gap reaches 1 + ⌈7 ÷ goal⌉ days (4 days for 3 a week). Each app open
  or close moves it; it never fires in the past.

## §17 An off day (25 October 2026)

Daily strength varies, so one weak first set is information, not a failure.

- **The usual first set:** for each exercise, the e1RM of the first working (or failed) set in
  each of up to five recent sessions (in the 56 days before this workout). The median of those
  values, when there are at least three sessions.
- **Today:** once the first working set of the exercise is logged, compare its e1RM with that
  median. If it is **10% or more below**, the card says how far below, and suggests keeping
  today's weights instead of chasing a best.
- It changes no suggestion and no figure. It is advice only.

## §18 Your rest and your reps (25 October 2026)

This shows what short rest costs, using your own set times.

- **A pair:** two back-to-back working sets of one exercise in one workout, at the same load and
  unit, both completed in the app.
- **Rest:** the time between the two completions. It includes the second set itself, so it reads
  a little long.
- **Leaving out:** pairs more than 10 minutes apart, because that is a break, not rest.
- **Groups:** under 90 s, 90 s to 3 min, and over 3 min. For each group, the mean change in reps
  on the second set, as a share of the first.
- **When it shows:** Progress shows the card when there are 10 pairs or more.

## §19 Starting without opening the app (25 October 2026)

- **Control Center control "Start workout"** (it can also go on the Action button). It opens the
  app and starts the active program's next day. If a workout is in progress, it brings that
  workout up instead.
- **Lock-screen widget** (circular or rectangular). A tap opens `bashigym://start`, which does
  the same.
- These do not show figures, such as the next day's name. A widget can read the app's data only
  through an App Group, and the free signing profile has no App Group. Add the App Group after
  moving to a paid developer account, or after Xcode regenerates the profiles with App Groups.

## §20 Rest on the lock screen (25 October 2026)

The rest Live Activity shows these, without opening the app:

- **On the lock screen:** a large countdown, a ring that empties as the rest runs down, the next
  exercise and set, and the buttons **+30s**, **Skip** and **Log**.
- **In the Dynamic Island:**
  - compact: the ring and the countdown;
  - minimal: the ring;
  - expanded: the same buttons.
- **The buttons** run in the app's process and do exactly what the workout screen's buttons do.
  For example, +30s moves the rest end and the rest alert. When the rest is over, only Log
  remains.
- **The ring needs the rest's start time.** An activity started by an older build shows the timer
  icon instead.

