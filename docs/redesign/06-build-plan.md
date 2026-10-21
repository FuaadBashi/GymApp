# Redesign: build plan and proof

You can ship each card alone. Each card keeps all existing tests passing and adds its own
tests. The UI tests (GymAppUITests) protect the workout flow from start to end. Card R.1 adds
tap-count checks to them.

The order: first the navigation gaps (the owner's complaint), then the workout card (the
screen that you use most), then the other screens.

| Card | Work | Proof |
|---|---|---|
| **R.0** | Usage counts on the device (table `usageCount`, Settings → Data → export). A prototype of Train → day → exercise, in a separate preview target, for review. | Counts test; the owner reviews the prototype |
| **R.1** | UI tests that count the taps of the ten tasks in 02-navigation.md. Run them now to record the "before" numbers. | The numbers, committed |
| **R.2** | Tokens: tools/build_tokens.py writes the Theme tokens and the studio's tokens.css from design/tokens.json. A check fails on a change by hand. | Generator test; a check.sh step |
| **R.3** | Plan navigation: day rows and Train's next-day rows open the exercise in the plan context (targets in place, Swap, Remove). Drag to reorder with no Edit mode. | UI tests for gaps 1–4; tap counts |
| **R.4** | The order of the workout card (moment 2 in 03): the set and what to beat above the fold, rare items closed, the exercise name opens its page. "Best last time" (see below). | UI tests; screenshots before and after, on a small phone and a large phone |
| **R.5** | The end of the workout (see below); the past workout without tiles. | Screenshots; the existing summary tests |
| **R.6** | Progress as three summary blocks with drill-downs. Recaps and Reports as visible rows. | A UI test reaches each old detail in 2 taps or fewer |
| **R.7** | Spacing, radius and type on tokens across the app (mechanical work). | Token check: no literal padding, radius or fixed size remains |
| **R.8** | The studio on tokens.css; the three overview blocks the same as the phone. | Browser check; token check on the CSS |
| **R.9** | Accessibility check at the largest Dynamic Type size and with VoiceOver, on the four moments; fixes. | Screenshots at AX5; notes from a VoiceOver walk-through |
| **R.10** | Close: tap counts before and after, gym timing, test with new users, HANDOFF and README. | The numbers below |
| **R.11** | The name and logo Bashi Gym (see below). | Screenshot of the home screen and the studio |

## Proof

- **Tap counts:** R.1 records today's counts with UI tests. R.10 runs them again. The targets
  are in 02-navigation.md.
- **Gym timing (the owner):** measure the time to log a set and the time to find what to beat.
  Do this before R.4 and after it: three sets each time, with the phone in one hand.
- **New users:** two people who do not know the app do these tasks: start the day, log three
  sets, find the best of the deadlift, swap an exercise, find last week's sessions. They get no
  help. Write down each hesitation.
- **Tokens:** after R.7 and R.8, a script finds no colour, font size, padding or radius literal
  outside the generated files. The baseline is in 04-design-system.md.
- **Accessibility:** you can use each screen at the largest accessibility text size. VoiceOver
  reads the set, the best and the Log action, in that order.

## Waiting on the owner

1. Approval of steps 1–5, or changes to them.
2. The screen recording of a real session (for the hesitation notes in step 1).
3. A "yes" for R.0's usage counts and the prototype target. The target changes
   project.pbxproj, as the UI-test target did.

## Decisions from the prototypes (20 October)

The interactive prototypes are at https://claude.ai/artifact/Hncqj8wMbWEyKeLq5QKBzt (private).

- **Best last time.** Some lifts have no 12-, 6- or 1-month best, because you did not do them
  in that time. The deadlift is an example: you last did it on 29 July 2025. For such a lift,
  the workout shows the best set of its last session as the nearer target, next to the all-time
  best. Each one has its own beat table. Rulebook §5b gets this case. It is part of R.4.
- **A more detailed end of workout.** The screen shows:
  - a headline with the bests and the number of lifts that went up;
  - duration, sets and volume, with the difference from last time;
  - for each lift, a bar of today against last time, the change in estimated 1RM, and today as
    a share of the lift's all-time best. A tap opens the sets and the volume, with a link to
    the exercise;
  - the muscles that you trained;
  - links to the full workout and to the week.

  This replaces the scope of R.5.
- **Name and logo: Bashi Gym.** The display name, the icon and the studio's title become
  Bashi Gym. The code, the bundle ID and the repository keep the name GymApp. Card **R.11**:
  the display name, the app icon from the mark on the brand board, the studio's title and
  favicon.

## Status (21 October 2026)

R.0–R.11 are complete and pushed. Tap counts before and after: [tap-counts.md](tap-counts.md).
Two targets were missed at first and met on 21 October: swap during a workout (now 2) and reorder a day (now 2).
Still owed by the owner: the gym timing (log a set, find what to beat, one hand) and a test with
two people who do not know the app. These need people, not code.
