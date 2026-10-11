# Decisions

Decided 11 October 2026 unless dated otherwise. "Default" marks a choice made to keep moving
that can change without reworking anything.

## A. Platform and distribution

| # | Question | Decision |
|---|---|---|
| 1 | Web app or native? | **Native iPhone app, SwiftUI.** The phone is locked or in another app between sets, and only a native app can alert when rest ends in that state. It also leaves Apple Watch open for later. |
| 2 | Paid Apple Developer membership? | **No.** Built and installed with a free Apple ID (Personal Team). The install expires after 7 days and is re-sent from Xcode on the Mac, about a minute over Wi-Fi. Data on the phone survives a re-send. **Never delete the app to fix a problem:** deleting it deletes the data. |
| 3 | Living with the 7-day expiry | The app reads its own expiry date and shows a banner, plus a notification, two days before. It must never lapse unnoticed before a gym session. |
| 4 | Tools | Xcode (free, Mac App Store). The Mac is only a build machine; nothing runs there day to day. |
| 5 | Free-account limits that matter | No iCloud sync and no push notifications. Neither is needed: rest alerts are local notifications. Whether the lock-screen countdown (Live Activity) works on a free account is **to verify in the first build**; the notification alone covers the need. |
| 6 | Minimum iOS | **iOS 26.** The phone is an iPhone 17 Pro Max on iOS 26.6.1, and the Mac has Xcode 26.6. One device means no older versions to support. |

## B. Data

| # | Question | Decision |
|---|---|---|
| 7 | Where does data live? | **On the phone only.** No account, no server, no network access. Exercise images are bundled. |
| 8 | Storage engine | **Default: SQLite through GRDB.** Weekly volume per muscle, PRs and plateau checks are aggregates that SQL expresses directly. CHECK constraints can enforce rulebook invariants for every writer. A backup is a single file that opens with `sqlite3` on the Mac. SwiftData is the alternative if a third-party package becomes a problem. |
| 9 | Backups | After every finished workout, a dated copy of the database goes to a folder you pick once, e.g. in iCloud Drive. That needs no paid entitlement; **to verify in the first build**. The last 30 copies are kept, plus one per month. The iPhone's own iCloud Backup is a second layer. Restore is tested before the app's first real session. |
| 10 | Derived figures | **Computed from logged sets on read, never stored:** PRs, volume, sets per muscle, estimated 1RM, plateau status, summaries. Correcting a set corrects everything downstream. |

## C. Units

| # | Question | Decision |
|---|---|---|
| 11 | kg or lb? | **kg by default, lb switchable** globally and per exercise (gyms mix lb dumbbells with kg machines). Loads are stored exactly as entered. Rulebook §1. |

## D. Training model

| # | Question | Decision |
|---|---|---|
| 12 | Routine scheduling | **Default: rolling rotation.** Day 1 → 2 → 3 → 1 regardless of weekday, matching the "Any" days in your JEFIT plan. A missed day never breaks the sequence. Fixed weekdays can come later. |
| 13 | Supersets and drop sets | **In the data model from V1, hidden in the UI until switched on.** Adding them to the model later would touch every query, and the UI is the cheap part. |
| 14 | Exercise library source | **[free-exercise-db](https://github.com/yuhonas/free-exercise-db)**: 876 exercises, marked public domain (Unlicense), with muscles, equipment, push/pull and compound/isolation. We add movement families and gym-specific tags. Image provenance is checked before shipping photos; until then, exercises ship text-only. |
| 15 | Last-time values | **Same routine day by default**, falling back to any workout. This matches your JEFIT setting, which JEFIT locks behind Elite. |
| 16 | Defaults for new exercises | 3 sets, 10 reps, 60 s rest, matching your JEFIT settings. |
| 17 | Week start | **Sunday by default**, matching your JEFIT calendar. Changeable. |

## E. Scope

| # | Question | Decision |
|---|---|---|
| 18 | What is out? | Social, points, upsells, AI coaching, "insights", Discover, nutrition, accounts, cloud sync. |
| 19 | JEFIT history | **Import all of it, in V1.** The second export (11 Oct) has 492 workouts from Aug 2022 to Oct 2026, plus routines, notes and body stats; the first was from a different account. The format, its traps and the import rules are in [JEFIT_EXPORT.md](JEFIT_EXPORT.md). Without the history there are no last-time values, and the app loses to JEFIT on day one. |

## F. Product shape (revised 11 Oct, after the first prototype)

| # | Question | Decision |
|---|---|---|
| 20 | Program structure | **Any split, built in the app.** You run three separate full-body days; the third gets built here. The split picker offers full body (2–3 days), upper/lower (4 or 6), push/pull/legs (3 or 6) and custom. Rotation stays rolling (#12). |
| 21 | Adding exercises to a day | **Filter, then suggest.** The library opens filtered to the day's focus, with "Show all" one tap away. "Suggest a day" fills a balanced set of movements from exercises you have done before. |
| 22 | Day focus from exercise data | **Default:** body region comes from primary muscles. Upper is chest, shoulders, lats, middle back, traps, biceps, triceps, forearms and neck. Lower is quadriceps, hamstrings, glutes, calves, adductors, abductors and lower back. Core is abdominals. Push and pull come from the dataset's `force` field; legs means lower. |
| 23 | Workout screen | **A scrolling list of exercise cards with a focus toggle.** This replaces the prototype's one-exercise-per-page layout, which was too close to JEFIT. The list matches what Strong and Hevy settled on; focus mode serves heavy sets. |
| 24 | Workout in progress | **A mini-player above the tab bar**, in place of a JEFIT-style resume banner. |
| 25 | Navigation | **Five tabs:** Train, History, Exercises, Progress, Settings. |
| 26 | Export and import | **Export** a full backup (the database file) and a CSV of every set. **Import** a backup, which backs up the current data first, or a JEFIT export. |
| 27 | Build order | Foundation → programs and library → workout screen → history and analytics → import/export → on the phone. Details in [ROADMAP.md](ROADMAP.md). |

## Open

- Which "Later" features in the product brief move up.
- Body stats: is weight plus body fat enough, or are BMI, lean mass and photos wanted?
