# Redesign step 4: one design system for both apps

The values are in [design/tokens.json](../../design/tokens.json). After approval, a small
generator (tools/build_tokens.py, standard library only) will write the Swift tokens into
`Theme` and a `tokens.css` file for the studio. A check will fail if you edit either output by
hand.

## The current state (20 October)

| | Phone (Swift) | Studio (CSS/JS) |
|---|---|---|
| Colours | 1 literal colour outside Theme, 20 opacities chosen one at a time | 45 hex values, copied by hand from Theme |
| Type | 264 direct uses of text styles, 4 fixed point sizes | 10 different px sizes |
| Spacing | 90 literal paddings, mostly 14, 10, 16, 8, 12, 6 | Chosen one at a time |
| Corner radius | 11 values (2–30) | 10, 16 and 99 |
| Motion | Snappy and spring animations in some places | One transition |

These numbers are the baseline for the token check in step 6.

## Tokens

- **Colour:** three surfaces on a base that is almost black. Volt shows progress and all-time
  bests. Gold shows 1/6/12-month bests. Orange shows warnings, red shows errors and yellow
  shows notes. Each body region has one hue. Text uses three greys. The colours do not change
  from today; only their source changes to one file.
- **Type:** six roles (display, title, heading, body, secondary, caption) and two figure styles
  (rounded, fixed-width digits). On iOS each role uses a text style, so Dynamic Type works. The
  studio uses the same sizes in px.
- **Space:** 2, 4, 8, 12, 16, 24, 32. Today's 14 becomes 12; today's 10 and 6 become 8 (or 4).
- **Radius:** chip 8, row 12, card 16, sheet 24, floating bar 30, pill.
- **Sizes:** 44 pt minimum tap target, 56 pt for workout controls, 54 pt primary button.
- **Motion:** press 0.15 s, change 0.25 s, navigate 0.35 s (spring). Under Reduce Motion, each
  motion becomes a 0.15 s crossfade.

## Components (the same names in both apps)

| Component | What it is | Phone today | Studio today |
|---|---|---|---|
| **Figure** | One number with its unit and caption. One figure per screen is the largest. | Theme.number, the hero on the exercise page | .hero .big |
| **Row** | Title, second line, value at the end, chevron when it opens a screen | Many list rows | .row |
| **Section** | A title in sentence case, with an optional "See all" | Mixed: small capitals and headlines | h2 |
| **Chip** | A status in one word with a colour (progressing, plateau, best) | MuscleTags, best badge | .chip |
| **Set row** | Label, today's load × reps large, last time small, tick | SetRow | Set pills in tables |
| **Best tile** | A best, the set that made it, the difference in words | BestHintLine tiles | — |
| **Suggestion** | "Today: 95 kg × 6", the reason, Fill | TodaySuggestion | Next session block |
| **Disclosure** | One line that opens in place to show rare content | DisclosureGroup in records | details |
| **Floating bar** | Glass, at the bottom, the one action | Workout bar, mini player | Toolbar |
| **Sheet** | A focused task above its context | Many | Drawer |

## Vocabulary (one word for one thing, in both apps)

| Use | Do not use |
|---|---|
| Workout | Session (in the UI), log |
| Day (of a program) | Routine, template |
| Set, warm-up, drop set, failed | Working set (write "set") |
| Estimated 1RM ("est. 1RM") | e1RM in the UI; the studio tables keep e1RM |
| Best; all-time best; 12-month best | PR, record (except in the Records list) |
| Last time | Previous |
| Today's suggestion | Target, next (except the studio's "Next session") |
| Reps in reserve | RIR in the UI |

## Motion that shows where a tap goes

- A row opens with a push (navigate). An exercise that you open during a workout comes up as a
  sheet from its name.
- The tick of a logged set moves up and down one time. Numbers roll (change). A best banner
  comes down from the top.
- The floating bar changes shape from Log to Rest. It does not jump.
- Under Reduce Motion, all of these become crossfades.

## References

Apple's Human Interface Guidelines, and the WWDC 2025 sessions "Meet Liquid Glass" and "Get to
know the new design system" ([session 284](https://developer.apple.com/videos/play/wwdc2025/284)):

- Glass only on the navigation and control layer.
- Standard components, so they get glass automatically.
- A floating tab bar that becomes smaller when you scroll, with an accessory above it (the mini
  player).

For comparison: Strong for logging with one tap, Apple Fitness for summary rings and
one-line sentences, Apple Health for drill-down from summary to detail, Things and Linear for
calm, dense lists with one accent colour.
