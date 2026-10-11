import Foundation
import GRDB
import Testing
@testable import GymApp

struct RecoveryTests {
    @Test func aDamagedPrimaryCanBeRecoveredWithoutErasingIt() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let workout = try app.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: .now) }
        _ = try recovery.stageRestore(try #require(recovery.snapshots().first))
        let live = folder.appending(path: "damaged.sqlite")
        let damaged = Data("damaged primary evidence".utf8)
        try damaged.write(to: live)
        try recovery.applyPendingRestore(to: live)
        #expect(try DatabaseQueue(path: live.path).read { try WorkoutQueries.inProgress($0)?.id } == workout.id)
        let archive = try #require(FileManager.default.contentsOfDirectory(at: recovery.folder, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("safety-live-") })
        #expect(try Data(contentsOf: archive.appending(path: "damaged.sqlite")) == damaged)
    }
    private func fixture() throws -> (AppDatabase, RecoveryStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let recovery = try RecoveryStore(folder: folder.appending(path: "Recovery"))
        let db = try AppDatabase(DatabaseQueue(path: folder.appending(path: "live.sqlite").path), recovery: recovery)
        return (db, recovery, folder)
    }
    @Test func aWALDatabaseProducesAPortableReadOnlySafetyCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let recovery = try RecoveryStore(folder: folder.appending(path: "Recovery"))
        let pool = try DatabasePool(path: folder.appending(path: "live.sqlite").path)
        defer { try? pool.close(); try? FileManager.default.removeItem(at: folder) }
        let app = try AppDatabase(pool)
        _ = try app.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: .now) }
        let copy = try app.reader.read { try recovery.capture($0, safety: true) }
        #expect(try RecoveryStore.inspect(copy).unfinished == 1)
        #expect(!FileManager.default.fileExists(atPath: copy.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: copy.path + "-shm"))
    }

    @Test func everyCommittedEditBacksUpAnUnfinishedWorkout() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = try app.writer.write { db in
            try TestData.exercise(db, id: "bench", name: "Bench")
            let workout = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: .now)
            let item = try WorkoutWrites.addExercise(db, workoutId: workout.id, exerciseId: "bench", settings: AppSettings())
            try WorkoutWrites.updateSet(db, setId: WorkoutSetRecord.filter(Column("workoutExerciseId") == item.id).fetchOne(db)!.id,
                edit: SetEdit(loadHundredths: 6250, unit: .lb, reps: 8, type: .working))
            return workout.id
        }
        let latest = try #require(recovery.snapshots().first)
        #expect(try RecoveryStore.inspect(latest).unfinished == 1)
        let copy = try DatabaseQueue(path: latest.path)
        try copy.read { db throws -> Void in
            #expect(try WorkoutRecord.fetchOne(db, key: id)?.endedAt == nil)
            #expect(try Int.fetchOne(db, sql: "SELECT loadHundredths FROM workoutSet ORDER BY position LIMIT 1") == 6250)
            #expect(try String.fetchOne(db, sql: "SELECT unit FROM workoutSet ORDER BY position LIMIT 1") == "lb")
        }
        #expect(recovery.status.localAt != nil)
        #expect(recovery.status.externalPending)
    }
    @Test func rollbackDoesNotReplaceTheLastGoodSnapshot() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = try recovery.snapshots()
        enum Stop: Error { case stop }
        #expect(throws: Stop.self) {
            try app.writer.write { db in
                try TestData.exercise(db, id: "discarded", name: "Discarded")
                throw Stop.stop
            }
        }
        #expect(try recovery.snapshots() == before)
    }
    @Test func aCorruptRestoreDoesNotChangeLiveData() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try app.writer.write { try TestData.exercise($0, id: "kept", name: "Kept") }
        let corrupt = folder.appending(path: "corrupt.sqlite")
        try Data("not sqlite".utf8).write(to: corrupt)
        #expect(throws: (any Error).self) { try recovery.stageRestore(corrupt) }
        #expect(try app.reader.read { try ExerciseRecord.fetchOne($0, key: "kept") != nil })
    }
    @Test func restorePreservesAnUnfinishedWorkoutAndMakesASafetyCopy() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let workout = try app.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: .now) }
        let backup = try #require(recovery.snapshots().first)
        let inspection = try recovery.stageRestore(backup)
        #expect(inspection.unfinished == 1)
        let restored = folder.appending(path: "restored.sqlite")
        let target = try AppDatabase(DatabaseQueue(path: restored.path))
        _ = try target.writer.write { try TestData.exercise($0, id: "before", name: "Before restore") }
        try recovery.applyPendingRestore(to: restored)
        let reopened = try AppDatabase(DatabaseQueue(path: restored.path))
        #expect(try reopened.reader.read { try WorkoutQueries.inProgress($0)?.id } == workout.id)
        let safety = try FileManager.default.contentsOfDirectory(at: recovery.folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("safety-live-") }
        #expect(safety.count == 1)
        #expect(try DatabaseQueue(path: safety[0].appending(path: "restored.sqlite").path).read { try ExerciseRecord.fetchOne($0, key: "before") != nil })
    }
    @Test func aFailedExternalCopyLeavesTheLocalCopyAndPendingStatus() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let external = folder.appending(path: "External")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try recovery.chooseExternalFolder(external)
        try recovery.retryExternal()
        #expect(recovery.status.externalAt != nil && !recovery.status.externalPending)
        // Remove the destination to reproduce an unavailable provider/folder.
        try FileManager.default.removeItem(at: external)
        _ = try app.writer.write { try TestData.exercise($0, id: "offline", name: "Offline") }
        #expect(recovery.status.externalPending && recovery.status.error != nil)
        let latest = try #require(recovery.snapshots().first)
        #expect(try DatabaseQueue(path: latest.path).read { try ExerciseRecord.fetchOne($0, key: "offline") != nil })
    }

    @Test func retentionKeepsThirtyVerifiedCopiesAndSafetyCopies() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let safety = try app.reader.read { try recovery.capture($0, safety: true) }
        for n in 0..<32 {
            _ = try app.writer.write { try TestData.exercise($0, id: "e\(n)", name: "Exercise \(n)") }
        }
        #expect(try recovery.snapshots().count == 30)
        #expect(FileManager.default.fileExists(atPath: safety.path))
        #expect(try DatabaseQueue(path: recovery.snapshots().first!.path).read { try ExerciseRecord.fetchCount($0) } == 32)
    }

}
