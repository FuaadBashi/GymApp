import Vapor

/// Any JSON value. A row is kept exactly as the phone sent it, so a field this server does not
/// know about yet survives the round trip.
enum JSON: Codable, Equatable, Sendable {
    case null, bool(Bool), int(Int64), double(Double), string(String), array([JSON]), object([String: JSON])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    init(_ value: some Encodable) throws {
        self = try JSONDecoder.sync.decode(JSON.self, from: JSONEncoder.sync.encode(value))
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder.sync.decode(T.self, from: JSONEncoder.sync.encode(self))
    }

    subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] } else { return nil }
    }
}

/// The rules for each kind of row: the same as the phone's CHECK constraints for the fields
/// that matter. Wire dates are milliseconds since 1970.
protocol SyncRow: Decodable { var id: String { get }; func validate() throws }

private func require(_ ok: Bool, _ what: String) throws {
    if !ok { throw Abort(.unprocessableEntity, reason: "invalid \(what)") }
}

struct SetRow: SyncRow {
    var id: String
    var workoutExerciseId: String
    var position: Int
    var loadHundredths: Int?
    var unit: String
    var reps: Int
    var type: String
    var rpe: Double?
    var repsInReserve: Int?
    var note: String?

    func validate() throws {
        try require(["kg", "lb"].contains(unit) && ["working", "warmUp", "failed", "drop"].contains(type)
            && reps >= 0 && position >= 0 && rpe.map { (1...10).contains($0) } ?? true
            && repsInReserve.map { (0...3).contains($0) } ?? true && (note?.count ?? 0) <= 2_000, "set \(id)")
    }
}

struct ExerciseRow: SyncRow {
    var id: String
    var name: String
    var source: String
    var defaultRestSeconds: Int
    var preferredUnit: String

    func validate() throws {
        try require(!name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 200
            && ["library", "jefit", "custom"].contains(source) && (0...900).contains(defaultRestSeconds)
            && ["kg", "lb"].contains(preferredUnit), "exercise \(id)")
    }
}

struct WorkoutRow: SyncRow {
    var id: String
    var startedAt: Date
    var endedAt: Date?
    var title: String
    var effort: Int?

    func validate() throws {
        try require(endedAt.map { $0 >= startedAt } ?? true && title.count <= 200
            && effort.map { (1...10).contains($0) } ?? true, "workout \(id)")
    }
}

struct WorkoutExerciseRow: SyncRow {
    var id: String
    var workoutId: String
    var exerciseId: String
    var position: Int
    var restSeconds: Int

    func validate() throws {
        try require(position >= 0 && (0...900).contains(restSeconds) && !workoutId.isEmpty && !exerciseId.isEmpty,
                    "workout exercise \(id)")
    }
}

struct ProgramRow: SyncRow {
    var id: String
    var name: String
    var sessionsPerWeekGoal: Int

    func validate() throws {
        try require(!name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 200
            && (1...7).contains(sessionsPerWeekGoal), "program \(id)")
    }
}

struct ProgramDayRow: SyncRow {
    var id: String
    var programId: String
    var name: String
    var position: Int

    func validate() throws {
        try require(!programId.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 200
            && position >= 0, "program day \(id)")
    }
}

struct DayExerciseRow: SyncRow {
    var id: String
    var dayId: String
    var exerciseId: String
    var position: Int
    var targetSets: Int
    var repMin: Int
    var repMax: Int
    var restSeconds: Int

    func validate() throws {
        try require(!dayId.isEmpty && !exerciseId.isEmpty && position >= 0 && (1...20).contains(targetSets)
            && repMin >= 1 && repMax >= repMin && (0...900).contains(restSeconds), "day exercise \(id)")
    }
}

struct Change: Codable, Equatable {
    static let rowTypes: [String: any SyncRow.Type] = [
        "exercise": ExerciseRow.self, "program": ProgramRow.self, "programDay": ProgramDayRow.self,
        "dayExercise": DayExerciseRow.self, "workout": WorkoutRow.self,
        "workoutExercise": WorkoutExerciseRow.self, "workoutSet": SetRow.self,
    ]

    var table: String
    var id: String
    var op: String          // upsert | delete
    var updatedAt: Date
    var row: JSON?

    func validate() throws {
        guard let type = Self.rowTypes[table], !id.isEmpty, id.count <= 64 else {
            throw Abort(.unprocessableEntity, reason: "invalid change")
        }
        switch op {
        case "upsert":
            guard let row, (try? JSONEncoder.sync.encode(row).count) ?? .max <= 64_000 else {
                throw Abort(.unprocessableEntity, reason: "upsert \(id) needs its row")
            }
            let typed: any SyncRow
            do { typed = try row.decode(type) } catch { throw Abort(.unprocessableEntity, reason: "invalid \(table) \(id)") }
            guard typed.id == id else { throw Abort(.unprocessableEntity, reason: "row id differs from \(id)") }
            try typed.validate()
        case "delete": break
        default: throw Abort(.unprocessableEntity, reason: "unknown op \(op)")
        }
    }
}

struct PushRequest: Codable { var changes: [Change] }
struct PushResponse: Codable { var accepted: [String] }

struct PullResponse: Codable {
    var changes: [Change]
    var nextCursor: Int64
    var hasMore: Bool
}

extension JSONEncoder {
    static let sync: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e }()
}
extension JSONDecoder {
    static let sync: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }()
}

extension Request {
    func decodeSync<T: Decodable>(_ type: T.Type) throws -> T {
        guard let body = body.data else { throw Abort(.badRequest) }
        do { return try JSONDecoder.sync.decode(T.self, from: body) } catch { throw Abort(.badRequest, reason: "malformed body") }
    }
}

func syncResponse(_ value: some Encodable) throws -> Response {
    let response = Response(status: .ok, body: .init(data: try JSONEncoder.sync.encode(value)))
    response.headers.contentType = .json
    return response
}
