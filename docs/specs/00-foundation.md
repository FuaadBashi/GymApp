# Phase 0: Foundation

**Outcome:** the app has its own SQLite database, holding the 876-exercise library and the
full JEFIT history, imported in-app with a report that accounts for every row. The prototype
UI keeps running on its seed file and is not touched beyond compile fixes.

**Already done and checked in:**

- `GymApp/Resources/Library/exercises.json`: the library, built by `tools/build_library.py`.
- `GymApp/Resources/Library/jefit_exercise_map.json`: all 199 JEFIT exercises classified, built
  by `tools/build_jefit_map.py`.
- `tools/reference_import.py`: the import rules below, written in Python. Its outputs are the
  expected values:
  - `GymAppTests/Fixtures/jefit_expected.json` for the real export;
  - `GymAppTests/Fixtures/jefit_mini_expected.json` for the synthetic `jefit_mini.csv`.
- GRDB 7.11.1 is linked to the app target, and `GymAppTests` exists.

**Read first:** [TRAINING_RULEBOOK.md](../TRAINING_RULEBOOK.md) §1–§3 and §10,
[JEFIT_EXPORT.md](../JEFIT_EXPORT.md), and `tools/reference_import.py`, which is the import
algorithm in executable form.

---

## Card 0.1: Domain types, and TrainingMath on load modes

**Goal:** the shared vocabulary every later card uses, and the rulebook maths expressed in it.

**Files:**

- create `GymApp/Domain/ExerciseTypes.swift`
- create `GymApp/Domain/PastSet.swift` (move `PastSet` and its `shortText` out of the prototype)
- change `GymApp/Domain/TrainingMath.swift`, `Load.swift`, `SetType.swift`
- change `GymApp/Prototype/PrototypeModels.swift` and the prototype call sites the compiler
  points to
- create `GymAppTests/TrainingMathTests.swift`

**Steps:**

1. In `ExerciseTypes.swift`, declare these enums, each `nonisolated`,
   `String`-backed, `Codable` and `CaseIterable`. The raw values are exactly the case names;
   they are what the database and both JSON resource files store.

   ```swift
   nonisolated enum Muscle: String, Codable, CaseIterable {
       case abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes,
            hamstrings, lats, lowerBack, middleBack, neck, quadriceps, shoulders, traps, triceps
   }
   nonisolated enum Equipment: String, Codable, CaseIterable {
       case barbell, ezBar, dumbbell, kettlebell, cable, machine, smith, plate, band, bodyweight, other
   }
   nonisolated enum LoadMode: String, Codable, CaseIterable {
       case total, perHand, perSide, bodyweightPlus, repsOnly
   }
   nonisolated enum Force: String, Codable, CaseIterable { case push, pull, `static` }
   nonisolated enum Mechanic: String, Codable, CaseIterable { case compound, isolation }
   nonisolated enum ExerciseCategory: String, Codable, CaseIterable {
       case strength, stretching, plyometrics, powerlifting, olympicWeightlifting, strongman, cardio
   }
   nonisolated enum BodyRegion: String, Codable, CaseIterable {
       case upper, lower, core, fullBody, cardio
   }
   nonisolated enum MovementPattern: String, Codable, CaseIterable {
       case horizontalPush, inclinePush, verticalPush, horizontalPull, verticalPull,
            squat, hinge, lunge, kneeExtension, kneeFlexion, hipThrust, hipAbduction, calfRaise,
            chestFly, lateralRaise, frontRaise, rearDelt, shrug, pullover,
            bicepsCurl, tricepsExtension, dip,
            coreFlexion, coreStability, backExtension, neck, grip, carry, cardio, other
   }
   ```

2. Add these computed properties in the same file:
   - `Muscle.region: BodyRegion`, from decision #22:
     - `.upper` for chest, shoulders, lats, middleBack, traps, biceps, triceps, forearms
       and neck;
     - `.lower` for quadriceps, hamstrings, glutes, calves, adductors, abductors and
       lowerBack;
     - `.core` for abdominals.
   - `Muscle.displayName: String`: "Lower back" and "Middle back"; every other case is its
     name capitalised.
   - `LoadMode.volumeMultiplier: Double`: 2 for `perHand` and `perSide`, otherwise 1.
   - `LoadMode.label: String`, shown in the UI under the weight column:
     - total: "Total"
     - perHand: "Per hand"
     - perSide: "Per side"
     - bodyweightPlus: "Added (− = assisted)"
     - repsOnly: "Reps only"
   - `Equipment.stepKg: Double`, one stepper tap:
     - 2.5 for barbell, ezBar, smith, machine, cable and plate;
     - 2 for dumbbell;
     - 4 for kettlebell;
     - 1 for band, bodyweight and other.

3. Add `nonisolated` to `WeightUnit`, `Load`, `SetType` and `TrainingMath`. Move `PastSet` (and
   the `shortText` extension) into `Domain/PastSet.swift`, also `nonisolated`. Its fields stay
   `kg: Double, reps: Int, type: SetType`; a reps-only set carries `kg: 0`.

4. Rewrite `TrainingMath` against `LoadMode`. The public surface is exactly:

   ```swift
   nonisolated enum TrainingMath {
       static func e1RM(kg: Double, reps: Int) -> Double
       static func displayableE1RM(kg: Double, reps: Int, loadMode: LoadMode) -> Double?
       static func calculationKg(_ kg: Double, loadMode: LoadMode, bodyWeightKg: Double?) -> Double?
       static func volumeKg(_ sets: [PastSet], loadMode: LoadMode, bodyWeightKg: Double?) -> Double
       struct Bests: Equatable { var heaviestKg: Double?; var bestE1RM: Double? }
       static func bests(_ sets: [PastSet], loadMode: LoadMode) -> Bests
   }
   ```

   Rules (rulebook §2–§5):
   - `e1RM`: Epley, `kg * (1 + reps / 30)`; reps ≤ 1 returns `kg`. Unchanged.
   - `displayableE1RM`: `nil` for `bodyweightPlus` and `repsOnly`, for kg ≤ 0, or for reps
     outside 1...12; otherwise `e1RM`.
   - `calculationKg`:
     - `total`, `perHand` and `perSide` return `kg`;
     - `bodyweightPlus` returns `max(bodyWeightKg + kg, 0)`, or `nil` when body weight is
       unknown;
     - `repsOnly` returns `nil`.
   - `volumeKg`: Σ `calculationKg × reps × volumeMultiplier` over sets whose type is not
     `.warmUp`. A `nil` calculation load contributes 0.
   - `bests`:
     - `Bests(nil, nil)` for `bodyweightPlus` and `repsOnly`;
     - otherwise consider sets that are neither `.warmUp` nor `.drop` (rulebook §3: only a
       drop set's first segment, logged as `.working` or `.failed`, can set a record) and have
       reps > 0 and kg > 0;
     - `heaviestKg` is the max kg;
     - `bestE1RM` is the max `displayableE1RM`.

5. Prototype fixes, kept minimal:
   - Give `ProtoEquipment` a `var loadMode: LoadMode`:
     - barbell, cable, machine and other map to `.total`;
     - dumbbell maps to `.perHand`;
     - assisted maps to `.bodyweightPlus`.
   - Delete `ProtoEquipment.volumeMultiplier`.
   - At each prototype call site of `TrainingMath`, pass `loadMode: <equipment>.loadMode` where
     it passed `equipment:`.
   - The prototype's `ProtoEquipment.stepKg` stays.

**Tests** (`TrainingMathTests.swift`), each expectation within 0.001:

| Call | Expected |
|---|---|
| `e1RM(kg: 50, reps: 10)` | 66.667 |
| `e1RM(kg: 100, reps: 1)` | 100 |
| `displayableE1RM(kg: 60, reps: 12, loadMode: .total)` | 84 |
| `displayableE1RM(kg: 60, reps: 13, loadMode: .total)` | nil |
| `displayableE1RM(kg: -45, reps: 6, loadMode: .bodyweightPlus)` | nil |
| `calculationKg(-45, loadMode: .bodyweightPlus, bodyWeightKg: 90)` | 45 |
| `calculationKg(-45, loadMode: .bodyweightPlus, bodyWeightKg: nil)` | nil |
| `calculationKg(-100, loadMode: .bodyweightPlus, bodyWeightKg: 90)` | 0 |
| `calculationKg(10, loadMode: .repsOnly, bodyWeightKg: 90)` | nil |
| `volumeKg([20×10 working, 20×10 warmUp], loadMode: .perHand, bodyWeightKg: nil)` | 400 |
| `volumeKg([-45×6 working], loadMode: .bodyweightPlus, bodyWeightKg: 90)` | 270 |
| `volumeKg([0×12 working], loadMode: .repsOnly, bodyWeightKg: 90)` | 0 |
| `volumeKg([60×8 failed], loadMode: .total, bodyWeightKg: nil)` | 480 |
| `bests([100×1 warmUp, 80×5 working, 70×12 working], loadMode: .total)` | heaviest 80, bestE1RM 98 |
| `bests([-45×6 working], loadMode: .bodyweightPlus)` | heaviest nil, bestE1RM nil |
| `bests([60×8 working, 90×3 drop], loadMode: .total)` | heaviest 60, bestE1RM 76 |
| `volumeKg([60×8 working, 40×6 drop], loadMode: .total, bodyWeightKg: nil)` | 720 |
| `Muscle.lowerBack.region`, `Muscle.traps.region`, `Muscle.abdominals.region` | `.lower`, `.upper`, `.core` |

**Done when:** the tests pass, the app builds, and the prototype runs unchanged in the
simulator (start a day, log a set, see the rest bar).

**Out of scope:** any database code; renaming prototype types; UI changes.

---

## Card 0.2: Database schema, records and AppDatabase

**Goal:** the database every later card reads and writes, with the rulebook's invariants
enforced by SQLite itself.

**Files:** create `GymApp/Database/Schema.swift`, `GymApp/Database/AppDatabase.swift`,
`GymApp/Database/Records.swift` and `GymAppTests/SchemaTests.swift`.

**Steps:**

1. `Schema.swift`: a `nonisolated enum Schema` with
   `static var migrator: DatabaseMigrator`, registering one migration named `"v1"` that runs
   this SQL exactly:

   ```sql
   CREATE TABLE exercise (
     id TEXT PRIMARY KEY NOT NULL,
     name TEXT NOT NULL CHECK (length(trim(name)) > 0),
     equipment TEXT NOT NULL CHECK (equipment IN ('barbell','ezBar','dumbbell','kettlebell','cable','machine','smith','plate','band','bodyweight','other')),
     loadMode TEXT NOT NULL CHECK (loadMode IN ('total','perHand','perSide','bodyweightPlus','repsOnly')),
     primaryMuscles TEXT NOT NULL DEFAULT '[]',
     secondaryMuscles TEXT NOT NULL DEFAULT '[]',
     force TEXT CHECK (force IN ('push','pull','static')),
     mechanic TEXT CHECK (mechanic IN ('compound','isolation')),
     category TEXT NOT NULL CHECK (category IN ('strength','stretching','plyometrics','powerlifting','olympicWeightlifting','strongman','cardio')),
     bodyRegion TEXT NOT NULL CHECK (bodyRegion IN ('upper','lower','core','fullBody','cardio')),
     movementPattern TEXT,
     instructions TEXT NOT NULL DEFAULT '[]',
     source TEXT NOT NULL CHECK (source IN ('library','jefit','custom')),
     libraryId TEXT REFERENCES exercise(id),
     stickyNote TEXT,
     defaultRestSeconds INTEGER NOT NULL DEFAULT 60 CHECK (defaultRestSeconds BETWEEN 0 AND 900),
     preferredUnit TEXT NOT NULL DEFAULT 'kg' CHECK (preferredUnit IN ('kg','lb')),
     isFavorite INTEGER NOT NULL DEFAULT 0 CHECK (isFavorite IN (0,1)),
     isArchived INTEGER NOT NULL DEFAULT 0 CHECK (isArchived IN (0,1)),
     createdAt TEXT NOT NULL
   );
   CREATE INDEX exercise_name ON exercise(name);

   CREATE TABLE program (
     id TEXT PRIMARY KEY NOT NULL,
     name TEXT NOT NULL CHECK (length(trim(name)) > 0),
     split TEXT NOT NULL CHECK (split IN ('fullBody','upperLower4','upperLower6','pushPullLegs3','pushPullLegs6','custom')),
     isActive INTEGER NOT NULL DEFAULT 0 CHECK (isActive IN (0,1)),
     isArchived INTEGER NOT NULL DEFAULT 0 CHECK (isArchived IN (0,1)),
     sessionsPerWeekGoal INTEGER NOT NULL DEFAULT 3 CHECK (sessionsPerWeekGoal BETWEEN 1 AND 7),
     source TEXT NOT NULL CHECK (source IN ('app','jefit')),
     externalId TEXT,
     createdAt TEXT NOT NULL,
     CHECK (NOT (isActive = 1 AND isArchived = 1))
   );
   CREATE UNIQUE INDEX program_one_active ON program(isActive) WHERE isActive = 1;
   CREATE UNIQUE INDEX program_external ON program(externalId) WHERE externalId IS NOT NULL;

   CREATE TABLE programDay (
     id TEXT PRIMARY KEY NOT NULL,
     programId TEXT NOT NULL REFERENCES program(id) ON DELETE CASCADE,
     name TEXT NOT NULL CHECK (length(trim(name)) > 0),
     focus TEXT NOT NULL CHECK (focus IN ('fullBody','upper','lower','push','pull','legs','custom')),
     position INTEGER NOT NULL CHECK (position >= 0),
     copiedFromDayId TEXT REFERENCES programDay(id) ON DELETE SET NULL,
     externalId TEXT
   );
   CREATE INDEX programDay_program ON programDay(programId, position);
   CREATE UNIQUE INDEX programDay_external ON programDay(externalId) WHERE externalId IS NOT NULL;

   CREATE TABLE dayExercise (
     id TEXT PRIMARY KEY NOT NULL,
     dayId TEXT NOT NULL REFERENCES programDay(id) ON DELETE CASCADE,
     exerciseId TEXT NOT NULL REFERENCES exercise(id),
     position INTEGER NOT NULL CHECK (position >= 0),
     targetSets INTEGER NOT NULL CHECK (targetSets BETWEEN 1 AND 20),
     repMin INTEGER NOT NULL CHECK (repMin >= 1),
     repMax INTEGER NOT NULL CHECK (repMax >= repMin),
     restSeconds INTEGER NOT NULL CHECK (restSeconds BETWEEN 0 AND 900),
     note TEXT,
     externalId TEXT
   );
   CREATE INDEX dayExercise_day ON dayExercise(dayId, position);
   CREATE UNIQUE INDEX dayExercise_external ON dayExercise(externalId) WHERE externalId IS NOT NULL;

   CREATE TABLE workout (
     id TEXT PRIMARY KEY NOT NULL,
     startedAt TEXT NOT NULL,
     endedAt TEXT,
     programDayId TEXT REFERENCES programDay(id) ON DELETE SET NULL,
     title TEXT NOT NULL,
     note TEXT,
     effort INTEGER CHECK (effort BETWEEN 1 AND 10),
     restEndsAt TEXT,
     restDurationSeconds REAL,
     source TEXT NOT NULL CHECK (source IN ('app','jefit')),
     externalId TEXT,
     CHECK (endedAt IS NULL OR endedAt >= startedAt)
   );
   CREATE UNIQUE INDEX workout_one_in_progress ON workout((endedAt IS NULL)) WHERE endedAt IS NULL;
   CREATE UNIQUE INDEX workout_external ON workout(externalId) WHERE externalId IS NOT NULL;
   CREATE INDEX workout_started ON workout(startedAt);

   CREATE TABLE workoutExercise (
     id TEXT PRIMARY KEY NOT NULL,
     workoutId TEXT NOT NULL REFERENCES workout(id) ON DELETE CASCADE,
     exerciseId TEXT NOT NULL REFERENCES exercise(id),
     position INTEGER NOT NULL CHECK (position >= 0),
     dayExerciseId TEXT REFERENCES dayExercise(id) ON DELETE SET NULL,
     targetSets INTEGER,
     repMin INTEGER,
     repMax INTEGER,
     restSeconds INTEGER NOT NULL DEFAULT 60 CHECK (restSeconds BETWEEN 0 AND 900),
     note TEXT,
     externalId TEXT
   );
   CREATE INDEX workoutExercise_workout ON workoutExercise(workoutId, position);
   CREATE INDEX workoutExercise_exercise ON workoutExercise(exerciseId);
   CREATE UNIQUE INDEX workoutExercise_external ON workoutExercise(externalId) WHERE externalId IS NOT NULL;

   CREATE TABLE workoutSet (
     id TEXT PRIMARY KEY NOT NULL,
     workoutExerciseId TEXT NOT NULL REFERENCES workoutExercise(id) ON DELETE CASCADE,
     position INTEGER NOT NULL CHECK (position >= 0),
     loadHundredths INTEGER,
     unit TEXT NOT NULL CHECK (unit IN ('kg','lb')),
     reps INTEGER NOT NULL CHECK (reps >= 0),
     type TEXT NOT NULL CHECK (type IN ('working','warmUp','failed','drop')),
     completedAt TEXT,
     rpe REAL CHECK (rpe BETWEEN 1 AND 10),
     externalId TEXT
   );
   CREATE INDEX workoutSet_exercise ON workoutSet(workoutExerciseId, position);
   CREATE UNIQUE INDEX workoutSet_external ON workoutSet(externalId) WHERE externalId IS NOT NULL;

   CREATE TABLE exerciseNote (
     id TEXT PRIMARY KEY NOT NULL,
     exerciseId TEXT NOT NULL REFERENCES exercise(id) ON DELETE CASCADE,
     date TEXT NOT NULL,
     text TEXT NOT NULL CHECK (length(trim(text)) > 0),
     source TEXT NOT NULL CHECK (source IN ('app','jefit')),
     externalId TEXT
   );
   CREATE INDEX exerciseNote_exercise ON exerciseNote(exerciseId, date);
   CREATE UNIQUE INDEX exerciseNote_external ON exerciseNote(externalId) WHERE externalId IS NOT NULL;

   CREATE TABLE bodyEntry (
     id TEXT PRIMARY KEY NOT NULL,
     date TEXT NOT NULL,
     weightHundredths INTEGER CHECK (weightHundredths > 0),
     weightUnit TEXT NOT NULL DEFAULT 'kg' CHECK (weightUnit IN ('kg','lb')),
     bodyFatPercent REAL CHECK (bodyFatPercent > 0 AND bodyFatPercent < 100),
     measurements TEXT NOT NULL DEFAULT '{}',
     source TEXT NOT NULL CHECK (source IN ('app','jefit')),
     externalId TEXT
   );
   CREATE INDEX bodyEntry_date ON bodyEntry(date);
   CREATE UNIQUE INDEX bodyEntry_external ON bodyEntry(externalId) WHERE externalId IS NOT NULL;

   CREATE TABLE setting (
     key TEXT PRIMARY KEY NOT NULL,
     value TEXT NOT NULL
   );

   CREATE TABLE importRun (
     id TEXT PRIMARY KEY NOT NULL,
     source TEXT NOT NULL,
     fileName TEXT NOT NULL,
     fileSHA256 TEXT NOT NULL,
     ranAt TEXT NOT NULL,
     report TEXT NOT NULL
   );
   ```

   Why some of these exist:
   - `workout_one_in_progress`: there can never be two open workouts.
   - `program_one_active`: there can never be two active programs.
   - The `externalId` unique indexes: running an import twice cannot duplicate anything.
   - `ON DELETE CASCADE` is limited to rows that cannot exist without their parent. Deleting
     an exercise that has history fails instead of erasing it (rulebook §10: archive,
     never delete).

2. `Records.swift`: one `nonisolated struct` per table. Each conforms to `Codable`,
   `Identifiable`, `Hashable`, `FetchableRecord` and `PersistableRecord`, sets
   `static let databaseTableName` to the table name, and has properties named exactly as the
   columns. Types:

   | Record | Notable property types |
   |---|---|
   | `ExerciseRecord` (`exercise`) | `equipment: Equipment`, `loadMode: LoadMode`, `primaryMuscles: [Muscle]`, `secondaryMuscles: [Muscle]`, `force: Force?`, `mechanic: Mechanic?`, `category: ExerciseCategory`, `bodyRegion: BodyRegion`, `movementPattern: MovementPattern?`, `instructions: [String]`, `source: ExerciseSource` (enum `library, jefit, custom`), `libraryId: String?`, `stickyNote: String?`, `defaultRestSeconds: Int`, `preferredUnit: WeightUnit`, `isFavorite: Bool`, `isArchived: Bool`, `createdAt: Date` |
   | `ProgramRecord` (`program`) | `split: Split` (enum `fullBody, upperLower4, upperLower6, pushPullLegs3, pushPullLegs6, custom`), `isActive: Bool`, `isArchived: Bool`, `sessionsPerWeekGoal: Int`, `source: RecordSource` (enum `app, jefit`), `externalId: String?`, `createdAt: Date` |
   | `ProgramDayRecord` (`programDay`) | `focus: DayFocus` (enum `fullBody, upper, lower, push, pull, legs, custom`), `position: Int`, `copiedFromDayId: String?`, `externalId: String?` |
   | `DayExerciseRecord` (`dayExercise`) | `targetSets`, `repMin`, `repMax`, `restSeconds: Int`; `note: String?` |
   | `WorkoutRecord` (`workout`) | `startedAt: Date`, `endedAt: Date?`, `programDayId: String?`, `title: String`, `note: String?`, `effort: Int?`, `restEndsAt: Date?`, `restDurationSeconds: Double?`, `source: RecordSource`, `externalId: String?` |
   | `WorkoutExerciseRecord` (`workoutExercise`) | `targetSets`, `repMin`, `repMax: Int?`; `restSeconds: Int`; `dayExerciseId: String?` |
   | `WorkoutSetRecord` (`workoutSet`) | `loadHundredths: Int?`, `unit: WeightUnit`, `reps: Int`, `type: SetType`, `completedAt: Date?`, `rpe: Double?` |
   | `ExerciseNoteRecord` (`exerciseNote`) | `date: String` (`yyyy-MM-dd`), `text: String`, `source: RecordSource` |
   | `BodyEntryRecord` (`bodyEntry`) | `date: String`, `weightHundredths: Int?`, `weightUnit: WeightUnit`, `bodyFatPercent: Double?`, `measurements: [String: Double]`, `source: RecordSource` |
   | `SettingRecord` (`setting`) | `key: String` (also its `id`), `value: String` |
   | `ImportRunRecord` (`importRun`) | `ranAt: Date`, `report: ImportReport` (from card 0.5; until then a `String`) |

   Put `ExerciseSource`, `RecordSource`, `Split` and `DayFocus` in `ExerciseTypes.swift`,
   declared like the others. For `SettingRecord`, `Identifiable` uses `var id: String { key }`.
   Ids are UUID strings (`UUID().uuidString`) unless a card gives a format.

   This pattern compiles under this project's settings. Copy it:

   ```swift
   nonisolated struct ProgramDayRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
       static let databaseTableName = "programDay"
       var id: String
       var programId: String
       var name: String
       var focus: DayFocus
       var position: Int
       var copiedFromDayId: String?
       var externalId: String?
   }
   ```

3. `AppDatabase.swift`, exactly:

   ```swift
   import Foundation
   import GRDB

   /// The app's one database. Every write goes through `writer`, so the schema's CHECK
   /// constraints and foreign keys apply to every caller.
   nonisolated final class AppDatabase: Sendable {
       let writer: any DatabaseWriter
       var reader: any DatabaseReader { writer }

       init(_ writer: any DatabaseWriter) throws {
           self.writer = writer
           try Schema.migrator.migrate(writer)
       }

       /// Application Support/GymApp/gymapp.sqlite. WAL mode, via DatabasePool.
       static func onDisk() throws -> AppDatabase {
           let folder = URL.applicationSupportDirectory.appending(path: "GymApp", directoryHint: .isDirectory)
           try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
           return try AppDatabase(DatabasePool(path: folder.appending(path: "gymapp.sqlite").path))
       }

       /// For tests and previews.
       static func inMemory() throws -> AppDatabase {
           try AppDatabase(DatabaseQueue())
       }
   }
   ```

   GRDB stores a `Date` as UTC text `yyyy-MM-dd HH:mm:ss.SSS`, arrays and dictionaries as
   JSON text, `Bool` as 0/1, and enums as their raw value. That has been checked; rely on it.

**Tests** (`SchemaTests.swift`, each on a fresh `AppDatabase.inMemory()`):

- Migrating creates exactly these tables: exercise, program, programDay, dayExercise,
  workout, workoutExercise, workoutSet, exerciseNote, bodyEntry, setting, importRun. Query
  `sqlite_master`, ignoring GRDB's own `grdb_migrations`.
- An `ExerciseRecord` with two primary muscles round-trips unchanged, and the raw
  `primaryMuscles` column reads back as `["chest","triceps"]`.
- Each of these inserts throws:
  - a second workout with `endedAt == nil`;
  - a second program with `isActive == true`;
  - a set with `reps = -1`;
  - a set with `unit = 'st'` (raw SQL);
  - a workout whose `endedAt` is before `startedAt`;
  - an exercise named `"   "`;
  - a `workoutExercise` whose `exerciseId` does not exist.
- Deleting a workout deletes its workout exercises and sets. Deleting an exercise that a
  workout exercise references throws.

**Done when:** the tests pass.

**Out of scope:** seeding data; any UI; wiring the database into the app (card 0.6).

---

## Card 0.3: Library and exercise-map files

**Goal:** the two bundled JSON files load, and the 876 library exercises land in the database
once.

**Files:** create `GymApp/Library/ExerciseDefinition.swift`, `GymApp/Library/LibrarySeeder.swift`
and `GymAppTests/LibraryTests.swift`.

**Steps:**

1. `ExerciseDefinition` is a `nonisolated struct: Decodable` covering the fields both
   files share:
   - `name: String`, `equipment: Equipment`, `loadMode: LoadMode`;
   - `primaryMuscles: [Muscle]`, `secondaryMuscles: [Muscle]`;
   - `force: Force?`, `mechanic: Mechanic?`, `category: ExerciseCategory`;
   - `bodyRegion: BodyRegion`, `movementPattern: MovementPattern?`.

   Then:
   - `LibraryEntry` (for `exercises.json`) adds `id: String` and `instructions: [String]`.
   - `JEFITMapEntry` (for `jefit_exercise_map.json`) adds:
     - `jefitId: String`, `libraryId: String?`, `jefitLogCount: Int`;
     - `importWeights: ImportWeights` (enum `keep, drop`);
     - `negateOnImport: Bool`, `skipOnImport: Bool`, `note: String?`.

   Each file is an object `{ "source": String, "exercises": [...] }`. Decode the whole
   file with a wrapper struct, and decode the shared fields with nested decoding or
   duplicated properties, whichever compiles cleanly. A decode failure must name the file.

2. `LibrarySeeder.seed(in db: Database, bundle: Bundle = .main, now: Date) throws -> Int`:
   - Reads `exercises.json` from the bundle.
   - Inserts every entry as an `ExerciseRecord`:
     - `source = .library`, `id` = the entry's id;
     - `defaultRestSeconds` 60, `preferredUnit` `.kg`;
     - `isFavorite` and `isArchived` false;
     - `createdAt = now`.
   - Uses `insert(db, onConflict: .ignore)`, so seeding twice changes nothing.
   - Returns the number of rows actually inserted (`db.changesCount` after each insert).

3. In `JEFITMapEntry`, add `var exerciseId: String { "jefit:\(jefitId)" }`. Card 0.5 uses
   it as the database id for imported exercises.

**Tests:**

- `exercises.json` decodes 876 entries, and `jefit_exercise_map.json` decodes 199. Load both
  from the app bundle: `Bundle(for:)` does not apply to Swift Testing structs, so use
  `Bundle.main` (the test host is the app).
- Seeding an empty database inserts 876 rows; seeding again inserts 0, and the table still
  has 876.
- `lib:Barbell_Squat` reads back with equipment `.barbell`, loadMode `.total`, bodyRegion
  `.lower`, and primary muscles `[.quadriceps]`.
- Every non-nil `libraryId` in the map matches an id in `exercises.json`.

**Done when:** the tests pass.

**Out of scope:** importing JEFIT exercises (card 0.5); UI.

---

## Card 0.4: JEFIT CSV reader

**Goal:** parse a JEFIT export into named tables, with the same output as
`tools/jefit_parse.py`.

**Files:** create `GymApp/Import/JEFITExport.swift` and `GymAppTests/JEFITExportTests.swift`.

**Steps:**

1. API:

   ```swift
   nonisolated struct JEFITExport {
       struct Table: Equatable { let header: [String]; var rows: [[String: String]] }
       /// Section name ("EXERCISE LOGS") to its tables, in order of first appearance.
       let sections: [String: [Table]]
       init(data: Data) throws
       /// The rows of the first table in `section` whose header contains `column`; [] if none.
       func rows(_ section: String, withColumn column: String) -> [[String: String]]
   }
   ```

2. Algorithm (UTF-8 input, LF or CRLF line endings):
   1. **Tokenise the whole file into records with an RFC 4180 state machine,** not line by
      line. Quoted fields can contain commas, newlines (day names and notes do) and `""`
      for a literal quote. A record ends at a newline outside quotes.
   2. Walk the records:
      - A record with exactly one field matching `^### (.+?) #+$` opens a section; its name
        is the capture, trimmed.
      - A record with exactly one field made only of `#` closes it.
      - A record whose single field is empty is a **block break**.
      - Inside a section, the first record after a block break (or after the opener) is a
        header, and the records after it are data rows, until the next block break.
   3. A data row becomes `[header[i]: field[i]]`. Missing trailing fields are `""`; extra
      fields are ignored.
   4. ROUTINES repeats its header before every row. **Blocks with an identical header merge
      into one table**, in file order. Different headers make different tables.
   5. Text outside any section is ignored. If the file contains no section at all, throw
      `JEFITExportError.notAJEFITExport`.

**Tests:**

- `jefit_mini.csv` gives these sections and table row counts:
  - SETTING [1]
  - PROFILE [1]
  - ROUTINES [1, 1, 2]
  - WORKOUT SESSIONS [2]
  - EXERCISE LOGS [5]
  - EXERCISE SET LOGS [7]
  - EXERCISE RECORDS [1]
  - FAVORITE EXERCISES [1]
  - NOTES [3]

  CARDIO LOGS, CARDIO EXERCISE LOGS and CUSTOM EXERCISES are present with no tables.
- In the mini file:
  - the ROUTINES day's `name` is `"Day A\nwith a newline"`;
  - the first NOTES row's `mynote` is `"Seat level 4\nKeep elbows \"tucked\""`.
- `rows("EXERCISE LOGS", withColumn: "ename").count == 5`.
- **Real export, enabled only if `data/jefit/jefit-export-2026-10-11.csv` exists.** Table row
  counts:
  - PROFILE 66
  - ROUTINES 2, 32, 198
  - WORKOUT SESSIONS 492
  - EXERCISE LOGS 2552
  - EXERCISE SET LOGS 1934
  - EXERCISE RECORDS 203
  - CARDIO LOGS 25
  - CARDIO EXERCISE LOGS 12
  - CUSTOM EXERCISES 6
  - FAVORITE EXERCISES 3
  - NOTES 247
- Data that is not a JEFIT export (`"a,b\n1,2\n"`) throws `notAJEFITExport`.

**Done when:** the tests pass.

**Out of scope:** interpreting values; the importer.

---

## Card 0.5: JEFIT importer

**Goal:** turn a parsed export into database rows, following the rules below exactly. The
counts and skip reasons must equal `tools/reference_import.py`'s.

**Files:** create `GymApp/Import/JEFITImporter.swift`, `GymApp/Import/ImportReport.swift` and
`GymAppTests/JEFITImporterTests.swift`.

**Steps:**

1. Report type:

   ```swift
   nonisolated struct ImportReport: Codable, Equatable {
       var inserted: [String: Int] = [:]        // table name → rows inserted
       var alreadyPresent: [String: Int] = [:]  // table name → rows skipped because they exist
       var skipped: [String: Int] = [:]         // SkipReason.rawValue → count
       var unmappedExercises: [String] = []     // "belongSys:eid name" not in the map
   }
   ```

   `SkipReason` is a `nonisolated enum: String`. Use these raw values character for
   character, because tests compare them with the Python output:

   ```
   exercise: cardio, not supported yet
   dayExercise: cardio, not supported yet
   dayExercise: exercise never logged, so not in the exercise map
   exercise log: cardio, not supported yet
   exercise log: exercise missing from the map
   exercise log: no sets left
   set: zero reps
   set row: no matching exercise log
   set row: duplicate set index, later row kept
   workout: empty in JEFIT (no exercises logged)
   workout: only cardio or empty exercise logs
   note: not attached to an exercise
   note: empty
   note: exercise not imported
   favourite: exercise not imported
   section: CARDIO LOGS, not supported yet
   section: CARDIO EXERCISE LOGS, not supported yet
   section: EXERCISE RECORDS, derived instead (rulebook §5)
   ```

2. Entry point:
   `nonisolated enum JEFITImporter { static func run(_ export: JEFITExport, map: [JEFITMapEntry], in db: Database, now: Date) throws -> ImportReport }`.
   - It runs inside one `writer.write` transaction supplied by the caller. Any thrown error
     rolls back everything.
   - **The library must already be seeded.** `exercise.libraryId` is a foreign key into the
     library rows, and instructions are copied from them. Start by checking for at least one
     `source = 'library'` row, and throw `JEFITImportError.libraryNotSeeded` if there is
     none. Every importer test calls `LibrarySeeder.seed` first.
   - **Idempotent.** Every row has an `externalId`, or for exercises a fixed `id`. When it
     already exists, count it in `alreadyPresent` and do not write it. For a workout that
     already exists, count that one workout and skip its exercises and sets entirely.

3. **The rules.** `tools/reference_import.py` implements the same; read it alongside.
   "Map entry" means the `JEFITMapEntry` whose `jefitId` is `"<belongSys>:<eid>"`.

   1. **Exercises.**
      - For every map entry with `skipOnImport == false`, insert an `ExerciseRecord`:
        - `id = "jefit:<jefitId>"`, `source = .jefit`;
        - name, equipment, loadMode, muscles, force, mechanic, category, bodyRegion and
          movementPattern from the entry;
        - `libraryId` from the entry;
        - `instructions` copied from the library row with that id (fetched from the
          database) if `libraryId` is set, else `[]`;
        - `defaultRestSeconds` = the SETTING `timer` (60 if blank);
        - `preferredUnit = .kg` if SETTING `mass` trims to `kg`, else `.lb`.
      - Entries with `skipOnImport == true` add one each to *exercise: cardio, not supported
        yet*.
   2. **Programs** (ROUTINES table with column `difficulty`): one `ProgramRecord` per row:
      - `name` trimmed, `split = .custom`, `source = .jefit`;
      - `isActive = false`, `isArchived = true`;
      - `externalId = "jefit:routine:<_id>"`.
   3. **Days** (ROUTINES table with column `dayIndex`): one `ProgramDayRecord` per row:
      - `programId` = the program whose `_id` equals the row's `package`;
      - `name` = the name with whitespace and newlines trimmed from both ends;
      - `focus = .custom`;
      - `externalId = "jefit:day:<_id>"`;
      - `position` = rank within its program after sorting by `sort_order` then `_id`,
        both numeric, starting at 0.
   4. **Day exercises** (ROUTINES table with column `exercisename`): for each row, find the
      map entry for `"<belongSys>:<exercise_id>"`.
      - No entry: skip with *dayExercise: exercise never logged…*.
      - Entry with `skipOnImport`: skip with *dayExercise: cardio…*.
      - Otherwise insert a `DayExerciseRecord`:
        - `dayId` = the day whose `_id` is the row's `belongplan`;
        - `position` = rank within the day by `mysort` then `_id`;
        - `targetSets = clamp(Int(setcount) ?? 1, 1, 20)`;
        - `repMin`/`repMax` = min/max of the positive integers in `targetrep`
          (comma-separated), or 10/10 if there are none;
        - `restSeconds = clamp(Int(timer) ?? 60, 0, 900)`;
        - `externalId = "jefit:item:<_id>"`.
   5. **Set rows** (EXERCISE SET LOGS): group by `exercise_log_id`, keyed by `set_index`.
      - When two rows share a `set_index`, the later one in the file wins; count one
        *set row: duplicate set index…* per extra row.
      - Rows whose `exercise_log_id` matches no exercise log count *set row: no matching
        exercise log*.
   6. **Workouts.** Process WORKOUT SESSIONS sorted by `starttime`. For each session, take
      its exercise logs (`belongsession == _id`) sorted by numeric `_id`. For each log:
      - **Map lookup.** No map entry: skip with *exercise log: exercise missing from the
        map*, and append `"<belongSys>:<eid> <ename>"` to `unmappedExercises` once. An entry
        with `skipOnImport`: skip with *exercise log: cardio…*.
      - **Raw sets.**
        - If the log has set rows, they are canonical (JEFIT_EXPORT.md trap 1). Take them
          in `set_index` order:
          - `kg = Double(weight_lbs) × 0.45359237`, or 0 when blank;
          - `reps = Int(reps) ?? 0`;
          - type `default` → `.working`, `warm-up` → `.warmUp`, `failure` → `.failed`,
            anything else → `.working`;
          - `completedAt` = `log_time` as Unix seconds.
        - Otherwise split `logs` on commas. Each token is `"<kg>x<reps>"`, giving type
          `.working` and `completedAt` = the session's `starttime`.
      - **Per raw set:**
        - Reps ≤ 0: skip with *set: zero reps*.
        - Else if the entry's `importWeights == .drop`: `loadHundredths` is `nil` when
          `loadMode == .repsOnly`, otherwise `0`.
        - Else: negate `kg` when `negateOnImport`, and
          `loadHundredths = Int((kg × 100).rounded())`. This rounding is what turns 44.0924 lb
          into exactly 2000 and `39.9999` into 4000.
        - `unit = .kg`. `position` = index among the sets kept.
        - `externalId = "jefit:set:<logId>:<n>"`, where `n` is the set's position.
      - **No sets kept:** skip the log with *exercise log: no sets left*.
      - **Otherwise insert a `WorkoutExerciseRecord`:**
        - `externalId = "jefit:log:<_id>"`; `position` = index among the logs kept.
        - Its day item is the dayExercise with `externalId == "jefit:item:<day_item_id>"`,
          if one was imported. When it exists:
          - `dayExerciseId` is that dayExercise;
          - `targetSets`, `repMin` and `repMax` are copied from it;
          - `restSeconds` is its rest.
        - With no day item, those three are `nil` and `restSeconds = 60`.
      - **A session with no logs kept** is not inserted. Count *workout: empty in JEFIT…* if
        it had no logs at all, otherwise *workout: only cardio or empty exercise logs*.
      - **Otherwise insert a `WorkoutRecord`:**
        - `startedAt` = `starttime` and `endedAt` = `endtime`, both Unix seconds;
        - `source = .jefit`, `externalId = "jefit:session:<_id>"`;
        - `programDayId` = the day that most of its kept logs' day items belong to. Break a
          tie with the first such log in `_id` order; use `nil` when no log has a day item;
        - `title` = that day's name, or `"Workout"` without one.
   7. **Notes** (NOTES), in this order of checks:
      - `eid` blank or `0`: *note: not attached to an exercise*.
      - `mynote` empty after trimming: *note: empty*.
      - Exercise `"jefit:<belongSys>:<eid>"` not imported: *note: exercise not imported*.
      - Otherwise insert an `ExerciseNoteRecord`: `date = mydate`, `text` = `mynote` trimmed,
        `source = .jefit`, `externalId = "jefit:note:<_id>"`.
      - Afterwards, set each exercise's `stickyNote` to the text of its newest note (latest
        `date`, then highest `_id`), **only if `stickyNote` is still nil**, so a re-import
        never overwrites an edit.
   8. **Body entries** (PROFILE): one `BodyEntryRecord` per row:
      - `date = mydate`, `externalId = "jefit:profile:<_id>"`;
      - `weightHundredths = round(weight × 100)` if weight > 0, else nil;
      - `weightUnit` from SETTING `mass`, as for exercises;
      - `bodyFatPercent = fatpercent` if > 0, else nil;
      - `measurements` = `["<column>Cm": value]` for each of chest, arms, waist, calves,
        height, hips, thighs, shoulders, neck and forearms where value > 0. When SETTING
        `length` trims to `inches`, multiply by 2.54 and round to 1 decimal place.
   9. **Favourites** (FAVORITE EXERCISES): for each row, set `isFavorite = true` on
      `"jefit:<belongSys>:<exercise_id>"` if it was imported. Otherwise count *favourite:
      exercise not imported*.
   10. **Settings:** write each key only if absent:
       - `defaultRestSeconds` = `timer`;
       - `weightUnit` = `kg` or `lb` from `mass`;
       - `weekStartsOn` = `sunday` when `week_start` is 7, otherwise `monday`;
       - `lastTimeSource` = `sameDay` when `lastlogs` is 1, otherwise `anyWorkout`.
   11. **Whole sections not imported:** add their row counts to the three *section: …*
       reasons.
   12. Insert an `ImportRunRecord`, with the report as JSON, the file's SHA-256 (passed in by
       the caller) and `ranAt = now`.

**Tests** (`JEFITImporterTests.swift`). Load the map from the bundle and run each import into
a fresh in-memory database:

- **Mini fixture** against `jefit_mini_expected.json`:
  - Row counts per table equal `counts`. Compare `exercise`, `program`, `programDay`,
    `dayExercise`, `workout`, `workoutExercise`, `workoutSet`, `exerciseNote` and `bodyEntry`
    by `fetchCount`. Compare `workoutsLinkedToADay`, `exercisesWithStickyNote` and
    `favoriteExercises` by SQL count.
  - `report.skipped` equals `skips`, ignoring zero values on both sides.
- **Mini fixture, specific rows:**
  - The pushdown exercise has sets `[(2700, 15, warmUp), (4500, 10, failed)]` as
    `(loadHundredths, reps, type)`.
  - Bench has `[(4000, 5, working), (6000, 3, working)]`.
  - The assisted pull-up has `[(-4500, 6, working)]`.
  - The knee raise has `[(nil, 7, working)]`.
  - Bench's `stickyNote` is `"Newer note"`.
  - The workout's `title` is `"Day A\nwith a newline"` trimmed, i.e. unchanged; its
    `programDayId` is that day.
- **Mini fixture, idempotency:** importing twice leaves every count unchanged.
  `alreadyPresent["workout"] == 1` on the second run, and `inserted` holds no positive
  value except `importRun`.
- **Real export** (skip when absent) against `jefit_expected.json`:
  - all `counts` and `skips`, as above;
  - every workout in `workouts`: fetch by `externalId` and compare `startedAt`/`endedAt` as
    Unix seconds, the program day's `externalId`, and each exercise's `exerciseId` and sets
    `[loadHundredths, reps, type]` in order;
  - every entry in `exercises`:
    - set count;
    - `heaviestHundredths` and `bestE1RMKg` where given, from `TrainingMath.bests` over the
      exercise's sets. Build each `PastSet` with `kg = loadHundredths / 100` and compare
      `bestE1RM` rounded to 2 decimal places;
    - the `allLoads…` flags.
- **Real export:** the importer finishes in under 10 seconds on the simulator. Measure with
  `ContinuousClock`; this guards against per-row queries in loops.

**Done when:** all tests pass, including the real-export ones on this machine.

**Out of scope:** UI; reading files from disk (the caller passes `JEFITExport`); cardio.

---

## Card 0.6: Wire the database into the app, and an import screen

**Goal:** the app opens its database at launch, seeds the library, and can import a JEFIT
file from Files or from a launch argument. It then shows the report.

**Files:**

- create `GymApp/App/AppEnvironment.swift`
- create `GymApp/Import/ImportService.swift`
- create `GymApp/Import/ImportReportView.swift`
- change `GymApp/App/GymAppApp.swift`
- change `GymApp/Prototype/Views/HomeView.swift` (toolbar item only)

**Steps:**

1. `AppEnvironment.swift`: an `EnvironmentValues` entry
   `@Entry var appDatabase: AppDatabase? = nil`. In `GymAppApp`, create
   `AppDatabase.onDisk()` once, then run `LibrarySeeder.seed` in `writer.write`. Inject it
   with `.environment(\.appDatabase, db)`. If opening fails, show a full-screen error view
   with the error's description; never crash.
2. `ImportService`:

   ```swift
   nonisolated enum ImportService {
       static func importJEFIT(fileAt url: URL, into db: AppDatabase) async throws -> ImportReport
   }
   ```

   It reads the data, computes its SHA-256 with `CryptoKit.SHA256`, parses `JEFITExport`, and
   decodes the map from the bundle. Then it runs `JEFITImporter.run` inside
   `try await db.writer.write { … }` and returns the report. It calls
   `url.startAccessingSecurityScopedResource()` and stops in a `defer` (files from
   `.fileImporter` need this).
3. `HomeView`: add a toolbar menu (`ellipsis.circle`) with **Import JEFIT export…**, opening
   `.fileImporter(allowedContentTypes: [.commaSeparatedText, .plainText, .data])`. Run the
   import in a `Task`, show a progress overlay while it runs, then present
   `ImportReportView`. An error shows an alert with its description.
4. `ImportReportView`: a `List` in a sheet with four sections:
   - **Imported**: table name → count, non-zero only.
   - **Already in the app**: the same, from `alreadyPresent`.
   - **Skipped**: reason → count, sorted by reason.
   - **Unmapped exercises**: shown only when the list is non-empty.

   Then a footer that re-reads the database: "Database now holds N workouts, N sets and
   N exercises", where exercises counts `source != 'library'`. A Done button closes it.
5. Launch argument, for verification on the simulator: in `#if DEBUG`, when
   `ProcessInfo.processInfo.arguments` contains `-importJEFIT` followed by a path, import that
   file after the database opens and present the report.

**Done when:**

- Tests still pass.
- On the simulator:

  ```bash
  xcrun simctl terminate "iPhone 17 Pro Max" com.fuaadshurie.GymApp
  xcrun simctl launch "iPhone 17 Pro Max" com.fuaadshurie.GymApp -importJEFIT "$PWD/data/jefit/jefit-export-2026-10-11.csv"
  ```

  shows a report with 468 workouts and 7,751 sets inserted. Take a screenshot.
- Running the same command again shows 0 inserted and 468 workouts already present.
- The prototype still works.

**Out of scope:** new tabs or navigation; any change to the prototype's workout flow.

---

## Card 0.7: Phase close

**Steps:**

1. Run the full test suite and the simulator import from 0.6 once more, from a clean install.
   Uninstall the app first with `xcrun simctl uninstall "iPhone 17 Pro Max" com.fuaadshurie.GymApp`.
2. In README.md, change phase 0's state to **done**, and mention the import numbers in "What
   exists today".
3. In ROADMAP.md, tick phase 0.
4. In HANDOFF.md, record anything learned that the next phase should know.

**Done when:** the above is committed.
