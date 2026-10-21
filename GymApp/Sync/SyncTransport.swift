import Foundation

/// A synced row: the phone's own record, sent as its JSON. Tables are listed parents first.
nonisolated enum SyncRecord: Equatable, Sendable {
    case exercise(ExerciseRecord)
    case program(ProgramRecord)
    case programDay(ProgramDayRecord)
    case dayExercise(DayExerciseRecord)
    case workout(WorkoutRecord)
    case workoutExercise(WorkoutExerciseRecord)
    case workoutSet(WorkoutSetRecord)

    static let tables = ["exercise", "program", "programDay", "dayExercise", "workout", "workoutExercise", "workoutSet"]

    var table: String {
        switch self {
        case .exercise: "exercise"
        case .program: "program"
        case .programDay: "programDay"
        case .dayExercise: "dayExercise"
        case .workout: "workout"
        case .workoutExercise: "workoutExercise"
        case .workoutSet: "workoutSet"
        }
    }

    var id: String {
        switch self {
        case .exercise(let r): r.id
        case .program(let r): r.id
        case .programDay(let r): r.id
        case .dayExercise(let r): r.id
        case .workout(let r): r.id
        case .workoutExercise(let r): r.id
        case .workoutSet(let r): r.id
        }
    }
}

/// The wire format of docs/backend/01-plan.md §4. Dates are milliseconds since 1970, so they
/// round-trip exactly.
nonisolated struct SyncChange: Codable, Equatable, Sendable {
    var table: String
    var id: String
    var op: String          // upsert | delete
    var updatedAt: Date
    var row: SyncRecord?

    init(table: String, id: String, op: String, updatedAt: Date, row: SyncRecord?) {
        self.table = table
        self.id = id
        self.op = op
        self.updatedAt = updatedAt
        self.row = row
    }

    private enum Keys: String, CodingKey { case table, id, op, updatedAt, row }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        table = try c.decode(String.self, forKey: .table)
        id = try c.decode(String.self, forKey: .id)
        op = try c.decode(String.self, forKey: .op)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        if try !c.contains(.row) || c.decodeNil(forKey: .row) { row = nil; return }
        switch table {
        case "exercise": row = .exercise(try c.decode(ExerciseRecord.self, forKey: .row))
        case "program": row = .program(try c.decode(ProgramRecord.self, forKey: .row))
        case "programDay": row = .programDay(try c.decode(ProgramDayRecord.self, forKey: .row))
        case "dayExercise": row = .dayExercise(try c.decode(DayExerciseRecord.self, forKey: .row))
        case "workout": row = .workout(try c.decode(WorkoutRecord.self, forKey: .row))
        case "workoutExercise": row = .workoutExercise(try c.decode(WorkoutExerciseRecord.self, forKey: .row))
        case "workoutSet": row = .workoutSet(try c.decode(WorkoutSetRecord.self, forKey: .row))
        default: row = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(table, forKey: .table)
        try c.encode(id, forKey: .id)
        try c.encode(op, forKey: .op)
        try c.encode(updatedAt, forKey: .updatedAt)
        switch row {
        case .exercise(let r): try c.encode(r, forKey: .row)
        case .program(let r): try c.encode(r, forKey: .row)
        case .programDay(let r): try c.encode(r, forKey: .row)
        case .dayExercise(let r): try c.encode(r, forKey: .row)
        case .workout(let r): try c.encode(r, forKey: .row)
        case .workoutExercise(let r): try c.encode(r, forKey: .row)
        case .workoutSet(let r): try c.encode(r, forKey: .row)
        case nil: try c.encodeNil(forKey: .row)
        }
    }
}

nonisolated struct SyncPullPage: Codable, Equatable, Sendable {
    var changes: [SyncChange]
    var nextCursor: Int64
    var hasMore: Bool
}

nonisolated enum SyncError: LocalizedError, Equatable {
    /// Worth retrying later: no network, a timeout, a 5xx or a 429.
    case transient(String)
    /// Retrying the same request cannot help (a 4xx other than 401 or 429).
    case rejected(Int)

    var errorDescription: String? {
        switch self {
        case .transient(let why): "Could not reach the server (\(why))"
        case .rejected(let status): "The server refused the data (HTTP \(status))"
        }
    }

    /// A pasted address often ends in a space or a full stop; either breaks the secure connection.
    static func cleanServer(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix(".") || s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

nonisolated protocol SyncTransport: Sendable {
    func push(_ changes: [SyncChange]) async throws
    func pull(since cursor: Int64) async throws -> SyncPullPage
}

extension JSONEncoder {
    nonisolated static var sync: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e }
}
extension JSONDecoder {
    nonisolated static var sync: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }
}

/// HTTPS to the Vapor server. Signs in with the development route (`AUTH_DEV=1` on the server).
/// shortcut: no Sign in with Apple yet; it needs the entitlement (a project-file change).
nonisolated final class HTTPSyncTransport: SyncTransport, @unchecked Sendable {
    let base: URL
    let subject: String
    let session: URLSession
    private let lock = NSLock()
    private var token: String?

    init(base: URL, subject: String, session: URLSession = .shared) {
        self.base = base
        self.subject = subject
        self.session = session
    }

    func push(_ changes: [SyncChange]) async throws {
        struct Body: Encodable { var changes: [SyncChange] }
        _ = try await send("v1/sync/push", method: "POST", body: try JSONEncoder.sync.encode(Body(changes: changes)))
    }

    func pull(since cursor: Int64) async throws -> SyncPullPage {
        let data = try await send("v1/sync/pull?since=\(cursor)", method: "GET", body: nil)
        return try JSONDecoder.sync.decode(SyncPullPage.self, from: data)
    }

    private func send(_ path: String, method: String, body: Data?, retried: Bool = false) async throws -> Data {
        let token = try await currentToken()
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, status) = try await perform(request)
        if status == 401, !retried {
            lock.withLock { self.token = nil }
            return try await send(path, method: method, body: body, retried: true)
        }
        try Self.check(status)
        return data
    }

    private func currentToken() async throws -> String {
        if let cached = lock.withLock({ self.token }) { return cached }
        var request = URLRequest(url: URL(string: "v1/auth/dev", relativeTo: base)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["subject": subject])
        let (data, status) = try await perform(request)
        try Self.check(status)
        struct Token: Decodable { var accessToken: String }
        let token = try JSONDecoder().decode(Token.self, from: data).accessToken
        lock.withLock { self.token = token }
        return token
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw SyncError.transient(error.localizedDescription)
        }
    }

    static func check(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 429, 500..., 0: throw SyncError.transient("HTTP \(status)")
        default: throw SyncError.rejected(status)
        }
    }
}
