# Redesign: build plan and proof

Each card ships alone, keeps every existing test passing and adds its own. The workout flow
is guarded by the UI tests throughout (GymAppUITests), extended in R.1 with tap-count
assertions. Order: navigation gaps first (the complaint), then the workout card (most used),
then the rest.

| Card | What | Proof |
|---|---|---|
| **R.0** | Usage counts on the device (table `usageCount`, Settings → Data → export). Prototype of Train → day → exercise in a separate preview target for review. | Counts test; owner reviews the prototype |
| **R.1** | Tap-count UI tests for the ten tasks in 02-navigation.md, run now to record the "before" numbers | The numbers, committed |
| **R.2** | Tokens: tools/build_tokens.py writes Theme tokens and studio tokens.css from design/tokens.json; a check fails on hand edits | Generator test; check.sh step |
| **R.3** | Plan navigation: day rows and Train's next-day rows open the exercise in plan context (targets in place, Swap, Remove); drag to reorder without Edit | UI tests for gaps 1–4; tap counts |
| **R.4** | Workout card order (03 moment 2): set and what-to-beat above the fold, rare items collapsed, exercise name opens its page | UI tests; screenshot before/after on a small and a large phone |
| **R.5** | End of workout as a sentence and records first; past workout without tiles | Screenshot; existing summary tests |
| **R.6** | Progress as three summary blocks with drill-downs; Recaps and Reports as visible rows | UI test reaches every old detail in ≤ 2 taps |
| **R.7** | Spacing, radius and type moved onto tokens across the app (mechanical) | Token check: no literal paddings, radii or fixed sizes left |
| **R.8** | Studio on tokens.css; overview's three blocks matching the phone | Browser check; token check on CSS |
| **R.9** | Accessibility pass at the largest Dynamic Type size and with VoiceOver on the four moments; fixes | Screenshots at AX5; VoiceOver walkthrough notes |
| **R.10** | Close: before/after tap counts, gym timing, new-user test, HANDOFF and README | The numbers below |

## Proof

- **Tap counts:** R.1 records today's counts from UI tests; R.10 re-runs them. Targets in
  02-navigation.md.
- **Gym timing (owner):** time to log a set and time to find what to beat, before R.4 and
  after, three sets each, phone in one hand.
- **New users:** two people unfamiliar with the app: start the day, log three sets, find the
  deadlift's best, swap an exercise, find last week's sessions. Unaided; note every hesitation.
- **Tokens:** after R.7–R.8 a script finds no colour, font size, padding or radius literal
  outside the generated files (baseline in 04-design-system.md).
- **Accessibility:** every screen usable at the largest accessibility text size; VoiceOver
  reads the set, the best and the Log action in that order.

## Waiting on the owner

1. Approval of steps 1–5 (or changes).
2. The screen recording of a real session (step 1's hesitation notes).
3. A yes for R.0's usage counts and the prototype target (a project.pbxproj change, like the
   UI-test target).

## Decided with the prototypes (20 October)

Interactive prototypes: https://claude.ai/artifact/Hncqj8wMbWEyKeLq5QKBzt (private).

- **Best last time.** When a lift has no 12-, 6- or 1-month best because it was not done in
  the window (the deadlift, last done 29 Jul 2025), the workout shows the best set of its
  last session as the nearer target beside the all-time best, each with its own beat table.
  Rulebook §5b gains this case; it goes into R.4.
- **A richer end of workout:** headline of bests and lifts up; duration, sets, volume against
  last time; each lift with a today-against-last bar, est. 1RM change and share of its
  all-time best, expanding to sets and volume with a link to the exercise; muscles worked;
  links to the full workout and the week. Replaces R.5's scope.
- **Name and logo: Bashi Gym.** The app's display name, icon and Studio title become Bashi Gym
  (code, bundle id and repo stay GymApp). New card **R.11**: display name, app icon from the
  mark on the brand board, studio title and favicon.
