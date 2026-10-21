import Foundation
import GRDB
import Testing
@testable import GymApp

/// An in-memory stand-in for the server: the same last-writer-wins and change numbering as
/// server/Sources/App/SyncController.swift, and a switch that drops the network.
nonisolated final class FakeSyncServer: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: (change: SyncChange, seq: Int64)] = [:]
    private var seq: Int64 = 0
    var failuresLeft = 0
    var pushes = 0

    func push(_ changes: [SyncChange]) async throws {
        try lock.withLock {
            if failuresLeft > 0 { failuresLeft -= 1; throw SyncError.transient("offline") }
            pushes += 1
            for change in changes {
                seq += 1
                if let old = rows[change.id], old.change.updatedAt >= change.updatedAt { continue }
                rows[change.id] = (change, seq)
            }
        }
    }

    func pull(since cursor: Int64) async throws -> SyncPullPage {
        lock.withLock {
            let newer = rows.values.filter { $0.seq > cursor }.sorted { $0.seq < $1.seq }
            return SyncPullPage(changes: newer.map(\.change), nextCursor: newer.last?.seq ?? cursor, hasMore: false)
        }
    }

    var stored: [SyncChange] { lock.withLock { rows.values.map(\.change).sorted { $0.id < $1.id } } }
}

@Suite struct SyncEngineTests {
    let db = try! AppDatabase.inMemory()

    /// One finished workout of `count` sets, logged after sync was turned on.
    func logSets(_ count: Int) throws -> [WorkoutSetRecord] {
        try db.writer.write { db in
            try SyncEngine.enable(db)
            try TestData.exercise(db, id: "bench")
            let w = try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.base,
                                                 exercises: [("bench", (0..<count).map { (kg: 100 + Double($0) * 2.5, reps: 8) })])
            return try WorkoutSetRecord.fetchAll(db, sql: """
                SELECT s.* FROM workoutSet s JOIN workoutExercise we ON we.id = s.workoutExerciseId
                WHERE we.workoutId = ? ORDER BY s.position
                """, arguments: [w.id])
        }
    }

    func pending(_ d: AppDatabase) throws -> Int { try d.reader.read(SyncEngine.pending) }
    func count(_ d: AppDatabase, _ sql: String) throws -> Int { try d.reader.read { try Int.fetchOne($0, sql: sql) ?? 0 } }
    func record(_ d: AppDatabase, _ id: String) throws -> WorkoutSetRecord? { try d.reader.read { try WorkoutSetRecord.fetchOne($0, key: id) } }

    // Done-when check 2: the network drops, the sets sync later, nothing is lost.
    @Test func setsLoggedOfflineSyncAfterTheNetworkReturns() async throws {
        let server = FakeSyncServer()
        server.failuresLeft = 3
        let delays = DelayLog()
        let engine = SyncEngine(db: db, transport: server, sleep: { await delays.add($0) })

        let logged = try logSets(5)
        #expect(logged.count == 5, "every set is in the phone database before any network call")
        #expect(try pending(db) == 5)

        #expect(await engine.run())
        #expect(await delays.count == 3, "one wait for each failed push")
        #expect(try pending(db) == 0)
        let stored = server.stored.compactMap(\.row)
        #expect(stored.count == 5)
        #expect(stored.sorted { $0.position < $1.position }.map(\.loadHundredths) == logged.map(\.loadHundredths))
        #expect(stored.allSatisfy { $0.unit == .kg && $0.reps == 8 })
    }

    @Test func aFailedRunKeepsEveryChangeInTheOutbox() async throws {
        let server = FakeSyncServer()
        server.failuresLeft = 100
        let engine = SyncEngine(db: db, transport: server, sleep: { _ in })
        _ = try logSets(3)
        #expect(await engine.run(maxAttempts: 4) == false)
        #expect(try pending(db) == 3)
        #expect(server.stored.isEmpty)
    }

    @Test func manyEditsOfOneSetGoAsOneChangeAndDeletesGoAsTombstones() async throws {
        let server = FakeSyncServer()
        let engine = SyncEngine(db: db, transport: server, sleep: { _ in })
        let sets = try logSets(2)
        try await db.writer.write { db in
            for reps in 9...12 { try db.execute(sql: "UPDATE workoutSet SET reps = ? WHERE id = ?", arguments: [reps, sets[0].id]) }
            _ = try WorkoutSetRecord.deleteOne(db, key: sets[1].id)
        }
        #expect(try pending(db) == 2)
        try await engine.syncOnce()
        #expect(server.pushes == 1)
        let byId = Dictionary(uniqueKeysWithValues: server.stored.map { ($0.id, $0) })
        #expect(byId[sets[0].id]?.row?.reps == 12)
        #expect(byId[sets[1].id]?.op == "delete")
    }

    @Test func nothingIsRecordedUntilSyncIsEnabledThenHistoryIsBackfilled() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.base, exercises: [("bench", [(kg: 100, reps: 5)])])
        }
        #expect(try pending(db) == 0)
        try db.writer.write(SyncEngine.enable)
        #expect(try pending(db) == 1)
    }

    @Test func pulledSetsAreAppliedWithoutEchoAndOrphansWaitForTheirExercise() async throws {
        let server = FakeSyncServer()
        let engine = SyncEngine(db: db, transport: server, sleep: { _ in })
        let other = try AppDatabase.inMemory()
        let sets = try logSets(1)
        try await engine.syncOnce()

        // A second phone with no workouts: the set waits, parked, and nothing is echoed back.
        let phone2 = SyncEngine(db: other, transport: server, sleep: { _ in })
        try await other.writer.write(SyncEngine.enable)
        try await phone2.syncOnce()
        #expect(try count(other, "SELECT COUNT(*) FROM workoutSet") == 0)
        #expect(try count(other, "SELECT COUNT(*) FROM syncParked") == 1)
        #expect(try pending(other) == 0)

        // Its workout arrives (by restore here; by sync once more tables sync): the set lands.
        let db1 = self.db
        try await other.writer.write { db in
            try TestData.exercise(db, id: "bench")
            let source = try db1.reader.read { src in
                (try WorkoutRecord.fetchOne(src)!, try WorkoutExerciseRecord.fetchOne(src)!)
            }
            try SyncEngine.set(db, "applying", "1")
            try source.0.insert(db)
            try source.1.insert(db)
            try SyncEngine.set(db, "applying", nil)
            try SyncEngine.apply(SyncPullPage(changes: [], nextCursor: 1, hasMore: false), in: db)
        }
        #expect(try record(other, sets[0].id) == sets[0])
        #expect(try pending(other) == 0)
    }

    @Test func backoffDoublesUpToFiveMinutes() {
        #expect(SyncEngine.delay(attempt: 0, jitter: 0) == 1)
        #expect(SyncEngine.delay(attempt: 3, jitter: 0) == 8)
        #expect(SyncEngine.delay(attempt: 30, jitter: 0) == 300)
        #expect(SyncEngine.delay(attempt: 2, jitter: 0.2) == 4.8)
    }
}

actor DelayLog {
    private(set) var values: [Double] = []
    func add(_ value: Double) { values.append(value) }
    var count: Int { values.count }
}

/// Against the real server (server/README.md). Runs when the test command passes
/// TEST_RUNNER_SYNC_SERVER=http://localhost:8080 and is skipped otherwise.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SYNC_SERVER"] != nil))
struct SyncServerIntegrationTests {
    @Test func aSetLoggedOnOnePhoneArrivesOnAnother() async throws {
        let url = URL(string: ProcessInfo.processInfo.environment["SYNC_SERVER"]!)!
        let account = "it-\(UUID().uuidString)"
        let phone1 = try AppDatabase.inMemory(), phone2 = try AppDatabase.inMemory()
        let set = try await phone1.writer.write { db -> WorkoutSetRecord in
            try SyncEngine.enable(db)
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.base, exercises: [("bench", [(kg: 102.5, reps: 6)])])
            return try WorkoutSetRecord.fetchOne(db)!
        }
        #expect(await SyncEngine(db: phone1, transport: HTTPSyncTransport(base: url, subject: account)).run(maxAttempts: 1))

        try await phone2.writer.write { db in
            try SyncEngine.enable(db)
            try TestData.exercise(db, id: "bench")
        }
        let source = try await phone1.reader.read { (try WorkoutRecord.fetchOne($0)!, try WorkoutExerciseRecord.fetchOne($0)!) }
        try await phone2.writer.write { db in
            try SyncEngine.set(db, "applying", "1")
            try source.0.insert(db); try source.1.insert(db)
            try SyncEngine.set(db, "applying", nil)
        }
        #expect(await SyncEngine(db: phone2, transport: HTTPSyncTransport(base: url, subject: account)).run(maxAttempts: 1))
        let arrived = try await phone2.reader.read { try WorkoutSetRecord.fetchOne($0, key: set.id) }
        #expect(arrived == set)
        #expect(arrived?.loadHundredths == 10_250 && arrived?.unit == .kg)
    }
}
