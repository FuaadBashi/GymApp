# Redesign step 3: key moments

Four moments decide how the app feels. For each: the situation, what must be visible, what
moves one tap away, and what changes from today. Nothing is removed from the app; it is
re-ranked using the marks in [01-audit.md](01-audit.md).

## 1. Before training (Train tab, at home or in the changing room)

**Situation:** two hands, a minute to spare, deciding whether today is the planned day.

| Visible | One tap away |
|---|---|
| Today's day: name, estimated time, last done | Other days (a compact list below) |
| Its exercises, each with today's suggestion ("95 kg × 6") instead of last time | Each exercise's page: demonstration, cues, history, records, targets, Swap |
| One button: Start | Programs, new program, empty workout (top bar) |
| Studio suggestions, when there are any (one line, expandable) | Accept / dismiss detail |

**Changes:** exercise rows become tappable (gap 1–2); rows show today's suggestion, the most
useful figure before training; the day's targets live on the exercise page, not a separate
sheet.

## 2. Between sets (workout, phone in one hand, often sweaty)

**Situation:** 1–3 minutes of rest; glances, not reading. The thumb reaches the bottom
half only.

Order of the current exercise, top to bottom (focus mode's order, adopted by the list):

1. Exercise name (tap → its page as a sheet) and "Set 2 of 3".
2. **The set:** load × reps in large type, with ± steppers (bottom half of the screen).
3. **What to beat:** this set's estimated 1RM against the best, one line; tap for the beat table.
4. Today's suggestion, one line with Fill.
5. The other sets as a compact table (today large, last time small).
6. Collapsed, one tap each: demonstration, cues, sticky note, notes & labels, set type, reps left.

The floating bar keeps Log / Rest. Nothing interactive sits under it (bottom inset sized to
the bar).

**Changes:** demonstration, credits, sticky note and workout note move below the sets and
collapse; the set and what-to-beat move above the fold on every phone size.

## 3. End of the workout

**Situation:** done, tired, curious: "did I do better?"

| Visible | One tap away |
|---|---|
| One headline: records set today (or "matched last time") | Each record's set and date |
| Per exercise: today against last time, one line, ↑ ↓ = in words and colour | The exercise's page |
| Duration, volume, sets as one sentence, not four tiles | Muscles worked |
| Done | Back to workout (fix a set) |

**Changes:** equal tiles become a sentence; records lead.

## 4. Weekly review (Progress, on the sofa)

**Situation:** two minutes, wants the shape of the week.

One screen, three blocks, each a door to its detail:

1. **This week against your usual:** sessions, sets, time as one line and a 12-week sparkline;
   tap → the three charts.
2. **Muscles:** the body map with sets per muscle (this week / last week toggle); tap →
   per-muscle list and recovery.
3. **Lifts:** records this week and lifts that moved, best first; tap → recent records and
   movement trends.

Reports (from the studio) and Recaps become visible rows at the bottom, not icons.

**Changes:** the five-screen scroll becomes one screen of summaries; the detail is unchanged,
one tap down. Body weight and steps move into block 1's detail.

## The studio's moments

The Mac app is used for a weekly or monthly sit-down. It mirrors moment 4 on a large screen:
the overview's hero and blocks use the same three summaries, the same words and the same
components (row, figure, chip, section header), from the shared tokens.
