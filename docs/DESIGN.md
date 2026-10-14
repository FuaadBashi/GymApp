# Design rules

How GymApp and GymApp Studio should look and behave. Every new screen follows these; a change
that breaks one needs a reason written next to it. Written 14 October 2026 from research into
what makes app interfaces read as machine-made, and kept inside the owner's chosen direction:
simple, near-black, one volt accent.

## What we keep

- Near-black base, three surface levels, one accent (volt). Gold only for 1/6/12-month bests,
  orange for warnings, red for errors. Text in system greys. All colours come from `Theme`.
- The system font (SF Pro; rounded, fixed-width digits for figures via `Theme.number`).
- Glass only on floating controls. No gradients, glows, gradient text or emoji icons.

## What to avoid (the tells)

1. **Everything in identical cards.** A rounded card is for a thing you can act on or that
   must stand apart; a list of facts is a list with dividers, not a stack of boxes.
2. **The same small grey capitals heading on every block.** Use them sparingly, for sections
   of a long page; otherwise let the content's own title lead.
3. **Equal grids of number tiles.** A screen has one dominant figure or action; supporting
   figures are smaller and fewer. Show two numbers that matter rather than four that don't.
4. **Flat hierarchy.** Use a real type scale: one large title per screen, one emphasis level,
   body, and secondary text. Size and weight carry hierarchy before colour does.
5. **Hidden everyday actions.** Anything used every session is visible and in thumb reach
   (bottom half of the screen during a workout); menus and long-presses are for rare actions.
6. **Vague words.** Labels say exactly what happens ("Log set 2 · 52.5 kg × 10"), empty states
   say what to do next, and numbers carry units.
7. **Decoration without data.** Every icon, chip and colour means something; remove any that
   only fill space.

## Interaction

- Primary in-workout controls are at least 56 pt tall and spaced so a sweaty tap can't hit the
  wrong one. One tap logs a set; nothing needed mid-set takes more than two.
- State is never shown by colour alone: pair it with an icon or a word.
- Motion marks a change (a number rolling, a best bouncing) and respects Reduce Motion.
- Every screen is designed in its empty, loading and error states as well as the full one.

## Review

Before a screen ships, check it against the seven tells above and write down any it breaks on
purpose. "Nothing to change" is a valid outcome.
