import Foundation
import GRDB
import Testing
@testable import GymApp

struct SetMetadataTests {
    @Test func anInterruptedDraftIsReplayedAndOlderSavesCannotEraseIt() throws {
        let app = try AppDatabase.inMemory()
        let id = try app.writer.write { db in
            try TestData.exercise(db, id: "draft-bench", name: "Bench")
            let workout = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: .now)
            let item = try WorkoutWrites.addExercise(db, workoutId: workout.id, exerciseId: "draft-bench", settings: AppSettings())
            return try WorkoutSetRecord.filter(Column("workoutExerciseId") == item.id).fetchOne(db)!.id
        }
        let older = MetadataDraft(kind: .set, id: id, note: "First edit", reserve: 2)
        let newer = MetadataDraft(kind: .set, id: id, note: "Final edit after interruption", reserve: 1, annotations: [.form])
        try older.persist()
        try newer.persist()
        try older.clearIfCurrent()
        try MetadataDraft.replay(into: app)
        let saved = try app.reader.read { try WorkoutSetRecord.fetchOne($0, key: id)! }
        #expect(saved.note == newer.note && saved.repsInReserve == 1 && saved.annotations == [.form])
    }
    @Test func metadataSurvivesBackupAndNewSetsDoNotInheritIt() throws {
        let db = try AppDatabase.inMemory()
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try RecoveryStore(folder: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ids = try db.writer.write { db in
            try TestData.exercise(db, id: "bench", name: "Bench")
            let workout = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: .now)
            let item = try WorkoutWrites.addExercise(db, workoutId: workout.id, exerciseId: "bench", settings: AppSettings())
            let set = try WorkoutSetRecord.filter(Column("workoutExerciseId") == item.id).fetchOne(db)!
            try WorkoutWrites.setMetadata(db, setId: set.id, note: "Seat 4\n左 shoulder", reserve: 1, annotations: [.form, .injury])
            try WorkoutWrites.setExerciseNote(db, itemId: item.id, note: "Session only")
            let added = try WorkoutWrites.addSet(db, workoutExerciseId: item.id, settings: AppSettings())
            #expect(added.note == nil && added.repsInReserve == nil && added.annotations.isEmpty)
            return (set.id, item.id)
        }
        let backup = try db.reader.read { try store.capture($0) }
        let copy = try AppDatabase(DatabaseQueue(path: backup.path))
        try copy.reader.read { db throws -> Void in
            let set = try #require(try WorkoutSetRecord.fetchOne(db, key: ids.0))
            #expect(set.note == "Seat 4\n左 shoulder" && set.repsInReserve == 1)
            #expect(set.annotations == [.injury, .form])
            #expect(try WorkoutExerciseRecord.fetchOne(db, key: ids.1)?.note == "Session only")
        }
    }
    @Test func invalidReserveRollsBackWithoutChangingTheSet() throws {
        let app = try AppDatabase.inMemory()
        let id = try app.writer.write { db in
            try TestData.exercise(db, id: "bench", name: "Bench")
            let w = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: .now)
            let item = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "bench", settings: AppSettings())
            return try WorkoutSetRecord.filter(Column("workoutExerciseId") == item.id).fetchOne(db)!.id
        }
        #expect(throws: (any Error).self) {
            try app.writer.write { try WorkoutWrites.setMetadata($0, setId: id, note: "Should roll back", reserve: 4, annotations: []) }
        }
        let set = try app.reader.read { try WorkoutSetRecord.fetchOne($0, key: id)! }
        #expect(set.note == nil && set.repsInReserve == nil)
    }
    @Test func customAndDifferentVariantsHaveNoMediaSubstitution() throws {
        let app = try AppDatabase.inMemory()
        try app.writer.write { db throws -> Void in
            let custom = try TestData.exercise(db, id: "custom:bench", name: "Barbell Bench Press")
            #expect(ExerciseMedia.asset(for: custom) == nil)
            var bench = custom
            bench.id = "jefit:1:2"; bench.equipment = .barbell
            #expect(ExerciseMedia.asset(for: bench)?.name == "barbell-bench")
            #expect(ExerciseMedia.asset(for: bench)?.still != nil)
            #expect(ExerciseMedia.asset(for: bench)?.video != nil)
            bench.equipment = .smith
            #expect(ExerciseMedia.asset(for: bench) == nil)
            bench.id = "lib:Front_Barbell_Squat"; bench.equipment = .barbell
            #expect(ExerciseMedia.asset(for: bench) == nil)
        }
    }
    @Test func reserveAndAnnotationsDoNotInventRepsOrChangeVolume() throws {
        let app = try AppDatabase.inMemory()
        try app.writer.write { db throws -> Void in
            try TestData.exercise(db, id: "bench", name: "Bench")
            let workout = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: .now)
            let item = try WorkoutWrites.addExercise(db, workoutId: workout.id, exerciseId: "bench", settings: AppSettings())
            let set = try WorkoutSetRecord.filter(Column("workoutExerciseId") == item.id).fetchOne(db)!
            try WorkoutWrites.updateSet(db, setId: set.id, edit: SetEdit(loadHundredths: 6000, unit: .kg, reps: 8, type: .working))
            try WorkoutWrites.logSet(db, setId: set.id, now: .now)
            try WorkoutWrites.finish(db, workoutId: workout.id, now: .now)
            try WorkoutWrites.setMetadata(db, setId: set.id, note: "Controlled form", reserve: 3, annotations: [.deload, .injury, .form])
            #expect(try SummaryQueries.summary(db, workoutId: workout.id).volumeKg == 480)
            #expect(try SummaryQueries.summary(db, workoutId: workout.id).setCount == 1)
            try WorkoutWrites.updateSet(db, setId: set.id, edit: SetEdit(loadHundredths: 6000, unit: .kg, reps: 8, type: .warmUp))
            #expect(try SummaryQueries.summary(db, workoutId: workout.id).volumeKg == 0)
            #expect(try SummaryQueries.summary(db, workoutId: workout.id).setCount == 0)
        }
    }

    @Test func v1HistorySurvivesTheMetadataMigration() throws {
        let queue = try DatabaseQueue()
        let app = try AppDatabase(queue)
        let id = try app.writer.write { db in
            try TestData.exercise(db, id: "bench", name: "Bench")
            let workout = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: .now)
            let item = try WorkoutWrites.addExercise(db, workoutId: workout.id, exerciseId: "bench", settings: AppSettings())
            let set = try WorkoutSetRecord.filter(Column("workoutExerciseId") == item.id).fetchOne(db)!
            try WorkoutWrites.updateSet(db, setId: set.id, edit: SetEdit(loadHundredths: 4500, unit: .lb, reps: 9, type: .working))
            // Return to the shipped v1 table shape, then rerun the new migration.
            try db.execute(sql: "ALTER TABLE workoutSet DROP COLUMN note")
            try db.execute(sql: "ALTER TABLE workoutSet DROP COLUMN repsInReserve")
            try db.execute(sql: "ALTER TABLE workoutSet DROP COLUMN annotations")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v2'")
            return set.id
        }
        try Schema.migrator.migrate(queue)
        let set = try queue.read { try WorkoutSetRecord.fetchOne($0, key: id)! }
        #expect(set.loadHundredths == 4500 && set.unit == .lb && set.reps == 9)
        #expect(set.note == nil && set.repsInReserve == nil && set.annotations.isEmpty)
    }

}
