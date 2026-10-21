import Foundation
import GRDB

/// The schema, as one migration per version. Never edit a shipped migration: add a new one.
nonisolated enum Schema {
    /// Every migration identifier, oldest first. A backup is valid with any leading run of them.
    static let versions = ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11"]

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: v1)
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: "ALTER TABLE workoutSet ADD COLUMN note TEXT")
            try db.execute(sql: "ALTER TABLE workoutSet ADD COLUMN repsInReserve INTEGER CHECK (repsInReserve BETWEEN 0 AND 3)")
            try db.execute(sql: "ALTER TABLE workoutSet ADD COLUMN annotations TEXT NOT NULL DEFAULT '[]'")
        }
        migrator.registerMigration("v3") { db in
            // Card 6.2: daily totals read from Apple Health. One row per local day.
            try db.execute(sql: """
                CREATE TABLE healthDay (
                  date TEXT PRIMARY KEY NOT NULL CHECK (length(date) = 10),
                  steps INTEGER CHECK (steps >= 0),
                  weightHundredths INTEGER CHECK (weightHundredths > 0),
                  weightUnit TEXT CHECK (weightUnit IN ('kg','lb')),
                  source TEXT NOT NULL DEFAULT 'health',
                  CHECK ((weightHundredths IS NULL) = (weightUnit IS NULL))
                )
                """)
        }
        migrator.registerMigration("v4") { db in
            // Card 6.3: what was decided about each studio suggestion. An accepted target keeps
            // its load as entered in the studio (hundredths plus unit).
            try db.execute(sql: """
                CREATE TABLE studioDecision (
                  suggestionId TEXT PRIMARY KEY NOT NULL CHECK (length(suggestionId) > 0),
                  kind TEXT NOT NULL CHECK (kind IN ('target','swap','note')),
                  decision TEXT NOT NULL CHECK (decision IN ('accepted','dismissed')),
                  decidedAt TEXT NOT NULL,
                  title TEXT NOT NULL,
                  exerciseId TEXT,
                  loadHundredths INTEGER,
                  unit TEXT CHECK (unit IN ('kg','lb')),
                  reps INTEGER CHECK (reps > 0),
                  CHECK ((loadHundredths IS NULL) = (unit IS NULL))
                )
                """)
            try db.execute(sql: "CREATE INDEX studioDecision_exercise ON studioDecision(exerciseId, decidedAt)")
        }
        migrator.registerMigration("v5") { db in
            // Card 7.6: supersets. Members share a group id; the rest between members is
            // supersetRestSeconds, and the last member's own rest follows the round.
            for table in ["dayExercise", "workoutExercise"] {
                try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN supersetGroup TEXT")
                try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN supersetRestSeconds INTEGER NOT NULL DEFAULT 0 CHECK (supersetRestSeconds BETWEEN 0 AND 900)")
            }
        }
        migrator.registerMigration("v6") { db in
            // Card 7.7: whether a day item builds warm-up sets when a workout starts.
            try db.execute(sql: "ALTER TABLE dayExercise ADD COLUMN warmUps INTEGER NOT NULL DEFAULT 0 CHECK (warmUps IN (0,1))")
        }
        migrator.registerMigration("v7") { db in
            // Card 8.3: decisions on `fix` suggestions. SQLite can't change a CHECK, so the
            // table is rebuilt with every row kept.
            try db.execute(sql: """
                CREATE TABLE studioDecisionNew (
                  suggestionId TEXT PRIMARY KEY NOT NULL CHECK (length(suggestionId) > 0),
                  kind TEXT NOT NULL CHECK (kind IN ('target','swap','note','fix')),
                  decision TEXT NOT NULL CHECK (decision IN ('accepted','dismissed')),
                  decidedAt TEXT NOT NULL,
                  title TEXT NOT NULL,
                  exerciseId TEXT,
                  loadHundredths INTEGER,
                  unit TEXT CHECK (unit IN ('kg','lb')),
                  reps INTEGER CHECK (reps > 0),
                  CHECK ((loadHundredths IS NULL) = (unit IS NULL))
                );
                INSERT INTO studioDecisionNew SELECT suggestionId, kind, decision, decidedAt, title, exerciseId, loadHundredths, unit, reps FROM studioDecision;
                DROP TABLE studioDecision;
                ALTER TABLE studioDecisionNew RENAME TO studioDecision;
                CREATE INDEX studioDecision_exercise ON studioDecision(exerciseId, decidedAt);
                """)
        }
        migrator.registerMigration("v8") { db in
            // Card 10.4: form cues. formCueSeed marks an exercise as seeded from its library
            // instructions, so a deleted library cue is never seeded back.
            try db.execute(sql: """
                CREATE TABLE formCue (
                  id TEXT PRIMARY KEY NOT NULL,
                  exerciseId TEXT NOT NULL REFERENCES exercise(id) ON DELETE CASCADE,
                  kind TEXT NOT NULL CHECK (kind IN ('setup','movement','mistake')),
                  text TEXT NOT NULL CHECK (length(trim(text)) > 0),
                  position INTEGER NOT NULL CHECK (position >= 0),
                  showOnOpen INTEGER NOT NULL DEFAULT 0 CHECK (showOnOpen IN (0,1)),
                  source TEXT NOT NULL CHECK (source IN ('library','owner'))
                );
                CREATE INDEX formCue_exercise ON formCue(exerciseId, position);
                CREATE TABLE formCueSeed (
                  exerciseId TEXT PRIMARY KEY NOT NULL REFERENCES exercise(id) ON DELETE CASCADE
                );
                """)
        }
        migrator.registerMigration("v9") { db in
            // Redesign card R.0: how often each screen opens and each key button is tapped.
            // Kept on the device only; exported from Settings as CSV.
            try db.execute(sql: """
                CREATE TABLE usageCount (
                  key TEXT PRIMARY KEY NOT NULL CHECK (length(key) > 0),
                  count INTEGER NOT NULL CHECK (count >= 0),
                  lastAt TEXT NOT NULL
                )
                """)
        }
        migrator.registerMigration("v10") { db in
            // docs/backend/01-plan.md: the sync outbox. Triggers record every change to a set,
            // from any writer, but only once sync is enabled; enabling backfills the outbox.
            // `applying` is set while pulled rows are written, so they are not sent back.
            try db.execute(sql: """
                CREATE TABLE syncState (
                  key TEXT PRIMARY KEY NOT NULL,
                  value TEXT NOT NULL
                );
                CREATE TABLE syncChange (
                  seq INTEGER PRIMARY KEY AUTOINCREMENT,
                  tableName TEXT NOT NULL,
                  rowId TEXT NOT NULL,
                  op TEXT NOT NULL CHECK (op IN ('upsert','delete')),
                  changedAtMs INTEGER NOT NULL
                );
                CREATE INDEX syncChange_row ON syncChange(tableName, rowId);
                CREATE TABLE syncParked (
                  rowId TEXT PRIMARY KEY NOT NULL,
                  payload BLOB NOT NULL
                );
                """)
            let when = "WHEN EXISTS (SELECT 1 FROM syncState WHERE key = 'enabled') AND NOT EXISTS (SELECT 1 FROM syncState WHERE key = 'applying')"
            let now = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)"
            for (event, row, op) in [("INSERT", "NEW", "upsert"), ("UPDATE", "NEW", "upsert"), ("DELETE", "OLD", "delete")] {
                try db.execute(sql: """
                    CREATE TRIGGER workoutSet_sync_\(event.lowercased()) AFTER \(event) ON workoutSet \(when) BEGIN
                      INSERT INTO syncChange (tableName, rowId, op, changedAtMs) VALUES ('workoutSet', \(row).id, '\(op)', \(now));
                    END
                    """)
            }
        }
        migrator.registerMigration("v11") { db in
            // Exercises, workouts and their exercises sync too. A bundled library exercise is
            // recorded only once it is changed here (seeding inserts with OR IGNORE, so it never
            // fires). Parked rows are now keyed by table as well as id.
            try db.execute(sql: """
                DROP TABLE syncParked;
                CREATE TABLE syncParked (
                  tableName TEXT NOT NULL,
                  rowId TEXT NOT NULL,
                  payload BLOB NOT NULL,
                  PRIMARY KEY (tableName, rowId)
                );
                """)
            let when = "EXISTS (SELECT 1 FROM syncState WHERE key = 'enabled') AND NOT EXISTS (SELECT 1 FROM syncState WHERE key = 'applying')"
            let now = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)"
            for table in ["exercise", "workout", "workoutExercise"] {
                for (event, row, op) in [("INSERT", "NEW", "upsert"), ("UPDATE", "NEW", "upsert"), ("DELETE", "OLD", "delete")] {
                    let extra = table == "exercise" && event == "INSERT" ? " AND NEW.source != 'library'" : ""
                    try db.execute(sql: """
                        CREATE TRIGGER \(table)_sync_\(event.lowercased()) AFTER \(event) ON \(table) WHEN \(when)\(extra) BEGIN
                          INSERT INTO syncChange (tableName, rowId, op, changedAtMs) VALUES ('\(table)', \(row).id, '\(op)', \(now));
                        END
                        """)
                }
            }
        }
        return migrator
    }

    /// docs/specs/00-foundation.md, card 0.2. The partial unique indexes make "one workout in
    /// progress" and "one active program" true for every writer, not just the UI.
    private static let v1 = """
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
        """
}
