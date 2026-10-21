import Foundation
import GRDB
import Testing
@testable import GymApp

/// An in-memory stand-in for the server: the same last-writer-wins and change numbering as
/// server/Sources/App/SyncController.swift, and a switch that drops the network.
nonisolated final class FakeSyncServer: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: (change: SyncChange, seq: Int64)] = [:]   // key: table/id
    private var seq: Int64 = 0
    var failuresLeft = 0
    var pushes = 0
    var refuse: Set<String> = []   // ids the server answers 422 for

    func push(_ changes: [SyncChange]) async throws {
        try lock.withLock {
            if failuresLeft > 0 { failuresLeft -= 1; throw SyncError.transient("offline") }
            if changes.contains(where: { refuse.contains($0.id) }) { throw SyncError.rejected(422) }
            pushes += 1
            for change in changes {
                seq += 1
                let key = change.table + "/" + change.id
                if let old = rows[key], old.change.updatedAt >= change.updatedAt { continue }
                rows[key] = (change, seq)
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
    var storedSets: [SyncChange] { stored.filter { $0.table == "workoutSet" } }
    /// Sends the server's changes in a chosen order, as a server with another phone's pushes might.
    func reorder(_ order: (SyncChange, SyncChange) -> Bool) {
        lock.withLock {
            let sorted = rows.sorted { order($0.value.change, $1.value.change) }
            for (i, entry) in sorted.enumerated() { rows[entry.key] = (entry.value.change, Int64(i + 1)) }
            seq = Int64(sorted.count)
        }
    }
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
        #expect(try pending(db) == 5 + 3, "five sets, their workout, its exercise entry and the exercise")

        #expect(await engine.run())
        #expect(await delays.count == 3, "one wait for each failed push")
        #expect(try pending(db) == 0)
        let stored = server.storedSets.compactMap { if case .workoutSet(let r) = $0.row { r } else { nil } }
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
        #expect(try pending(db) == 3 + 3)
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
        #expect(try pending(db) == 2 + 3)
        try await engine.syncOnce()
        #expect(server.pushes == 1)
        let byId = Dictionary(uniqueKeysWithValues: server.storedSets.map { ($0.id, $0) })
        guard case .workoutSet(let edited) = byId[sets[0].id]?.row else { Issue.record("no set"); return }
        #expect(edited.reps == 12)
        #expect(byId[sets[1].id]?.op == "delete")
    }

    @Test func nothingIsRecordedUntilSyncIsEnabledThenHistoryIsBackfilled() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.base, exercises: [("bench", [(kg: 100, reps: 5)])])
        }
        #expect(try pending(db) == 0)
        try db.writer.write(SyncEngine.enable)
        #expect(try pending(db) == 4, "the set, its workout and exercise entry, and the custom exercise")
    }

    @Test func aWholeWorkoutArrivesOnASecondPhoneWithoutEcho() async throws {
        let server = FakeSyncServer()
        let sets = try logSets(3)
        try await SyncEngine(db: db, transport: server, sleep: { _ in }).syncOnce()

        let other = try AppDatabase.inMemory()
        try await other.writer.write(SyncEngine.enable)
        try await SyncEngine(db: other, transport: server, sleep: { _ in }).syncOnce()
        for set in sets { #expect(try record(other, set.id) == set) }
        #expect(try count(other, "SELECT COUNT(*) FROM workout") == 1)
        #expect(try count(other, "SELECT COUNT(*) FROM exercise WHERE id = 'bench'") == 1)
        #expect(try pending(other) == 0, "pulled rows are not sent back")
        #expect(try count(other, "SELECT COUNT(*) FROM syncParked") == 0)
    }

    @Test func childrenThatArriveBeforeTheirParentsWaitThenLand() async throws {
        let server = FakeSyncServer()
        let sets = try logSets(2)
        try await SyncEngine(db: db, transport: server, sleep: { _ in }).syncOnce()
        let depth = ["workoutSet": 0, "workoutExercise": 1, "workout": 2, "exercise": 3]
        server.reorder { depth[$0.table]! < depth[$1.table]! }    // sets first, exercise last

        let other = try AppDatabase.inMemory()
        try await other.writer.write(SyncEngine.enable)
        let page = try await server.pull(since: 0)
        // Apply only the sets: no parent yet, so they wait.
        try await other.writer.write { try SyncEngine.apply(SyncPullPage(changes: Array(page.changes.prefix(2)), nextCursor: 2, hasMore: false), in: $0) }
        #expect(try count(other, "SELECT COUNT(*) FROM workoutSet") == 0)
        #expect(try count(other, "SELECT COUNT(*) FROM syncParked") == 2)
        // The rest arrives: every parked row lands.
        try await SyncEngine(db: other, transport: server, sleep: { _ in }).syncOnce()
        for set in sets { #expect(try record(other, set.id) == set) }
        #expect(try count(other, "SELECT COUNT(*) FROM syncParked") == 0)
    }

    @Test func aSecondWorkoutInProgressWaitsUntilTheLocalOneEnds() async throws {
        let server = FakeSyncServer()
        try await db.writer.write { db in
            try SyncEngine.enable(db)
            try TestData.exercise(db, id: "bench")
            let day = try TestData.day(db, programId: TestData.program(db).id, name: "Full Body 1", position: 0, items: ["bench"])
            try WorkoutRecord(id: "remote", startedAt: TestData.base, endedAt: nil, programDayId: day.id, title: "Remote",
                              note: nil, effort: nil, restEndsAt: nil, restDurationSeconds: nil, source: .app, externalId: nil).insert(db)
        }
        try await SyncEngine(db: db, transport: server, sleep: { _ in }).syncOnce()

        let other = try AppDatabase.inMemory()
        try await other.writer.write { db in
            try SyncEngine.enable(db)
            try WorkoutRecord(id: "local", startedAt: TestData.day(1), endedAt: nil, programDayId: nil, title: "Local",
                              note: nil, effort: nil, restEndsAt: nil, restDurationSeconds: nil, source: .app, externalId: nil).insert(db)
        }
        let phone2 = SyncEngine(db: other, transport: FakeSyncServerReadOnly(server), sleep: { _ in })
        try await phone2.syncOnce()
        #expect(try count(other, "SELECT COUNT(*) FROM workout") == 1)
        #expect(try count(other, "SELECT COUNT(*) FROM syncParked") == 1)

        try await other.writer.write { try $0.execute(sql: "UPDATE workout SET endedAt = ? WHERE id = 'local'", arguments: [TestData.day(2)]) }
        try await phone2.syncOnce()
        #expect(try count(other, "SELECT COUNT(*) FROM workout") == 2)
        #expect(try count(other, "SELECT COUNT(*) FROM workout w JOIN programDay d ON d.id = w.programDayId WHERE w.id = 'remote' AND d.name = 'Full Body 1'") == 1,
                "the program, its day and its items arrive first, so the workout keeps its day")
        #expect(try count(other, "SELECT COUNT(*) FROM dayExercise") == 1)
    }

    @Test func aDayItemWaitsForItsDayThenLands() async throws {
        let server = FakeSyncServer()
        try await db.writer.write { db in
            try SyncEngine.enable(db)
            try TestData.exercise(db, id: "bench")
            try TestData.day(db, programId: TestData.program(db).id, name: "Full Body 1", position: 0, items: ["bench"])
        }
        try await SyncEngine(db: db, transport: server, sleep: { _ in }).syncOnce()
        let depth = ["dayExercise": 0, "programDay": 1, "program": 2, "exercise": 3]
        server.reorder { depth[$0.table, default: 9] < depth[$1.table, default: 9] }

        let other = try AppDatabase.inMemory()
        try await other.writer.write(SyncEngine.enable)
        let page = try await server.pull(since: 0)
        try await other.writer.write { try SyncEngine.apply(SyncPullPage(changes: Array(page.changes.prefix(1)), nextCursor: 1, hasMore: false), in: $0) }
        #expect(try count(other, "SELECT COUNT(*) FROM syncParked WHERE tableName = 'dayExercise'") == 1)
        try await SyncEngine(db: other, transport: server, sleep: { _ in }).syncOnce()
        #expect(try count(other, "SELECT COUNT(*) FROM dayExercise") == 1)
        #expect(try count(other, "SELECT COUNT(*) FROM syncParked") == 0)
        #expect(try pending(other) == 0)
    }

    @Test func untouchedLibraryExercisesAreNeverSent() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "lib-a", source: .library)
            try TestData.exercise(db, id: "lib-b", source: .library)
            try db.execute(sql: "UPDATE exercise SET isFavorite = 1 WHERE id = 'lib-b'")
            try SyncEngine.enable(db)
            try TestData.exercise(db, id: "lib-c", source: .library)
        }
        #expect(try count(db, "SELECT COUNT(*) FROM syncChange WHERE tableName = 'exercise'") == 1)
        #expect(try count(db, "SELECT COUNT(*) FROM syncChange WHERE rowId = 'lib-b'") == 1)
        try db.writer.write { try $0.execute(sql: "UPDATE exercise SET stickyNote = 'Pin 4' WHERE id = 'lib-a'") }
        #expect(try count(db, "SELECT COUNT(*) FROM syncChange WHERE rowId = 'lib-a'") == 1)
    }

    @Test func aChangeOfEveryKindSurvivesTheWireExactly() throws {
        let sets = try logSets(1)
        let rows: [SyncRecord] = try db.reader.read { db in
            [.exercise(try ExerciseRecord.fetchOne(db, key: "bench")!), .workout(try WorkoutRecord.fetchOne(db)!),
             .workoutExercise(try WorkoutExerciseRecord.fetchOne(db)!), .workoutSet(sets[0])]
        }
        for row in rows {
            let change = SyncChange(table: row.table, id: row.id,
                                    op: "upsert", updatedAt: Date(timeIntervalSince1970: 1_790_000_000.123), row: row)
            let back = try JSONDecoder.sync.decode(SyncChange.self, from: JSONEncoder.sync.encode(change))
            #expect(back == change)
        }
    }

    @Test func aRefusedChangeIsSetAsideAndTheRestStillGo() async throws {
        let server = FakeSyncServer()
        let sets = try logSets(4)
        server.refuse = [sets[1].id]
        try await SyncEngine(db: db, transport: server, sleep: { _ in }).syncOnce()
        #expect(Set(server.storedSets.map(\.id)) == Set(sets.map(\.id)).subtracting([sets[1].id]))
        #expect(try pending(db) == 0)
        #expect(try count(db, "SELECT COUNT(*) FROM syncDeadLetter") == 1)
        #expect(try count(db, "SELECT COUNT(*) FROM syncDeadLetter WHERE rowId = '\(sets[1].id)' AND status = 422") == 1)
        #expect(try record(db, sets[1].id) == sets[1], "the set itself stays on the phone")
    }

    @Test func turningSyncOffForgetsTheQueueButKeepsTheTraining() async throws {
        let server = FakeSyncServer()
        server.refuse = ["nothing"]
        let sets = try logSets(2)
        try await db.writer.write(SyncEngine.disable)
        #expect(try pending(db) == 0)
        #expect(try count(db, "SELECT COUNT(*) FROM syncState WHERE key = 'enabled'") == 0)
        #expect(try count(db, "SELECT COUNT(*) FROM workoutSet") == 2)
        try await db.writer.write { try $0.execute(sql: "UPDATE workoutSet SET reps = 9 WHERE id = ?", arguments: [sets[0].id]) }
        #expect(try pending(db) == 0, "nothing is recorded while sync is off")
        try await db.writer.write(SyncEngine.enable)
        #expect(try pending(db) == 2 + 3, "turning it on again queues everything")
    }

    @Test func aPastedServerAddressIsCleaned() {
        #expect(SyncError.cleanServer(" https://bashi-gym-sync.onrender.com.\n") == "https://bashi-gym-sync.onrender.com")
        #expect(SyncError.cleanServer("https://x.example/") == "https://x.example")
        #expect(SyncError.transient("timed out").localizedDescription == "Could not reach the server (timed out)")
    }

    @Test func backoffDoublesUpToFiveMinutes() {
        #expect(SyncEngine.delay(attempt: 0, jitter: 0) == 1)
        #expect(SyncEngine.delay(attempt: 3, jitter: 0) == 8)
        #expect(SyncEngine.delay(attempt: 30, jitter: 0) == 300)
        #expect(SyncEngine.delay(attempt: 2, jitter: 0.2) == 4.8)
    }
}

/// Pulls from a server without pushing to it, so a test can hold one phone's view still.
nonisolated struct FakeSyncServerReadOnly: SyncTransport {
    let server: FakeSyncServer
    init(_ server: FakeSyncServer) { self.server = server }
    func push(_ changes: [SyncChange]) async throws {}
    func pull(since cursor: Int64) async throws -> SyncPullPage { try await server.pull(since: cursor) }
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
    @Test func aWorkoutLoggedOnOnePhoneArrivesOnAnother() async throws {
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

        try await phone2.writer.write(SyncEngine.enable)
        #expect(await SyncEngine(db: phone2, transport: HTTPSyncTransport(base: url, subject: account)).run(maxAttempts: 1))
        let arrived = try await phone2.reader.read { try WorkoutSetRecord.fetchOne($0, key: set.id) }
        #expect(arrived == set)
        #expect(arrived?.loadHundredths == 10_250 && arrived?.unit == .kg)
        let workouts = try await phone2.reader.read { try WorkoutRecord.fetchAll($0) }
        #expect(workouts == (try await phone1.reader.read { try WorkoutRecord.fetchAll($0) }))
    }
}
