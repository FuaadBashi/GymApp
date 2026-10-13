# GymApp and the analysis studio: plan, ideas and open questions

Updated 14 October 2026. Builds on [ANALYTICS_RESEARCH.md](ANALYTICS_RESEARCH.md).
S0 foundations and S1 dashboards are implemented. S2 Rule Lab now replays five rules
with historical targets, outcome scoring and a later-session holdout. Notebook work
is retained, including the editor and local custom metrics. Ask and the later phone
additions remain deferred. See [the S2 implementation](specs/studio-s2-rule-lab.md).

## 1. The split

| | **GymApp (iPhone)** | **The studio (Mac, offline)** |
|---|---|---|
| Purpose | Train, log, and see everything JEFIT shows, and more, without needing the Mac | Deep analysis, experiments, your own code, and AI over your data |
| Data | The live database | The latest backup, read-only, never written back |
| Analytics | Fixed, tested, fast: records, charts, volume, recovery, balance, standards, next-weight suggestions | Adjustable: every setting exposed; rule lab; back-tests; notebooks; chat |
| Weight suggestions | Shows them at the gym | Invents and proves the rules first ("tool proves rules, then in-app") |
| AI | None (offline, private) | Optional; it only explains numbers the code computed |

**Data path.** The phone already copies a verified backup into your chosen folder after
every change. If that folder is in iCloud Drive, it appears on the Mac by itself. The studio
watches the folder and always opens the newest copy. No cable, no export step.

**Rules path.** A progression or plateau rule is written once in Python in the studio,
back-tested on four years of history, and written up as a short spec with test cases. It is
then ported to Swift, and the same test cases run in both, so the phone and the studio can
never disagree.

## 2. JEFIT parity: what the app has and what it lacks

| JEFIT feature | GymApp today |
|---|---|
| 1RM and volume chart per exercise; tap a point for that day's sets | Chart (e1RM, heaviest, volume) and records; **tapping a point is missing** |
| PR identification | Yes (records list, summary, Progress tab) |
| Muscle map of training focus | Yes (body map, this week and last week) |
| **Muscle recovery chart** (which muscles are ready) | **Missing** |
| Weekly sets per muscle | Yes |
| **Movement balance; weekly 1RM change for six key movement patterns** | **Missing** |
| Workout time charts | Partly (weekly training time) |
| Body weight, **body fat, measurements, body-stat goals** | Weight only; **fat, measurements and goals missing** |
| Calendar and history timeline | Yes |
| "AI progressive overload" suggestions | **Missing**: the reason for the studio's rule lab |
| Export the whole journey | Yes (CSV and full backup) |

Beyond JEFIT, from the other apps: per-set targets with real plate increments (Alpha),
stall-triggered deloads (Stronglifts, Dr. Muscle), a strength score and standards (Boostcamp,
Strength Level), monthly and yearly recaps (Hevy, Boostcamp), session comparison (Hevy).

## 3. Interface options for the studio

You asked for an excellent interface, settings to adjust, and the ability to add code.

| Option | Interface | Your own code | Effort |
|---|---|---|---|
| **A. Local web app** (Python + DuckDB behind a polished browser front end, run with one command) | Best: custom dashboards, drill-down, keyboard, dark theme like the app | Through a built-in "Lab" | Most |
| **B. marimo** (reactive Python notebooks that also run as apps) | Good: sliders and charts update live; less polished | Native: every view is editable Python | Least |
| **C. Hybrid (recommended)**: A for the dashboards, with a **Lab** tab that opens marimo notebooks on the same data and functions | Best | Native in the Lab | Medium |
| D. Native Mac app (SwiftUI, reusing GymApp's code) | Polished | Hard to add code at run time | High |

The earlier choice was "Python + HTML report". A static report can't be adjusted or coded
into, so option C replaces it unless you say otherwise.

## 4. Ideas: what the studio could do

**Progress and plateaus**
1. Progress rate per lift (kg of e1RM per month) over any window, with best and worst periods.
2. **Plateau detector:** sessions since the last record, flagged when no improvement in N exposures. N is a setting.
3. **Rule lab:** replay any progression rule over your real history ("if you had followed double progression with a 10% deload after 3 stalls…") and score it: how often it called a plateau you really had, how often it raised the weight too soon.
4. **Next-session targets** per exercise from the winning rule, with the reason shown.
5. **Increment learning:** the real step sizes each machine allows, learnt from loads you have used (a stack that moves in 4.5 kg steps, dumbbells in 2 kg).
6. **Goal projection:** "at your current rate, 100 kg bench around March"; a confidence band, not a promise.
7. **Breaks and detraining:** how much strength each lift lost after gaps, and how fast it came back. Your history has several comeback periods.

**Volume and balance**
8. Weekly fractional sets per muscle against a target band you set, with the research's diminishing-returns curve shown.
9. Balance radar: push/pull, upper/lower, quads/hamstrings, chest/back, left side of the body map vs right.
10. **Recovery estimate** per muscle from recent sets and their timing (Fitbod style), for parity with JEFIT's recovery chart; the formula is exposed and adjustable.
11. Movement-pattern strength: weekly e1RM change for six patterns (squat, hinge, horizontal and vertical push and pull), for parity with JEFIT.

**Strength standards**
12. Where each lift sits for your sex, age and bodyweight, from a table bundled offline.
13. Symmetry: lifts that lag behind the others relative to norms.

**Session quality**
14. Rest-time analysis: sets carry completion times, so real rest between sets is known. Does longer rest mean more reps?
15. Time of day, day of week, session length: when you train best.
16. Effort calibration: once RIR is logged, how your RIR guesses compare with what you then did.
17. Warm-up and drop-set patterns; failed-set frequency per exercise.

**Formula lab**
18. Compare e1RM equations on your own sets (Epley, Brzycki, the 2026 load-dependent equation) by internal consistency, and pick the one that fits you; the app follows.

**Body**
19. Weight trend, strength per kilogram, and body fat and measurements once the app records them.

**Reviews and recaps**
20. Weekly and monthly review: what went up, what stalled, what was skipped.
21. Year recap ("Wrapped"): totals, records, most-trained muscle, longest streak.
22. **Notes mining:** 243 dated exercise notes, searchable; with AI, summarised into themes (injuries, set-ups, seat positions).

**AI (optional, numbers stay in code)**
23. **Ask your data:** a chat where the model answers by calling tested functions ("best bench since June", "which muscles am I neglecting"), never by doing arithmetic itself.
24. A written weekly review built from the computed facts.
25. Program assistant: proposes changes to Full Body 1–3 from volume gaps and plateaus; you accept or reject.
26. Anomaly finder: likely typos (59 kg logged as 590), impossible jumps.

**Your own code**
27. Any notebook in the Lab sees the same tables and functions. Custom metrics, charts and rules can be saved and shown on the dashboard.

## 5. AI on this Mac

- **Local** (private, free, offline): Ollama is already installed. With 16 GB, models around 7–8 billion parameters run well (Qwen, Llama, Mistral families). They're good enough to phrase a summary of facts; weaker at multi-step reasoning and tool use.
- **Claude API** (better reasoning, needs internet and an API key): only the computed summary is sent, never the raw database.
- **Both:** local by default; Claude when you choose. Everything works without AI.

## 6. A possible build order (after your answers)

1. **S0, foundations:** read the backup, the data model, the rulebook maths in Python checked against the app's own test values, iCloud folder watching.
2. **S1, dashboards:** overview, exercise deep-dive, muscle volume and balance, history explorer.
3. **S2, rule lab:** plateau detector, progression rules, back-tests, increment learning.
4. **S3, Lab:** notebooks with your own code, saved custom metrics.
5. **S4, AI:** ask-your-data, weekly review, notes mining.
6. **App parity:** in parallel, cards in the app for recovery, movement patterns, body fat and measurements, tap-a-point, recaps, and next-weight suggestions once S2 has proven the rule.

## 7. Decisions (13 October 2026)

- **Use:** any time, from daily to monthly. Only the owner uses it for now.
- **Decisions it supports:** weights, exercise choice, program changes and deloads, grounded in the research. Health data stays narrow for now: training, body weight and **steps**.
- **Phone:** receives proven rules, and also program suggestions. Every suggestion is clearly marked as one, shows where it came from, and changes nothing until accepted.
- **Interface:** option C, dashboards plus a Lab of marimo notebooks on the same data and functions.
- **Ideas:** all of section 4, and more.
- **AI:** the Claude API, with a local model as an option.
- **Build order:** S0–S4 and app parity as in section 6.
- **Effort:** RIR is logged on every set from now on.
- **Plateau:** three weeks with no increase in weight on an exercise. Then look at the other exercises for the same muscles to find the weak point.
- **Research findings to build:** double progression as the default rule; stall rules (Stronglifts-style) back-tested on the history; the 2026 load-dependent e1RM equation compared with Epley on these sets; RIR-based targets once RIR data exists.

- **Steps and weight:** from Apple Health, read by GymApp and carried in the backup. Body fat and measurements are not wanted for now.
- **Plateau response:** suggest a deload and rebuild, or a swap to a close variant. Rules start from the research and are tuned by the history, with every change shown.
- **Goal:** size first, strength tracked on the main lifts. Weekly target 10–20 fractional sets per muscle, adjustable.
- **Profile:** sex, birth year and height, set in both the app and the studio, never committed.
- **Launch:** a double-click Mac app opening the studio in its own window.
- **To the phone:** a suggestions file in the iCloud backup folder; GymApp shows each with Accept or Dismiss.
- **Code:** in this repository under `studio/`. Name: **GymApp Studio**.
- **Claude API data:** computed summaries by default; a mode where the model can query any table through tools, when chosen.

## 8. Questions (original list)

**Purpose and use**
1. When would you open the studio: after every session, weekly, or occasionally to dig?
2. What decisions should it help you make: weights, exercise choice, program changes, when to deload?
3. Is anyone else ever going to use it (friends, a coach), or only you?
4. Do you want the phone to receive anything from the studio besides proven rules (for example, a program change it proposes)?

**Interface**
5. Option C (dashboards plus a code Lab), or another from section 3?
6. Which screens matter most on the first day: overview, exercise deep-dive, muscles, history, rule lab, chat?
7. Light or dark, and should it look like the app (dark with the volt accent)?
8. How much code do you expect to write yourself: tweak settings only, small formulas, or full notebooks?

**Analytics**
9. Which of ideas 1–27 do you want first? Any you don't want?
10. For progression: double progression, linear with deloads, RIR targets, or let the rule lab compare them all on your history first?
11. What counts as a plateau for you: no new e1RM in N sessions, N weeks, or something else?
12. Your target weekly sets per muscle, or should the studio suggest bands from the research?
13. For standards: your sex, age and current bodyweight (stored only on your machine)?
14. Will you log RIR on every set from now on? Several ideas get much better with it.
15. Should the app record body fat and measurements (waist, chest, arms, thighs) for parity with JEFIT?

**AI**
16. Local only, Claude only, or both with local as the default?
17. Are you happy to create a Claude API key for the optional cloud mode?
18. What should AI never see (for example, notes)?

**Data and practicalities**
19. Is your backup folder in iCloud Drive, so the Mac sees new backups automatically?
20. Will you keep logging in JEFIT for a while, so the studio should merge JEFIT exports too?
21. Should the studio live in this repository (tools/studio/) or a separate one?
22. Name for it?
