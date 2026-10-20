# Redesign step 4: one design system for both apps

The values live in [design/tokens.json](../../design/tokens.json). After approval a small
generator (tools/build_tokens.py, standard library only) writes the Swift tokens into
`Theme` and a `tokens.css` the studio loads; a check fails if either is edited by hand.

## Where things stand (20 October)

| | Phone (Swift) | Studio (CSS/JS) |
|---|---|---|
| Colours | 1 literal outside Theme, 20 ad-hoc opacities | 45 hex values, copied by hand from Theme |
| Type | 264 direct text-style uses, 4 fixed point sizes | 10 different px sizes |
| Spacing | 90 literal paddings, mostly 14, 10, 16, 8, 12, 6 | Ad hoc |
| Corner radius | 11 values (2–30) | 10, 16 and 99 |
| Motion | Snappy and spring in a few places | One transition |

These are the baseline for the "everything comes from the token file" check in step 6.

## Tokens

- **Colour:** three surfaces above a near-black base; volt for progress and all-time bests;
  gold for 1/6/12-month bests; orange for warnings, red for errors, yellow for notes; one
  hue per body region. Text in three greys. Unchanged in look from today; only now from one
  file.
- **Type:** six roles (display, title, heading, body, secondary, caption) plus two figure
  styles (rounded, fixed-width digits). On iOS they map to text styles, so Dynamic Type works;
  the studio uses the same sizes in px.
- **Space:** 2, 4, 8, 12, 16, 24, 32. Today's 14, 10 and 6 round to 12, 8 and 8 (or 4).
- **Radius:** chip 8, row 12, card 16, sheet 24, floating bar 30, pill.
- **Sizes:** 44 pt minimum tap target, 56 pt for workout controls, 54 pt primary button.
- **Motion:** press 0.15 s, change 0.25 s, navigate 0.35 s spring; under Reduce Motion
  everything is a 0.15 s crossfade.

## Components (same names in both apps)

| Component | What it is | Phone today | Studio today |
|---|---|---|---|
| **Figure** | One number with unit and caption; one dominant per screen | Theme.number, hero on exercise page | .hero .big |
| **Row** | Title, secondary line, trailing value, chevron when it opens something | Many list rows | .row |
| **Section** | Sentence-case title with optional "See all" | Mixed: small caps and headlines | h2 |
| **Chip** | Status in a word with a colour (progressing, plateau, best) | MuscleTags, best badge | .chip |
| **Set row** | Label, today's load × reps large, last time small, tick | SetRow | set pills in tables |
| **Best tile** | A best, the set behind it, the gap in words | BestHintLine tiles | — |
| **Suggestion** | "Today: 95 kg × 6", reason, Fill | TodaySuggestion | Next session block |
| **Disclosure** | One line that expands in place for rare content | DisclosureGroup in records | details |
| **Floating bar** | Glass, bottom, the one action | Workout bar, mini player | Toolbar |
| **Sheet** | Focused task over context | Many | Drawer |

## Vocabulary (one word for one thing, both apps)

| Use | Not |
|---|---|
| Workout | Session (in the UI), log |
| Day (of a program) | Routine, template |
| Set, warm-up, drop set, failed | Working set (just "set") |
| Estimated 1RM ("est. 1RM") | e1RM in the UI; e1RM stays in the studio tables |
| Best; all-time best; 12-month best | PR, record (except the Records list) |
| Last time | Previous |
| Today's suggestion | Target, next (except studio's "Next session") |
| Reps in reserve | RIR in the UI |

## Motion that shows where a tap leads

- A row opens by pushing (navigate); an exercise opened mid-workout rises as a sheet from its
  name.
- A logged set's tick bounces once; numbers roll (change); a best banner drops in.
- The floating bar morphs between Log and Rest rather than swapping.
- Reduce Motion: all of these become crossfades.

## References used

Apple's Human Interface Guidelines, and WWDC 2025 "Meet Liquid Glass" and "Get to know the new
design system" ([session 284](https://developer.apple.com/videos/play/wwdc2025/284)): glass on
the navigation and control layer only, standard components so they adopt it, tab bar
floating and minimising on scroll, an accessory above it (the mini player). For comparison:
Strong for one-tap logging, Apple Fitness for summary rings and one-line sentences, Apple
Health for summary → detail drill-down, Things and Linear for calm, dense lists with one
accent.
