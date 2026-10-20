# Redesign step 5: wireframes

Low fidelity: these drawings show only position, order and weight. `[ ]` is a button, `›`
opens a screen, `▸` opens in place, `━━` is the floating glass bar. The sizes come from
design/tokens.json. Compare them with the current screens in [screens/](screens/). The
interactive prototypes of 20 October go further; see [06-build-plan.md](06-build-plan.md).

## Train

```
┌──────────────────────────────────────┐
│ Programs                          +  │
│ Train                    (display)   │
│                                      │
│ FULL BODY 3 · next up                │
│ 8 exercises · ~28 min · last 13 Oct  │
│ ──────────────────────────────────── │
│ Barbell Deadlift        95 × 6     › │  ← today's suggestion; row opens the exercise
│ Barbell Incline Bench   40 × 8     › │
│ Machine Assisted Pull…  BW−54 × 6  › │
│ …                                    │
│ [            Start            ]      │  ← one primary action
│                                      │
│ Studio: 2 suggestions ▸              │
│ Other days                           │
│ Full Body 1 · last 15 Oct          › │
│ Full Body 2 · last 18 Oct          › │
│ ━━ mini player (when a workout runs)━│
│ ━━━━━━━━━━━━ tab bar ━━━━━━━━━━━━━━━│
└──────────────────────────────────────┘
```

## Exercise in the plan (new: from a day or Train)

```
┌──────────────────────────────────────┐
│ ‹ Full Body 3                    ⋯   │
│ Barbell Deadlift          (title)    │
│ Hamstrings · Barbell                 │
│ ┌ In Full Body 3 ─────────────────┐  │
│ │ 4 sets · 6–10 reps · rest 1:00 ›│  │  ← targets, edited in place
│ │ [Swap]                [Remove]  │  │
│ └─────────────────────────────────┘  │
│ Today's suggestion: 95 × 6 ▸ why     │
│ [ demonstration, full width ]        │
│ Form cues                        +   │
│ Best est. 1RM  170 kg   (figure XL)  │
│ chart ─────────────                  │
│ History ›   Records ›   Notes ›      │
└──────────────────────────────────────┘
```

## Workout, list (between sets)

```
┌──────────────────────────────────────┐
│ ⌄ Full Body 3  17:03   ◔1/9  ◎  ⋯ [Finish]
│ ┌ Barbell Deadlift ›        2 of 3 ┐ │  ← name opens the exercise as a sheet
│ │ SET  KG    REPS          LAST  ✓ │ │
│ │ W    80    10            80×10 ✓ │ │
│ │▌1    80     8            80×8  ○ │ │  ← selected
│ │ 2   100     6           100×6  ○ │ │
│ │ This set 101 kg · best 170 kg ›  │ │  ← one line; tap for both bests and the table
│ │ Today: 95 × 6          [Fill]    │ │
│ │ ┌───────┐  ┌───────┐             │ │
│ │ │− 80 +│  │ − 8 + │  (56 pt)     │ │  ← bottom half, thumb reach
│ │ └───────┘  └───────┘             │ │
│ │ Reps left  Max 1 2 3             │ │
│ │ Demonstration ▸  Cues ▸  Note ▸  │ │  ← rare things collapsed
│ └──────────────────────────────────┘ │
│ Barbell Incline Bench   0/3        › │
│ Machine Assisted Pull-Up 0/2       › │
│ ━━[ Log set 1 · 80 kg × 8 ]━━━━━━━━━│
└──────────────────────────────────────┘
```

During rest, the bar becomes `( 1:24 ) Rest · Next: set 2 · 100 × 6  −15 +15 [Skip]`. The
content has a bottom inset equal to the bar, so no item is below the bar.

## Workout, focus

```
┌──────────────────────────────────────┐
│ Barbell Deadlift            (title)  │
│ Set 2 of 3                           │
│                                      │
│        100 kg × 6        (figure XL) │
│ This set 133 kg · best 170 kg ›      │
│ Today: 95 × 6                [Fill]  │
│ ┌─────────┐   ┌─────────┐            │
│ │ − 100 + │   │  − 6 +  │            │
│ └─────────┘   └─────────┘            │
│ Reps left  Max 1 2 3                 │
│ Done: W 80×10 ↑ · 1 80×8 =           │
│ Demonstration ▸ Cues ▸ Note ▸        │
│ ━━[ Log set 2 · 100 kg × 6 ]━━━━━━━━│
└──────────────────────────────────────┘
```

## End of workout

```
┌──────────────────────────────────────┐
│ Workout complete                     │
│ 2 bests today            (figure XL) │
│ 🏆 Deadlift 120 × 6 · all-time best   │
│ 🏆 Incline bench 45 × 8 · 12-month    │
│ 52 min · 17 sets · 6,240 kg          │  ← one sentence, not tiles
│ Against last time                    │
│ Deadlift          ↑ +6 kg est. 1RM › │
│ Incline bench     =                › │
│ …                                    │
│ Muscles worked ▸                     │
│ [ Done ]           Back to workout   │
└──────────────────────────────────────┘
```

## History and a past workout

```
History                         Past workout
┌───────────────────────────┐   ┌───────────────────────────┐
│ History                   │   │ ‹ History           Edit  │
│ ‹ October 2026 ›          │   │ Full Body 2               │
│ calendar (as today)       │   │ Sun 18 Oct · 29 min       │
│ This week 1 of 3          │   │ 2 bests · 11 sets ·       │
│ Week of 18 Oct · 2,610 kg │   │ 2,610 kg (+225 vs last)   │
│ Full Body 2  Sun ·29 min ›│   │ Preacher Curl Machine   › │
│ …                         │   │  1 36×5 🏆  2 24×7          │
│ Recaps ›                  │   │ …                         │
└───────────────────────────┘   └───────────────────────────┘
```

## Progress (weekly review)

```
┌──────────────────────────────────────┐
│ Progress                             │
│ This week                            │
│ 1 of 3 sessions · 11 sets · 29 min   │
│ ▁▃▅▇▅▃▂▁▃▅▆▂  12 weeks             › │
│ Muscles   [This week|Last week]      │
│ (body map, front and back)         › │
│ Lifts                                │
│ 🏆 Preacher curl 42 kg · 18 Oct     › │
│ ↑ Vertical pull +20.8%             › │
│ ↓ Horizontal pull −7.4%            › │
│ Reports ›            Body & steps ›  │
└──────────────────────────────────────┘
```

## Exercises, Settings, lock screen

Their structure does not change. The exercise list and Settings already agree with the
system. The lock screen keeps the countdown, the next set and Log. These screens get the
tokens (type, spacing, radius).

## Studio overview (Mac)

```
┌ sidebar ─┬ toolbar: Overview                     Search ⌘K ┐
│ Overview │ Workouts this week  1   (figure XL)  2,610 kg   │
│ Exercises│ 4 wk streak · 0 plateaus · Full Body 2, 18 Oct  │
│ Muscles  │ ┌ This week ──┐ ┌ Muscles ────┐ ┌ Lifts ──────┐ │
│ History  │ │ sparkline   │ │ body map    │ │ bests/moves │ │  ← same three blocks
│ …        │ └─────────────┘ └─────────────┘ └─────────────┘ │     as the phone's Progress
│          │ Next session (suggestion rows, same component)  │
└──────────┴─────────────────────────────────────────────────┘
```
