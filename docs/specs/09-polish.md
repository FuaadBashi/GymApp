# Phase 9: Visual polish

**Specified 14 October 2026.** Direction chosen: the current near-black and volt-lime look,
polished, not replaced. The studio follows the same palette.

Principles:

- **Glass only on floating controls** (tab bar, toolbars, the workout bottom bar, the
  mini-player), never on data, per Apple's Liquid Glass guidance.
- **Colour belongs to data and meaning:** volt for progress and all-time bests, gold for
  1/6/12-month bests, orange for warnings; text in greys.
- **Motion only where something changed**, and Reduce Motion is respected everywhere.

## Card 9.1: Theme and surfaces

- `Theme` gains tokens: background (near-black, not #000), three surface levels, separator,
  text primary/secondary/tertiary, volt, gold, orange; every view uses tokens, no literal
  colours. Cards get the layered surfaces and consistent corner radii.
- Numbers use a single style: rounded-width monospaced digits for weights, reps, timers.
- Floating controls adopt `glassEffect` in a `GlassEffectContainer`.
- **Done when:** a screenshot of each tab before and after.

## Card 9.2: Rolling numbers

- `contentTransition(.numericText())` with an animation on: set load and reps in the editor,
  rest timer, workout volume and set count, Progress tiles, recap tiles.

## Card 9.3: Animated icons and haptics

- `symbolEffect` on: the set checkmark (bounce on log), the record trophy (bounce on a
  best), the rest bell at the end of rest. `sensoryFeedback`: light impact on log, success
  on an all-time best, soft on a window best, warning when rest ends. One vocabulary,
  documented in the rulebook's UI notes.

## Card 9.4: Charts that draw in

- Progress, exercise and recap charts animate in on first appear; the tapped point (6.4)
  lifts with a callout. Off under Reduce Motion.

## Card 9.5: Studio restyle

- The studio's CSS adopts the same tokens (near-black base, grey text, volt/gold/orange for
  data), tabular numbers everywhere and rounded figures for tiles, and a registered ECharts
  theme built from the tokens. The Mac's system font is used instead of Inter: the studio
  runs offline, and the system font is the app's own family.

## Card 9.6: Phase close

Screenshots of every tab and the studio pages into `docs/screenshots/`, README.
