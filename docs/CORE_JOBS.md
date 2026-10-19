# Core jobs and what to build next

Research of 19 October 2026: what lifters ask of a logger, what the main apps get wrong, and
how the owner actually trains. It ends in a short list for the owner to choose from.

## How the owner trains (471 workouts, Aug 2022 – Oct 2026, from the phone's database)

| Measure | Median | Typical range (10th–90th %) |
|---|---|---|
| Session length | 59 min | 26–81 min |
| Sets per session | 17 | 9–24 |
| Exercises per session | 5 | 3–8 |
| Rest between sets (app-logged sessions only, few so far) | 2 min 20 s | 25 s – 3 min |

- Working sets by reps: 1–5: 30%, 6–8: 22%, 9–12: 40%, 13+: 8%. So 92% of sets fall where an
  estimated 1RM is meaningful (§4 caps it at 12 reps).
- Set types: 7,710 working, 54 failed, 23 warm-ups. Warm-ups were rarely logged in JEFIT.
- Usually trains on consecutive days (median gap 1 day), with 6 breaks of 30+ days (longest
  159). That makes the comeback (window) bests of §5a matter for this owner.
- Most-trained: lat pulldown (95 sessions), deadlift (87), Smith incline bench (83),
  leg extension (81), bench (78), bent-over row (77), squat (65).
- Reps-in-reserve has been logged on 15 sets: the feature exists but is barely used.

## The market

| App | Its core job | Best at | Common complaints |
|---|---|---|---|
| Strong | Fast set logging from your own templates | The cleanest, fastest logger | Paid for a plain log; 3 free templates; dated; no guidance on what to do next |
| Hevy | Free logger with a social feed | Generous free tier, good design | Free tier caps routines (4), custom exercises (7), history (3 months); a feed some can't turn off; reported rest-timer and black-screen bugs |
| JEFIT | Library, plans and logging | Big exercise library and history | Constant upsells and ads, sync errors, needs a connection to start, swaps behind a paywall, updates that broke mid-workout editing |
| Fitbod | Generates each session for you | Adaptive workouts with no planning | Expensive; users lose control of their plan |
| Alpha Progression | Periodised hypertrophy plans | Progression advice and exercise videos | Plan generator, progression and charts locked behind a subscription |
| Boostcamp | Follow published programs | Large free program library | Lighter form guidance; programs lead, logging follows |
| Liftosaur | Programmable progression rules | Full control of how lifts progress | Learning curve: rules are written as code |

The most-cited single measure of a logger is the number of taps to log a set. Next come
seeing last time's numbers while logging, rest timing, e1RM and volume charts, offline use and
data export. GymApp already has the last four; it has no paywall, ads, feed or account, which
removes the largest group of complaints outright.

## The core jobs

1. **Log the set I just did:** one tap, prefilled, never lost (survives the lock screen and
   a killed app).
2. **Know what to lift now:** today's target, last time, and what beats my best.
3. **Rest properly:** a countdown that alerts with the phone locked.
4. **See if I'm progressing:** per lift and overall, with honest numbers.
5. **Plan the next session:** what to change, swap or push.
6. **Keep my data mine:** offline, backed up, exportable.
7. **Learn and keep form:** demonstrations and my own cues.

## Candidate features, sorted

Kano: **E** essential (missing = complaints), **P** performance (more = better), **D** delighter
(unexpected). Status in GymApp: **Has**, **Weak** (exists but falls short), **Lacks**.

| Job | Feature | Kano | GymApp |
|---|---|---|---|
| 1 | One-tap log of a prefilled set | E | Has |
| 1 | Survives lock screen and app kill | E | Has (lock-screen hang fixed 16 Oct) |
| 1 | Plate calculator | P | Has |
| 1 | Log a set from the lock screen or Live Activity without opening the app | D | Lacks |
| 1 | Apple Watch logging | P | Lacks |
| 2 | Last time beside each set | E | Has (made secondary 19 Oct) |
| 2 | Live e1RM against all-time and window bests, with the set to beat | D | Has (19 Oct) |
| 2 | Suggested next weight × reps per set (double progression) | P | Weak: in the studio and as accepted targets, not shown per set by default |
| 2 | RIR / RPE that steers the next target | P | Weak: recorded, barely used, not used for advice |
| 3 | Rest alert with phone locked | E | Has |
| 3 | Rest length suggested by set type and effort | D | Lacks |
| 4 | Per-lift charts, records, history | E | Has |
| 4 | Weekly sets per muscle against a target band | P | Has (app and studio) |
| 4 | Plateau detection with a suggested fix | D | Has in the studio; Weak in the app |
| 5 | Programs and day templates | E | Has |
| 5 | Auto-progression rules per lift | P | Weak: studio only |
| 5 | Deload and comeback suggestions after breaks | D | Lacks (window bests exist; no plan) |
| 6 | Offline, no account | E | Has |
| 6 | Backups, restore, CSV export | E | Has |
| 6 | Import from Strong / Hevy as well as JEFIT | P | Lacks |
| 7 | Demonstrations | P | Has (83% of logged exercises) |
| 7 | Editable form cues in the workout | D | Has (10.4–10.5) |

## Recommended short list

1. **Next set suggestion on the set row:** "Try 62.5 × 10", from the studio's double
   progression rules moved into the app (jobs 2 and 5). It is the biggest gap against Alpha
   Progression and Fitbod, and the rules already exist and are tested in the studio.
2. **Log from the Live Activity:** a Log button on the lock-screen rest countdown (job 1). It
   removes the most taps of anything left. It needs an App Intent; check that it works on a
   free signing account first.
3. **Comeback plan after a break:** after 30+ days off, start lifts at a stated percentage of
   the window best and step up over a set number of sessions (jobs 4 and 5). This owner has
   had 6 such breaks.
4. **Make RIR count:** use reps in reserve in the next suggestion (item 1), or drop the chips
   if they stay unused (job 2).
5. **Import from Strong and Hevy CSV:** only if the app is ever shared (job 6).

Left out on purpose: social feed, gamification, AI-generated workouts. These are the features
the complaints are about, or ones that take control away from the lifter.

## Proof still owed (from the brief)

- UI tests (XCUITest) for the best tiles and the layout: they need a UI-test target, which is
  a project.pbxproj change and waits for the owner's go-ahead.
- A timing check at the gym: log a set in two taps or fewer, and read the number to beat at a
  glance.
- Two or three other lifters completing the main tasks without help.

## Sources

- Strong: [RepReturn review](https://repreturn.com/strong-app-review/),
  [Dr Muscle review](https://dr-muscle.com/strong-workout-app-review/),
  [PRPath review](https://prpath.app/blog/strong-app-review-2026.html)
- Hevy: [RepReturn review](https://repreturn.com/hevy-app-review/),
  [Dr Muscle review](https://dr-muscle.com/hevy-workout-app-review/),
  [Push/Pull on free limits](https://push-pull.app/blog/push-pull-vs-hevy)
- JEFIT: [Google Play reviews](https://play.google.com/store/apps/details/Gym_Workout_Plan_Log_Tracker?id=je.fit),
  [JustUseApp review summary](https://justuseapp.com/en/app/449810000/jefit-workout-planner-gym-log/reviews),
  [Dr Muscle review](https://dr-muscle.com/jefit-review-alternative/)
- Others: [Fitnessdrum comparison](https://fitnessdrum.com/alpha-progression-vs-fitbod-vs-hevy-vs-boostcamp/),
  [Sensai: Boostcamp vs Hevy vs Liftosaur](https://www.sensai.fit/blog/boostcamp-vs-hevy-vs-liftosaur-2026)
- What lifters value: [Setgraph comparison](https://setgraph.app/articles/best-app-to-log-workout-tested-by-lifters),
  [Nishaana guide](https://nishaana.com/blog/best-workout-apps-guide/)
- 1RM accuracy above 10 reps: [preprint review of validation studies](https://arxiv.org/pdf/2603.17495),
  [Mayhew et al. 2008](https://jssm.org/jssm-08-567.xml%3EFulltext)

Caveat: many of these sources are review blogs, some written by competing apps. No Reddit
threads came back from the searches, so the complaints list leans on reviews and store
listings; treat it as indicative, not measured.
