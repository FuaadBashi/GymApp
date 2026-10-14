# Training rulebook

The definitions every figure in the app is computed from. Where the code and this document
disagree, that is a bug report. These rules exist because a polished chart that compares
incompatible numbers is worse than no chart.

## §1 Units and stored loads

1. A load is stored exactly as entered: an integer count of hundredths in the unit used, plus
   the unit. 62.5 kg is stored as `6250, kg`; 45 lb as `4500, lb`.
2. Converted values are computed for display and aggregates and **never stored**. Storing a
   conversion turns 45 lb into 44.99 lb on the way back.
3. 1 lb = 0.45359237 kg, exactly.
4. Aggregates (volume, PR comparisons, plateau checks) convert every load to kg first, then
   display in the preferred unit.
5. Each exercise remembers the unit it was last logged in, so lb dumbbells and kg machines can
   coexist.

## §2 What a logged load means

Every exercise has a **load mode** that says what its logged number means. The mode is fixed
once the exercise has history, because changing it would change what past sets mean.

| Load mode | Typical exercises | The number you log | Load used in calculations | Volume |
|---|---|---|---|---|
| `total` | Barbell (including the bar), machine, cable, Smith, plate | The whole load | As logged | × 1 |
| `perHand` | Two dumbbells at once | One dumbbell | As logged | × 2 |
| `perSide` | One-arm row, single-leg press | One side; reps are per side | As logged | × 2 |
| `bodyweightPlus` | Pull-up, dip, chin-up, assisted machines | Added weight, or assistance as a negative | Body weight + logged figure, never below 0. Body weight is the latest entry on or before the workout date | × 1 |
| `repsOnly` | Push-up, knee raise, plank | Nothing | None | Excluded |

Each machine is its own exercise and is never compared with another. A held plate on a
partial-bodyweight movement (weighted crunch, back extension) is `total`: the plate is the
only load that changes.

With no body-weight entry, whole-body exercises fall back to reps only. The app says so
rather than inventing a figure.

## §3 Set types

| Type | Volume | Hard set (for muscle counts) | PRs and plateau |
|---|---|---|---|
| Working (default) | Yes | 1 | Yes |
| Warm-up | No | 0 | No |
| Drop set (a working set plus its drops) | Every segment counts | 1 for the whole drop set | Only the first segment |

A drop set is stored as its first segment (a working or failed row) followed by one `drop` row
per further segment. That is how "1 for the whole drop set" and "only the first segment" are
computed: `drop` rows add volume and nothing else.
| Failed or partial | Reps actually done | 1 | Reps actually done |

A superset is a grouping of exercises, not a set type, and changes no calculation.

**Effort labels (11 October):** Max rep means 0 reps in reserve. MR −1, MR −2 and
MR −3 mean 1, 2 and 3 reps left in the tank. Store this separately from actual reps,
RPE and set type. Max rep does not imply a failed repetition. Deload, injury and form
are independent annotations that may coexist with an effort label. Warm uses warm-up.
These annotations do not change the existing calculation rules: 60 kg × 8 at MR −1
still uses 8 actual reps and 480 kg of volume, not 9 inferred reps. Notes and labels
belong to that particular set/session and are not copied into a new workout as facts.

## §3a Warm-up ramps

Built on request per exercise (card 7.7) before the first unlogged working set, from that
set's load and unit. The day's first exercise, when it is a barbell squat, hinge or
horizontal push, gets the **strength ramp**: the bar × 10 (only when working at 30 kg / 65 lb
or more), then 50% × 5, 70% × 3, 85% × 1. Every other loaded exercise gets the **short ramp**:
50% × 8, 80% × 3. Loads round to the nearest step the exercise moves in (§5a's learnt step,
default 2.5); a load that doesn't climb, reaches the working load, or is at or below the bar
in the strength ramp is dropped. Warm-ups are `warmUp` sets, so they never count (§3).

## §4 Estimated 1RM

- Epley: `load × (1 + reps / 30)`. One rep gives the load itself.
- Shown as a PR only for sets of 1–12 reps; above that the estimate is too loose to present.
- Plateau checks (§8) use it for 1–20 reps, where consistency matters more than accuracy.

## §5 Personal records

Per exercise, from working and failed sets (never warm-ups or `drop` segments), and never for
`bodyweightPlus` or `repsOnly` exercises. All are computed from history on read, so
correcting a set can create or remove a PR.

- **Heaviest load** at any reps.
- **Best estimated 1RM** (§4).
- **Rep PR:** most reps at a given load.
- **Best session volume.**

## §5a Time-window bests

The personal best that badges, banners and the "beat my best" table use is the **best
estimated 1RM** (§4, from the sets §5 counts). A newly logged set is judged against every
earlier counted set of the exercise, including sets already logged in the same workout:

1. **All-time best:** its estimated 1RM beats the best so far by more than 0.01 kg.
2. Otherwise, **only if training broke off** for 30 days or more at some point since the
   all-time best was last reached (including the gap up to this set), it may be a
   **window best**: the longest of the last 12, 6 and 1 months (365, 182 and 30 days) whose
   best is below the all-time best and which it beats by more than 0.01 kg.
3. Otherwise it is not a best. A first-ever set has nothing to beat.

So a lift trained without a month off only ever shows all-time bests, and after a long
break the comeback earns smaller bests on the way back. Heaviest load, rep PRs and best
session volume (§5) are still recorded; they don't drive badges.

## §6 Volume and sets per muscle

- **Volume** = Σ (calculation load × reps) over volume-counting sets (§2, §3), in kg. JEFIT
  defines volume differently, so the figures will not match.
- **Hard sets per muscle**: each hard set (§3) counts 1 for each primary muscle and 0.5 for each
  secondary muscle.
- **Week**: starts on the day set in Settings (default Sunday). A workout belongs to the local
  date it started, even if it runs past midnight.

## §7 Last-time values

When an exercise opens in a workout, "last time" is its most recent logged session:

1. In the **same routine day** (default), or in **any workout**, per Settings.
2. If the same routine day has no history for it, fall back to any workout and label it so.

"Same routine day" includes the days it was copied from. A day built with *Copy from…*
remembers its source (`copiedFromDayId`), so a new "Full Body 1" copied from JEFIT's "1FBD 1"
picks up that day's history instead of starting blank.

## §8 Plateau swap

**Progress score.** For one session of one exercise, the score is the best estimated 1RM
(§4) among its working sets of 1–20 reps. For reps-only exercises, it is the most reps in a
single set.

**Plateau.** With window *W* (default 3 weeks, settable 2–6), an exercise has plateaued when
all of these hold:

1. it was done in at least 3 sessions within the last *W* weeks;
2. it was done at least once in the *W* weeks before that;
3. the best score in the last *W* weeks is **not higher** than the best score in the *W*
   weeks before.

A single extra rep counts as progress. Comparing against the previous window, not the
all-time best, means returning from a break does not flag everything at once.

**Candidates.** Exercises with the same movement pattern that share a primary muscle and are not
archived or marked "avoid". If gym availability is tagged, they must also be available. Ranked
by never or longest since done, then most history. At most three, each with the reason.

**Behaviour.** Shown at the end of the session and on the exercise screen, never applied
automatically.

- **Swap** replaces the exercise in the routine from the next session.
- **Keep for now** snoozes the check for *W* weeks.
- **Dismiss** turns it off for that exercise until re-enabled.

The explanation always reads like: *"Best set in the last 3 weeks (3 sessions): 60 kg × 10.
Best in the 3 weeks before: 60 kg × 10."*

**Movement pattern.** A tag on each exercise (`movementPattern`) naming the movement it
trains, fine enough that swaps are genuinely equivalent. The full list is in
`specs/00-foundation.md`, card 0.1. Examples:

- Flat horizontal press: barbell bench, dumbbell bench, machine chest press, seated chest press.
- Incline press is a separate pattern (`inclinePush`).
- Horizontal pull: seated cable row, machine row, dumbbell one-arm row.
- Squat pattern: barbell squat, hack squat, leg press.
- Knee flexion: prone leg curl, seated leg curl.

## §9 Rest timer

- Rest starts when a set is marked done. Its end is stored as an absolute time, so locking
  the phone or switching apps cannot make it drift.
- Duration comes from the exercise's rest setting (default 60 s) and can be changed or skipped
  mid-rest.
- When rest ends, a local notification with sound and vibration fires whether the app is
  open, in the background or the phone is locked.

## §10 Templates, history and corrections

- A routine is a template; a finished workout is history. Editing a routine never changes a
  finished workout.
- A logged session records the routine's targets at that time, so "hit the target" stays
  true historically.
- Renaming an exercise renames it everywhere; it is the same exercise. Moving to different
  equipment or a different machine is a different exercise.
- Finished workouts can be edited, since typos happen, and every derived figure follows.
- Exercises with history are archived, never deleted.
- A workout with logged sets is deleted only after explicit confirmation. An empty one is
  discarded silently.

## §11 Estimated session time

The median duration of your last three completed sessions of that routine day. With fewer
than three, use Σ over sets of (40 s + that exercise's rest).

## §12 Feedback (UI notes)

One vocabulary, so a feeling always means the same thing (card 9.3):

- **Set logged:** a light tap; the tick bounces.
- **All-time best:** the success haptic; the volt trophy bounces in the banner and on the set.
- **1/6/12-month best:** a soft tap; the gold clock bounces.
- **Rest over:** the warning haptic and notification; the bell wiggles beside the Log button.
- **Reps left chosen:** the selection tick.

Animations are skipped under Reduce Motion; haptics follow the system setting.
