# Phase 8: Studio reports, data health and the program planner

**Specified 14 October 2026.** Studio side of the owner's answers; phone pieces it needs are
cards 7.9 (reports) and 8.3 (fix suggestions).

## Card 8.1: Weekly and monthly reports

- `gymstudio/reports.py`: a report for each completed week (by the week-start setting) and
  each month, kept for all history (not only the last one). Sections: totals and change
  against the previous period; records (all-time and 1/6/12-month, phase 7 rules);
  sets per muscle against the band; plateaus and rebuilding lifts; skipped program days;
  body weight and steps; next targets.
- Written three ways, regenerated when a new backup loads:
  - a **Reports** page in the studio;
  - `GymApp Backups/Reports/2026-W42.md` and `2026-10.md`: Markdown with every figure in
    plain text, so the report can be read, searched or handed to an assistant later;
  - `GymApp-reports.json` for the app (card 7.9), the last 26 weeks and 12 months.
- Wording is generated from the figures by code; the optional AI wording uses Ask's
  summaries mode and is labelled as such.
- **Tests:** a synthetic week's totals and records; Markdown contains every number shown
  on the page; files rewrite atomically.

## Card 8.2: Data health

- `gymstudio/health.py`: per exercise, flag a set whose load is more than 6 median absolute
  deviations (MAD, floored at 5% of the median and 1 kg) from the loads of the five sessions
  before and five after it **and** at least double or at most half that median, with likely
  corrections tried in order: ×10 / ÷10 slip, kg↔lb slip, a dropped or doubled digit; the
  first landing within 1 MAD (at least 5% of the median) is proposed. A light set with no
  likely correction is not flagged (logged empty-bar sets and comebacks look like that).
  Also: reps over 50 on a loaded lift; a top set more than 60% above the best of the previous
  three sessions within 30 days (to check, no fix); and exercises whose names differ only in
  case or punctuation. On the real history: 18 load findings (9 with a fix), 21 jumps, 3 names.
- A **Data health** page lists findings with the proposed fix; ticked fixes are published
  as suggestions of a new kind `fix` (`{setId, load, unit, reps}`).
- **Tests:** 590 among 59s proposes 59; a real 20% PB jump is not flagged.

## Card 8.3: Fix suggestions on the phone

- App: suggestion kind `fix` shows the set's workout, date and old → new values; Accept
  writes through `WorkoutWrites.updateSet` on the finished set. History is corrected, never
  deleted. Records recompute.
- **Tests:** accepting a fix changes only that set; a fix for a set that no longer exists
  is refused and not recorded.

## Card 8.4: Program planner

- A **Planner** page: blocks of 4–6 weeks for the current program. Each block ramps weekly
  sets per muscle from near the bottom of the band toward the top; the page shows sets per
  muscle per week as a heat table, with balance ratios, before anything is sent.
- **Deloads only after a plateau:** the planner marks a deload week when 3 or more of the
  program's lifts are on plateau, or offers a deload for a single plateaued lift (the
  existing plateau target). No calendar deloads.
- **Nothing is sent automatically.** A "Send to phone" button publishes the chosen changes
  as suggestions (targets, swaps, set counts) only when pressed.
- **Tests:** ramp arithmetic for a 5-week block; deload offered only with plateaus.

## Card 8.5: Phase close

Studio tests, a report generated from the real backup checked against the app's Recaps for
the same month, HANDOFF, studio README.
