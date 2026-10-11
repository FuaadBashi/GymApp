import Foundation
import GRDB
import Testing
@testable import GymApp

struct RecoveryTests {
    @Test func aFullPrimaryRollsBackAndKeepsTheWorkoutAndLastBackup() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let workout = try app.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: .now) }
        let copies = try recovery.snapshots()
        try app.writer.writeWithoutTransaction { db in
            let pages = try #require(try Int.fetchOne(db, sql: "PRAGMA page_count"))
            _ = try Int.fetchOne(db, sql: "PRAGMA max_page_count = \(pages)")
        }
        do {
            try app.writer.write { try WorkoutWrites.setNoteAndEffort($0, workoutId: workout.id, note: String(repeating: "x", count: 2_000_000), effort: 7) }
            Issue.record("The bounded database should reject a write that needs more pages")
        } catch let error as DatabaseError { #expect(error.resultCode == .SQLITE_FULL) }
        #expect(try app.reader.read { try WorkoutQueries.inProgress($0)?.id } == workout.id)
        #expect(try app.reader.read { try WorkoutRecord.fetchOne($0, key: workout.id)?.note } == nil)
        #expect(try recovery.snapshots() == copies)
    }
    @Test func fullBackupStorageDoesNotUndoACommittedWorkoutOrReplaceGoodCopies() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = try RecoveryStore(folder: folder.appending(path: "Recovery"))
        let queue = try DatabaseQueue(path: folder.appending(path: "live.sqlite").path)
        let app = try AppDatabase(queue)
        _ = try app.reader.read { try good.capture($0) }
        let before = try good.snapshots()
        let full = try RecoveryStore(folder: good.folder) { point in
            if point == .snapshotValidated { throw POSIXError(.ENOSPC) }
        }
        queue.writeWithoutTransaction { $0.add(transactionObserver: full, extent: .databaseLifetime) }
        let workout = try app.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: .now) }
        #expect(try app.reader.read { try WorkoutQueries.inProgress($0)?.id } == workout.id)
        #expect(try full.snapshots() == before)
        #expect(full.status.error != nil)
        #expect(try FileManager.default.contentsOfDirectory(at: good.folder, includingPropertiesForKeys: nil).allSatisfy { $0.pathExtension != "partial" })
        _ = try app.reader.read { try good.capture($0) }
        #expect(try RecoveryStore.inspect(try #require(good.snapshots().first)).unfinished == 1)
    }
    @Test func interruptedCopiesStayHiddenAndAnUnavailableDestinationRecoversOnRetry() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let previous = try recovery.snapshots()
        try Data("interrupted bytes".utf8).write(to: recovery.folder.appending(path: ".recovery-interrupted.partial"))
        #expect(try RecoveryStore(folder: recovery.folder).snapshots() == previous)
        #expect(!FileManager.default.fileExists(atPath: recovery.folder.appending(path: ".recovery-interrupted.partial").path))
        let external = folder.appending(path: "External")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try recovery.chooseExternalFolder(external)
        try FileManager.default.removeItem(at: external)
        _ = try app.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: .now) }
        #expect(recovery.status.externalPending)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try recovery.retryExternal()
        #expect(!recovery.status.externalPending && recovery.status.error == nil)
        let copy = external.appending(path: try #require(recovery.snapshots().first).lastPathComponent)
        #expect(try RecoveryStore.inspect(copy).unfinished == 1)
    }
    @Test func interruptedRestoreLeavesThePrimaryAndPendingCandidateAvailable() throws {
        let (app, recovery, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let backup = try #require(recovery.snapshots().first)
        _ = try app.writer.write { try TestData.exercise($0, id: "keep", name: "Kept") }
        _ = try recovery.stageRestore(backup)
        let interrupted = try RecoveryStore(folder: recovery.folder) { point in
            if point == .restoreValidated { throw POSIXError(.ENOSPC) }
        }
        let live = folder.appending(path: "live.sqlite")
        #expect(throws: (any Error).self) { try interrupted.applyPendingRestore(to: live) }
        #expect(try app.reader.read { try ExerciseRecord.fetchOne($0, key: "keep") != nil })
        #expect(FileManager.default.fileExists(atPath: recovery.folder.appending(path: "pending-restore.sqlite").path))
    }
    @Test func aCompletedSnapshotLeavesNoStagingFilesBehind() throws {
        // WAL, like the app's own database: its backup starts out as a WAL file.
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let recovery = try RecoveryStore(folder: folder.appending(path: "Recovery"))
        let pool = try DatabasePool(path: folder.appending(path: "live.sqlite").path)
        defer { try? pool.close(); try? FileManager.default.removeItem(at: folder) }
        let app = try AppDatabase(pool, recovery: recovery)
        _ = try app.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: .now) }
        _ = try app.reader.read { try recovery.capture($0) }
        let names = try FileManager.default.contentsOfDirectory(atPath: recovery.folder.path)
        #expect(names.allSatisfy { !$0.contains(".partial") }, "left behind: \(names)")
    }
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

/// Card 4.2: a backup of the real history restores onto a fresh install with identical rows
/// and identical exercise figures.
struct BackupRoundTripTests {
    @Test(.enabled(if: Fixtures.hasRealExport))
    func aBackupRestoresWithIdenticalCountsAndFigures() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recovery = try RecoveryStore(folder: folder.appending(path: "Recovery"))
        let original = try AppDatabase(DatabaseQueue(path: folder.appending(path: "phone.sqlite").path), recovery: recovery)
        try await original.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        _ = try await ImportService.importJEFIT(fileAt: Fixtures.realExport, into: original)
        let backup = try await original.reader.read { try recovery.capture($0) }

        // A fresh install elsewhere: its own recovery folder and an empty database file.
        let fresh = folder.appending(path: "fresh")
        let freshRecovery = try RecoveryStore(folder: fresh.appending(path: "Recovery"))
        _ = try freshRecovery.stageRestore(backup)
        let live = fresh.appending(path: "gymapp.sqlite")
        try freshRecovery.applyPendingRestore(to: live)
        let restored = try AppDatabase(DatabaseQueue(path: live.path))

        let tables = ["exercise", "program", "programDay", "dayExercise", "workout", "workoutExercise", "workoutSet",
                      "exerciseNote", "bodyEntry", "setting", "importRun"]
        for table in tables {
            let a = try await original.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") }
            let b = try await restored.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") }
            #expect(a == b, "\(table)")
        }
        #expect(try await restored.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workoutSet") } == 7751)
        for id in ["jefit:1:2", "jefit:1:12", "jefit:1:93"] {
            let a = try await original.reader.read { try ExerciseQueries.sessions($0, exerciseId: id) }
            let b = try await restored.reader.read { try ExerciseQueries.sessions($0, exerciseId: id) }
            #expect(ExerciseStats.records(a, loadMode: .total) { _ in nil } == ExerciseStats.records(b, loadMode: .total) { _ in nil }, "\(id)")
            #expect(ExerciseStats.points(a, loadMode: .total) { _ in nil } == ExerciseStats.points(b, loadMode: .total) { _ in nil }, "\(id)")
        }
    }
}
