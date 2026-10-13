CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
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
   , note TEXT, repsInReserve INTEGER CHECK (repsInReserve BETWEEN 0 AND 3), annotations TEXT NOT NULL DEFAULT '[]');
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
