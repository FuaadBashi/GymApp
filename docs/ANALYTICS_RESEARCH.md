# Training analytics: what apps and tools offer, and what fits this data

Research for the separate offline analysis tool (decision #36), 13 October 2026. It covers
what the main training apps analyse, how the ones that recommend weights decide the next
increase, the free tools anyone can use, the research behind the methods, and which of it
this app's own data can support. Claims about apps come from their own pages, store
listings and reviews; few publish their exact formulas, and where a detail is a vendor or
third-party claim it is marked as such.

## 1. The apps

### Trackers: they log and chart, they don't prescribe

| App | Analytics | Recommends weights? |
|---|---|---|
| **Strong** | 1RM and volume charts per exercise, lifetime and yearly PRs flagged as you log, body measurements, CSV export. Full charts are paid. | No. |
| **Hevy** | Sets per muscle group (weekly/monthly/yearly), a body diagram of muscle distribution, volume load, duration, monthly report, workout comparison, leaderboards. Long history is paid. Pro has a public API, which community tools use to feed workouts to AI assistants. | No. |
| **JEFIT** | Body map of muscle focus, recovery chart, volume, weekly sets per muscle, movement balance, automatic 1RM. "AI progressive overload" and an analytics dashboard in the paid Elite tier. | Claims to (Elite); not documented. |
| **Boostcamp** | PRs, e1RM, weekly report, year-end recap; paid: a 0–100 Strength Score across squat, bench, deadlift, press and rows, bodyweight-adjusted with DOTS, and a per-muscle volume heatmap. | Auto-progression inside its programs. |

### Recommenders: they decide the next load

| App | Inputs | How the next weight is chosen (as far as published) |
|---|---|---|
| **Stronglifts 5×5** | Completed vs missed reps | Linear: all reps done → add a fixed increment (2.5 kg default) next session. Miss → repeat. Three misses in a row → drop 10% and climb again. All configurable. The clearest published rule of any app. |
| **Liftosaur** | Reps, weight, RPE; user scripts | Built-ins: linear (add after N successes), **double progression** (fill a rep range, then add weight and reset reps), reps-sum (add when total reps pass a threshold). Anything else is scriptable in its own language. |
| **Gravl** | e1RM, Easy/Hard rating per set | Rule-based on estimated 1RM: add reps set by set, raise weight when the range is full, rounded to the plates or stack you have. Shows why a target was chosen. |
| **Alpha Progression** | Weight, reps, RIR per set; available plate increments | Weight, reps and RIR target for every set from the last sessions; a strong set raises the target, a struggle holds it. Rounds to real increments ("31.7 kg is useless if the machine jumps 30 → 35"). Mesocycles with planned deloads. Charts an estimated 10RM. |
| **MacroFactor Workouts** | Weight, reps, RIR | Rule-based, no generative AI. Sets to failure: progress when performance beats prior sets. Sets with a range and RIR target (e.g. 7–9 @ 2 RIR ⇒ ~10 at failure): predict reps-to-failure and raise targets when beaten. Learns your strength–endurance relationship; offers a "fix" when targets can't fit the range. |
| **Fitbod** | Sets, reps, load; time since training; synced cardio | Per-muscle recovery 0–100% from recent work, shown as a heat map; heavy work is gated by recovery. Beginners start near 2–3 RIR. Hit reps easily → more load or reps; struggle → less. Varies intensity across sessions; lowers suggestions after a break; schedules "max effort days" to recalibrate. Per-muscle "mStrength" and an overall Strength Score. Formulas not public. |
| **RP Hypertrophy** | Soreness, pump, joint pain, workload ratings (not RPE) | Volume, not just load: per-muscle sets move between maintenance, MEV and MRV through a mesocycle depending on how you recover, then a deload. Third-party descriptions: start near MEV, add about one set per muscle per week while recovery is fine, hold when soreness or performance stalls. |
| **Juggernaut AI** | Top-set and back-off RPE; a 0–100 readiness score (weighted running average of check-ins) | Adjusts within a session, session to session, week to week and block to block. Can plan backwards from a meet date. Depends on accurate RPE. |
| **Dr. Muscle** | Performance vs targets | Daily undulating periodisation (rep ranges rotate, e.g. 5–7 → 10–12). The developer's own pre-app rule: no gains for two workouts in a row → deload 10% and restart the cycle. Schedules deloads. |
| **Arvo** | Set feedback (too hard/easy), notes | Next weight, reps and rest per set; a chat assistant over your data; volume per muscle; benchmarks on 16 lifts. Vendor/directory claims; prices disagree between sources. |
| **SensAI** | HRV, sleep, resting HR (via HealthKit), training | An LLM coaching layer that builds plans and remembers injuries and preferences. |

### Wearables

- **Whoop:** strength "strain" estimated as tonnage from motion sensors, with no per-exercise detail. Best paired with a logging app.
- **Garmin:** automatic rep counting, strength profiles and muscle heat maps.

Both are about readiness and load more than lift-by-lift progress.

### Free tools anyone can use with their own numbers

- **[Strength Level](https://strengthlevel.com/):** rates a lift (1RM or a set to failure) for your sex, bodyweight and age from about 195 million logged lifts, as percentiles from Beginner (5th) to Elite (95th). Covers 287 exercises, including machines.
- **[Symmetric Strength](https://symmetricstrength.com/):** strength score per lift and per muscle group, strong and weak points, and how proportionate your lifts are to each other.
- **FitnessVolt percentiles:** the same lift ranked against self-reported gym lifters (Symmetric Strength) and verified competitors (OpenPowerlifting). The gap is large: a 205 lb bench at 180 lb bodyweight is the 53rd percentile in a gym and the 10th among competitors.
- **Strong/Hevy CSV into a spreadsheet:** the common do-it-yourself route. GymApp's CSV already uses Strong's columns (EXPORT_FORMAT.md).
- **Hevy API + MCP servers:** let an AI assistant read and analyse workouts. That's the pattern for an LLM over training data: the assistant calls tools that compute; it doesn't compute itself.

## 2. Kinds of analysis, sorted

1. **Records and strength estimates:** heaviest load, best e1RM, rep record per load, best session volume, and their trend. Every app has these. GymApp has them (rulebook §5).
2. **Volume:** tonnage; hard sets per muscle per week; *fractional* sets (an indirect set counts half). GymApp counts 1 per primary and ½ per secondary muscle, which matches the fractional method.
3. **Rate of progress and plateaus:** slope of e1RM over weeks, sessions since the last record, stall detection (no improvement in N exposures). Recommenders use this as their deload trigger; trackers rarely surface it.
4. **Balance:** push vs pull, quad vs hamstring, upper vs lower, and lift ratios against norms (Symmetric Strength).
5. **Standards:** where a lift sits for your sex, age and bodyweight (Strength Level, competition data).
6. **Recovery and fatigue:** per-muscle recovery (Fitbod), readiness (Juggernaut, Whoop), fitness–fatigue models, acute:chronic workload ratio.
7. **Effort calibration:** how close sets were to failure, and how well your RIR guesses match what you could do. Needs RIR logging.
8. **Consistency:** sessions per week against a goal, streaks, missed days, time per session.
9. **Body composition:** weight trend; strength per kilogram.
10. **Program level:** mesocycles, planned deloads, peaking toward a date.
11. **Next-session prescription:** the weight and reps to attempt next.

## 3. What the research supports

- **Load vs reps progression:** adding reps at the same load and adding load at the same reps gave similar muscle growth over 8 weeks, with a slight, practically questionable strength edge for load ([Plotkin et al. 2022](https://peerj.com/articles/14142)). Fitbod's own user data points the same way. Double progression, which does both, is a sound default.
- **Training to failure:** no evidence that failure beats stopping short for growth; the relationship to proximity looks non-linear ([Refalo et al. 2023](https://dro.deakin.edu.au/articles/journal_contribution/Influence_of_Resistance_Training_Proximity-to-Failure_on_Skeletal_Muscle_Hypertrophy_A_Systematic_Review_with_Meta-analysis/22030796)). A dose-response on reps in reserve followed (Robinson et al. 2024).
- **Volume:** more weekly sets keep helping, with diminishing returns, much sooner for strength than for size. Fractional set counting fit the data best ([Pelland et al., preprint](https://sportrxiv.org/index.php/server/preprint/view/460)). Supports per-muscle weekly targets with a ceiling, not "more is always better".
- **RIR accuracy:** experienced lifters underestimate reps left by about 1–2, novices by about 4–5; estimates are better at heavier loads. Use RIR, but calibrate it.
- **1RM equations:** Epley and Brzycki agree at 10 reps and diverge below; no meta-analysis crowns one. A 2026 preprint fitted a **weight-dependent** equation on 303,494 near-failure sets from a consumer app (388 exercises) and cut estimate inconsistency by 17–22% against classical equations: `1RM = w × (1 + (r − 1)^0.85 / (−2.55 + 4.58 ln w))` ([Marzagao 2026](https://arxiv.org/abs/2603.17495)). Worth testing on this history before adopting; the rulebook uses Epley today.
- **Fitness–fatigue and ACWR:** promising for endurance, poorly validated for lifting, and sensitive to measurement noise. Useful as a descriptive "load this week vs your usual" line, not as a predictor or an injury-risk claim.

## 4. What this data can support

The history: 468 imported workouts from August 2022 plus app sessions, 7,765 sets over 193
exercises, with set types and 243 dated exercise notes. **No RPE or RIR in the history**:
JEFIT never recorded it. RIR (0–3) and labels can be logged in the app from now on. Body
weight: 66 entries.

| Analysis | Possible now | Notes |
|---|---|---|
| Records, e1RM trends, rep records | Yes | Already in the app. |
| Weekly fractional sets per muscle, balance ratios | Yes | Muscle tags come from the exercise map. |
| Progress rate per exercise, plateau/stall detection | Yes | Four years of exposures per lift. |
| Next-session weight by double progression with real increments | Yes | Increment per exercise can be learnt from the loads you have actually used (e.g. a stack that only moves in 4.5 kg steps). |
| Deload suggestion on stall (Stronglifts / Dr. Muscle style) | Yes | Needs a stall rule; the history can test candidate rules: which would have flagged your real plateaus? |
| Comparison of e1RM equations on your sets | Yes | Internal consistency, as in the 2026 preprint. |
| Strength standards / percentiles | Partly | Needs sex, age and current bodyweight; offline means bundling a table, not calling a site. |
| RIR-based targets (MacroFactor / Alpha style) | From now on | Needs a few weeks of RIR logged per exercise. |
| Readiness, recovery % | Weakly | Only from training load; no sleep or heart-rate data unless Apple Health is added. |
| Fitness–fatigue modelling | Not worth it | The evidence doesn't support prediction for lifting. |

## 5. Recommendation for the offline tool

- **Deterministic core, explained in words.** Every number comes from code that can be tested against the rulebook, the same as the app. An LLM, if used, only writes the narrative over facts the code computed ("bench has stalled for 5 sessions at 50 kg; last time this happened, a 10% deload broke it"). This is the pattern the Hevy MCP tools use, and it stops a model inventing numbers.
- **Input:** the `.sqlite` backup (EXPORT_FORMAT.md). It is read-only and needs no network.
- **Output:** a static HTML report (charts and tables) plus a small `recommendations.json`: per exercise, the next weight and reps, why, and any stall or deload flag.
- **The app can use that file.** Import it on the phone, and the workout screen shows "Try 52.5 kg × 8 (you hit 10, 10, 9 last time)" beside last time's values. Or the same rules move into the app later, once the tool has proven them on four years of history. Either way the rules are tested first.
- **A first version:** progress and plateau report per exercise; weekly fractional sets per muscle against a target band; balance ratios; consistency; and double-progression next-session targets with learnt increments and a stall-triggered deload, all back-tested on the history.

## Sources

App pages and reviews: [Hevy: sets per muscle group](https://www.hevyapp.com/features/sets-per-muscle-group-per-week/), [Hevy Pro](https://help.hevyapp.com/hc/en-us/articles/35119778922263-Hevy-Pro-Subscription-How-to-get-Pro-and-What-Does-It-Include), [Strong (App Store)](https://apps.apple.com/sg/app/id464254577), [Strong review 2026](https://www.sensai.fit/blog/strong-app-review-2026), [JEFIT (App Store)](https://apps.apple.com/app/id449810000), [Boostcamp features](https://boostcamp.app/features), [Stronglifts increments](https://support.stronglifts.com/article/71-increments), [Liftosaur docs](https://www.liftosaur.com/docs), [Gravl review 2026](https://www.sensai.fit/blog/gravl-app-review-2026), [Gravl (App Store)](https://apps.apple.com/ca/app/6450921637), [Alpha Progression guide](https://alphaprogression.com/en/blog/alpha-progression-guide), [MacroFactor smart progressions](https://help.macrofactorapp.com/en/articles/305-understanding-and-using-smart-progressions), [MacroFactor progressive overload](https://help.macrofactorapp.com/en/articles/372-what-does-progressive-overload-mean-in-macrofactor-workouts), [Fitbod: when to lift heavier](https://fitbod.me/blog/how-fitbods-ai-knows-exactly-when-you-should-lift-heavier-and-when-to-recover/), [Fitbod: how workouts are created](https://help.fitbod.me/hc/en-us/articles/360004429814-How-Fitbod-Creates-Your-Workout), [RP volume landmarks](https://rpstrength.com/training-volume-landmarks-muscle-growth/), [RP muscle emphasis](https://help.rpstrength.com/hc/en-us/articles/34825395726743-Muscle-Emphasis-Breakdown), [JuggernautAI individualisation](https://help.jtsstrength.com/en/articles/3-how-juggernautai-is-individualized-to-you), [Dr. Muscle periodisation](https://dr-muscle.com/periodization-muscle-hypertrophy/), [Arvo](https://arvo.guru/download), [AI personal trainer apps 2026](https://www.sensai.fit/blog/best-ai-personal-trainer-apps-2026), [Whoop vs Garmin](https://www.wareable.com/wearable-tech/whoop-vs-garmin), [Hevy MCP server](https://mcpservers.org/servers/chrisdoc/hevy-mcp), [Strong CSV for analysis](https://forum.intervals.icu/t/import-strong-data-weightlifting-app/5531).

Standards: [Strength Level](https://strengthlevel.com/), [FitnessVolt percentiles](https://fitnessvolt.com/powerlifting/calculators/percentile/).

Research: [Plotkin et al. 2022](https://peerj.com/articles/14142), [Refalo et al. 2023](https://dro.deakin.edu.au/articles/journal_contribution/Influence_of_Resistance_Training_Proximity-to-Failure_on_Skeletal_Muscle_Hypertrophy_A_Systematic_Review_with_Meta-analysis/22030796), [Pelland et al. (preprint)](https://sportrxiv.org/index.php/server/preprint/view/460), [Marzagao 2026](https://arxiv.org/abs/2603.17495), [1RM equations](https://en.wikipedia.org/wiki/One-repetition_maximum), [ACWR evidence](https://pmc.ncbi.nlm.nih.gov/articles/PMC7047972), [fitness–fatigue model](https://www.arxiv.org/pdf/1612.08591).
