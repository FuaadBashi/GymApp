import BackgroundTasks
import Foundation
import GRDB
import Network

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

    /// Turns the triggers on and puts every existing row in the outbox once, parents first.
    /// Bundled library exercises go only if changed here (favourite, archived or a note).
    static func enable(_ db: Database) throws {
        guard try !isEnabled(db) else { return }
        let now = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)"
        let filters = ["exercise": "WHERE source != 'library' OR isFavorite = 1 OR isArchived = 1 OR stickyNote IS NOT NULL",
                       "formCue": "WHERE source = 'owner'"]
        for table in SyncRecord.tables {
            try db.execute(sql: """
                INSERT INTO syncChange (tableName, rowId, op, changedAtMs)
                SELECT '\(table)', id, 'upsert', \(now) FROM \(table) \(filters[table] ?? "")
                """)
        }
        try set(db, "enabled", "1")
    }

    /// Turns sync off and forgets what was sent, so turning it on again sends everything.
    /// The phone's own training data is untouched.
    static func disable(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM syncState WHERE key IN ('enabled', 'cursor', 'applying');
            DELETE FROM syncChange;
            DELETE FROM syncParked;
            DELETE FROM syncDeadLetter;
            """)
    }

    /// Rows with changes not yet sent.
    static func pending(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM (SELECT DISTINCT tableName, rowId FROM syncChange)") ?? 0
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
            do {
                try await transport.push(changes)
                try await markSent(sent)
            } catch SyncError.rejected {
                // Find the change the server refuses: send one at a time, and set aside each
                // refused one so the rest still go.
                for (change, entry) in zip(changes, sent) {
                    do {
                        try await transport.push([change])
                    } catch SyncError.rejected(let status) {
                        try await db.writer.write { db in
                            try db.execute(sql: """
                                INSERT OR REPLACE INTO syncDeadLetter (tableName, rowId, payload, status, failedAtMs)
                                VALUES (?, ?, ?, ?, CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER))
                                """, arguments: [change.table, change.id, try JSONEncoder.sync.encode(change), status])
                        }
                    }
                    try await markSent([entry])
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

    private func markSent(_ sent: [(String, String, Int64)]) async throws {
        try await db.writer.write { db in
            for (table, rowId, seq) in sent {
                try db.execute(sql: "DELETE FROM syncChange WHERE tableName = ? AND rowId = ? AND seq <= ?",
                               arguments: [table, rowId, seq])
            }
        }
    }

    static func refused(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncDeadLetter") ?? 0
    }

    /// The newest change of up to `batchSize` rows, in the order they were first changed, so a
    /// parent normally goes before its children. Many edits of one row go as one change.
    private func nextBatch() throws -> ([SyncChange], [(String, String, Int64)])? {
        try db.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.tableName, c.rowId, c.seq, c.op, c.changedAtMs, m.firstSeq FROM syncChange c
                JOIN (SELECT tableName, rowId, MAX(seq) AS seq, MIN(seq) AS firstSeq FROM syncChange GROUP BY tableName, rowId) m
                  ON m.seq = c.seq
                ORDER BY m.firstSeq LIMIT ?
                """, arguments: [Self.batchSize])
            guard !rows.isEmpty else { return nil }
            var changes: [SyncChange] = []
            var sent: [(String, String, Int64)] = []
            for row in rows {
                let table: String = row["tableName"]
                let id: String = row["rowId"]
                let at = Date(timeIntervalSince1970: Double(row["changedAtMs"] as Int64) / 1000)
                let record = (row["op"] as String) == "upsert" ? try Self.fetch(table, id, db) : nil
                changes.append(SyncChange(table: table, id: id, op: record == nil ? "delete" : "upsert", updatedAt: at, row: record))
                sent.append((table, id, row["seq"]))
            }
            return (changes, sent)
        }
    }

    private static func fetch(_ table: String, _ id: String, _ db: Database) throws -> SyncRecord? {
        switch table {
        case "exercise": try ExerciseRecord.fetchOne(db, key: id).map(SyncRecord.exercise)
        case "program": try ProgramRecord.fetchOne(db, key: id).map(SyncRecord.program)
        case "programDay": try ProgramDayRecord.fetchOne(db, key: id).map(SyncRecord.programDay)
        case "dayExercise": try DayExerciseRecord.fetchOne(db, key: id).map(SyncRecord.dayExercise)
        case "workout": try WorkoutRecord.fetchOne(db, key: id).map(SyncRecord.workout)
        case "workoutExercise": try WorkoutExerciseRecord.fetchOne(db, key: id).map(SyncRecord.workoutExercise)
        case "workoutSet": try WorkoutSetRecord.fetchOne(db, key: id).map(SyncRecord.workoutSet)
        case "exerciseNote": try ExerciseNoteRecord.fetchOne(db, key: id).map(SyncRecord.exerciseNote)
        case "bodyEntry": try BodyEntryRecord.fetchOne(db, key: id).map(SyncRecord.bodyEntry)
        case "formCue": try FormCueRecord.fetchOne(db, key: id).map(SyncRecord.formCue)
        default: nil
        }
    }

    /// Writes a pulled page with the triggers paused. A row with unsent local changes is skipped:
    /// the local push decides it on the server. A row whose parent is not on this phone yet, or
    /// that breaks a local rule (a second workout in progress), is parked and tried again after
    /// each page, until no parked row can be written.
    static func apply(_ page: SyncPullPage, in db: Database) throws {
        try set(db, "applying", "1")
        for change in page.changes where SyncRecord.tables.contains(change.table) {
            let pending = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM syncChange WHERE tableName = ? AND rowId = ?)",
                                            arguments: [change.table, change.id]) ?? false
            if pending { continue }
            try db.execute(sql: "DELETE FROM syncParked WHERE tableName = ? AND rowId = ?", arguments: [change.table, change.id])
            if change.op == "delete" {
                try db.execute(sql: "DELETE FROM \(change.table) WHERE id = ?", arguments: [change.id])
            } else if let row = change.row, !(try write(row, in: db)) {
                try db.execute(sql: "INSERT OR REPLACE INTO syncParked (tableName, rowId, payload) VALUES (?, ?, ?)",
                               arguments: [change.table, change.id, try JSONEncoder.sync.encode(change)])
            }
        }
        var progress = true
        while progress {
            progress = false
            let order = SyncRecord.tables.enumerated().map { "WHEN '\($1)' THEN \($0)" }.joined(separator: " ")
            let parked = try Data.fetchAll(db, sql: "SELECT payload FROM syncParked ORDER BY CASE tableName \(order) END")
            for payload in parked {
                let change = try JSONDecoder.sync.decode(SyncChange.self, from: payload)
                if let row = change.row, try write(row, in: db) {
                    try db.execute(sql: "DELETE FROM syncParked WHERE tableName = ? AND rowId = ?", arguments: [change.table, change.id])
                    progress = true
                }
            }
        }
        try set(db, "cursor", String(page.nextCursor))
        try set(db, "applying", nil)
    }

    /// Saves (update, else insert: never REPLACE, which would cascade-delete children) when the
    /// parents are here; otherwise the row is parked until they arrive. A link to a library entry
    /// this phone lacks (an older bundled library) is dropped, since it never syncs.
    private static func write(_ row: SyncRecord, in db: Database) throws -> Bool {
        func exists(_ table: String, _ id: String?) throws -> Bool {
            guard let id else { return true }
            return try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM \(table) WHERE id = ?)", arguments: [id]) ?? false
        }
        var written = false
        do {
            try db.inSavepoint {
                switch row {
                case .exercise(var r):
                    if try !exists("exercise", r.libraryId) { r.libraryId = nil }
                    try r.save(db)
                case .program(let r):
                    try r.save(db)
                case .programDay(let r):
                    guard try exists("program", r.programId), try exists("programDay", r.copiedFromDayId) else { return .rollback }
                    try r.save(db)
                case .dayExercise(let r):
                    guard try exists("programDay", r.dayId), try exists("exercise", r.exerciseId) else { return .rollback }
                    try r.save(db)
                case .workout(let r):
                    guard try exists("programDay", r.programDayId) else { return .rollback }
                    try r.save(db)
                case .workoutExercise(let r):
                    guard try exists("workout", r.workoutId), try exists("exercise", r.exerciseId),
                          try exists("dayExercise", r.dayExerciseId) else { return .rollback }
                    try r.save(db)
                case .workoutSet(let r):
                    guard try exists("workoutExercise", r.workoutExerciseId) else { return .rollback }
                    try r.save(db)
                case .exerciseNote(let r):
                    guard try exists("exercise", r.exerciseId) else { return .rollback }
                    try r.save(db)
                case .bodyEntry(let r):
                    try r.save(db)
                case .formCue(let r):
                    guard try exists("exercise", r.exerciseId) else { return .rollback }
                    try r.save(db)
                }
                written = true
                return .commit
            }
            return written
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            return false
        }
    }
}

/// Runs sync when the app opens, after each logged set, when the network comes back, and in
/// background refresh (BackgroundSync). One run at a time; a request during a run queues one more.
actor SyncScheduler {
    static let shared = SyncScheduler()
    private var running = false
    private var again = false
    private var monitor: NWPathMonitor?

    func kick(_ db: AppDatabase) async {
        watchNetwork(db)
        if running { again = true; return }
        running = true
        repeat {
            again = false
            await SyncEngine.configured(db)?.run(maxAttempts: 6)
        } while again
        running = false
    }

    private func watchNetwork(_ db: AppDatabase) {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        var wasOnline = true
        m.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            if online && !wasOnline { Task { await SyncScheduler.shared.kick(db) } }
            wasOnline = online
        }
        m.start(queue: DispatchQueue(label: "sync.network"))
        monitor = m
    }
}

/// Sync while the app is closed: iOS runs this refresh task when it chooses (often a few
/// times a day, more for an app used daily). The identifier is listed in GymApp/Info.plist.
enum BackgroundSync {
    static let identifier = "com.fuaadshurie.GymApp.sync"

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                schedule()
                guard let db = WorkoutHub.db else { return task.setTaskCompleted(success: false) }
                nonisolated(unsafe) let task = task
                let work = Task { await SyncScheduler.shared.kick(db); task.setTaskCompleted(success: !Task.isCancelled) }
                task.expirationHandler = { work.cancel() }
            }
        }
    }

    /// Asks for the next run; iOS decides when. Called when the app goes to the background.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
