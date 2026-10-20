# Redesign step 3: key moments

Four moments decide how the app feels. For each moment, this step gives the situation, the
items that must be visible, the items that go one tap away, and the changes from today. The
app keeps all its information. We change only the order, with the marks from
[01-audit.md](01-audit.md).

## 1. Before training (Train tab, at home or in the changing room)

**Situation:** you have two hands and one minute. You decide if today is the planned day.

| Visible | One tap away |
|---|---|
| Today's day: name, estimated time, date last done | Other days (a short list below) |
| Its exercises, each with today's suggestion ("95 kg × 6") in place of last time | The page of each exercise: demonstration, cues, history, records, targets, Swap |
| One button: Start | Programs, new program, empty workout (top bar) |
| Studio suggestions, when there are any (one line that opens) | The details to accept or dismiss |

**Changes:** you can tap the exercise rows (gaps 1–2). Before training, today's suggestion is
the most useful figure, so the rows show it. The day's targets are on the exercise page, not
on a separate sheet.

## 2. Between sets (workout, phone in one hand, often wet)

**Situation:** you rest for 1–3 minutes. You glance; you do not read. Your thumb reaches only
the bottom half of the screen.

The current exercise shows these items from the top down. This is the order of focus mode,
and the list will use it too:

1. The exercise name (a tap opens its page as a sheet) and "Set 2 of 3".
2. **The set:** load × reps in large type, with ± steppers in the bottom half of the screen.
3. **What to beat:** this set's estimated 1RM against the best, on one line. A tap opens the
   beat table.
4. Today's suggestion on one line, with Fill.
5. The other sets as a short table: today large, last time small.
6. Closed, one tap each: demonstration, cues, sticky note, notes and labels, set type, reps in
   reserve.

The floating bar keeps Log and Rest. No item that you can tap is below the bar, because the
content has a bottom inset equal to the bar.

**Changes:** the demonstration, the credits, the sticky note and the workout note move below the
sets and close. The set and what to beat move above the fold on each phone size.

## 3. End of the workout

**Situation:** you are finished and tired. You want to know: "Did I do better?"

| Visible | One tap away |
|---|---|
| One headline: the bests of today and the number of lifts that went up | The set and date of each best |
| For each exercise: today against last time on one line, ↑ ↓ = with a word and a colour | The sets of each exercise, and its page |
| Duration, volume and sets in one row, not in four tiles | The muscles that you trained |
| Done | Back to workout (to correct a set) |

**Changes:** one row replaces the equal tiles. The bests come first. (The prototype of 20
October adds more detail; see [06-build-plan.md](06-build-plan.md).)

## 4. Weekly review (Progress, on the sofa)

**Situation:** you have two minutes. You want the shape of the week.

One screen with three blocks. Each block opens its details:

1. **This week against your usual week:** sessions, sets and time on one line, and a 12-week
   sparkline. A tap opens the three charts.
2. **Muscles:** the body map with sets per muscle (this week or last week). A tap opens the list
   of muscles and the recovery.
3. **Lifts:** the bests of this week and the lifts that changed, the best first. A tap opens the
   recent records and the movement trends.

Reports (from the studio) and Recaps become visible rows at the bottom. They are not icons.

**Changes:** one screen of summaries replaces the scroll of five screens. The details do not
change, and they are one tap down. Body weight and steps move into the details of block 1.

## The moments of the studio

You use the Mac app for a weekly or monthly review. It shows moment 4 on a large screen. The
hero and blocks of the overview use the same three summaries, the same words and the same
components (row, figure, chip, section title), from the shared tokens.
