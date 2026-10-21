import Foundation
import GRDB

/// Sends the outbox and applies the server's changes (docs/backend/01-plan.md §4). Logging a set
/// never waits for this: the set is in the database before the outbox row exists.
nonisolated final class SyncEngine: Sendable {
    static let batchSize = 200
    static let maxDelay: Double = 300

    let db: AppDatabase
    let transport: any SyncTransport
    let sleep: @Sendable (Double) async throws -> Void

    init(db: AppDatabase, transport: any SyncTransport,
         sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.db = db
        self.transport = transport
        self.sleep = sleep
    }

    // MARK: State

    static func isEnabled(_ db: Database) throws -> Bool { try value(db, "enabled") != nil }

    /// Turns the triggers on and puts every existing set in the outbox once.
    static func enable(_ db: Database) throws {
        guard try !isEnabled(db) else { return }
        try db.execute(sql: """
            INSERT INTO syncChange (tableName, rowId, op, changedAtMs)
            SELECT 'workoutSet', id, 'upsert', CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER) FROM workoutSet
            """)
        try set(db, "enabled", "1")
    }

    static func pending(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT rowId) FROM syncChange") ?? 0
    }

    static func value(_ db: Database, _ key: String) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM syncState WHERE key = ?", arguments: [key])
    }

    static func set(_ db: Database, _ key: String, _ value: String?) throws {
        if let value {
            try db.execute(sql: "INSERT OR REPLACE INTO syncState (key, value) VALUES (?, ?)", arguments: [key, value])
        } else {
            try db.execute(sql: "DELETE FROM syncState WHERE key = ?", arguments: [key])
        }
    }

    /// The engine for the server saved in Settings, or nil while sync is off.
    static func configured(_ db: AppDatabase) -> SyncEngine? {
        guard let (server, account) = try? db.reader.read({ db -> (String, String)? in
            guard try isEnabled(db), let s = try value(db, "server"), let a = try value(db, "account") else { return nil }
            return (s, a)
        }), let url = URL(string: server) else { return nil }
        return SyncEngine(db: db, transport: HTTPSyncTransport(base: url, subject: account))
    }

    // MARK: Run

    /// 1, 2, 4 … seconds up to five minutes, ±20%.
    static func delay(attempt: Int, jitter: Double = .random(in: -0.2...0.2)) -> Double {
        min(maxDelay, pow(2, Double(min(attempt, 20)))) * (1 + jitter)
    }

    /// Push, then pull, retrying transient failures with backoff. Returns false on a rejected
    /// request or after `maxAttempts` failures; the outbox keeps every unsent change either way.
    @discardableResult
    func run(maxAttempts: Int = 12) async -> Bool {
        for attempt in 0..<maxAttempts {
            do {
                try await syncOnce()
                return true
            } catch SyncError.transient {
                try? await sleep(Self.delay(attempt: attempt))
            } catch {
                return false
            }
        }
        return false
    }

    func syncOnce() async throws {
        while let (changes, sent) = try nextBatch() {
            try await transport.push(changes)
            try await db.writer.write { db in
                for (rowId, seq) in sent {
                    try db.execute(sql: "DELETE FROM syncChange WHERE tableName = 'workoutSet' AND rowId = ? AND seq <= ?", arguments: [rowId, seq])
                }
            }
        }
        var cursor = try await db.reader.read { try Self.value($0, "cursor").flatMap(Int64.init) ?? 0 }
        while true {
            let page = try await transport.pull(since: cursor)
            try await db.writer.write { try Self.apply(page, in: $0) }
            cursor = page.nextCursor
            if !page.hasMore { break }
        }
    }

    /// The newest change of up to `batchSize` rows, oldest first. Many edits of one row go as one.
    private func nextBatch() throws -> ([SyncChange], [(String, Int64)])? {
        try db.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.rowId, c.seq, c.op, c.changedAtMs FROM syncChange c
                JOIN (SELECT rowId, MAX(seq) AS seq FROM syncChange WHERE tableName = 'workoutSet' GROUP BY rowId) m
                  ON m.seq = c.seq
                ORDER BY c.seq LIMIT ?
                """, arguments: [Self.batchSize])
            guard !rows.isEmpty else { return nil }
            var changes: [SyncChange] = []
            var sent: [(String, Int64)] = []
            for row in rows {
                let id: String = row["rowId"]
                let at = Date(timeIntervalSince1970: Double(row["changedAtMs"] as Int64) / 1000)
                let record = (row["op"] as String) == "upsert" ? try WorkoutSetRecord.fetchOne(db, key: id) : nil
                changes.append(SyncChange(table: "workoutSet", id: id, op: record == nil ? "delete" : "upsert", updatedAt: at, row: record))
                sent.append((id, row["seq"]))
            }
            return (changes, sent)
        }
    }

    /// Writes a pulled page with the triggers paused. A row with unsent local changes is skipped:
    /// the local push decides it on the server. A set whose exercise is not on this phone yet is
    /// parked and tried again on each pull.
    static func apply(_ page: SyncPullPage, in db: Database) throws {
        try set(db, "applying", "1")
        for change in page.changes where change.table == "workoutSet" {
            let pending = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM syncChange WHERE rowId = ?)", arguments: [change.id]) ?? false
            if pending { continue }
            try db.execute(sql: "DELETE FROM syncParked WHERE rowId = ?", arguments: [change.id])
            if change.op == "delete" {
                _ = try WorkoutSetRecord.deleteOne(db, key: change.id)
            } else if let row = change.row {
                try save(row, in: db)
            }
        }
        for parked in try Data.fetchAll(db, sql: "SELECT payload FROM syncParked") {
            let row = try JSONDecoder.sync.decode(WorkoutSetRecord.self, from: parked)
            if try exerciseExists(row, db) {
                try row.save(db)
                try db.execute(sql: "DELETE FROM syncParked WHERE rowId = ?", arguments: [row.id])
            }
        }
        try set(db, "cursor", String(page.nextCursor))
        try set(db, "applying", nil)
    }

    private static func save(_ row: WorkoutSetRecord, in db: Database) throws {
        if try exerciseExists(row, db) {
            try row.save(db)
        } else {
            try db.execute(sql: "INSERT OR REPLACE INTO syncParked (rowId, payload) VALUES (?, ?)",
                           arguments: [row.id, try JSONEncoder.sync.encode(row)])
        }
    }

    private static func exerciseExists(_ row: WorkoutSetRecord, _ db: Database) throws -> Bool {
        try WorkoutExerciseRecord.exists(db, key: row.workoutExerciseId)
    }
}
