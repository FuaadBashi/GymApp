import Vapor

/// Wire format. Dates are milliseconds since 1970, so they round-trip exactly between the phone
/// and the server. Field names match the phone's `workoutSet` columns.
struct SetRow: Codable, Equatable {
    var id: String
    var workoutExerciseId: String
    var position: Int
    var loadHundredths: Int?
    var unit: String
    var reps: Int
    var type: String
    var completedAt: Date?
    var rpe: Double?
    var externalId: String?
    var note: String?
    var repsInReserve: Int?
    var annotations: [String]

    /// The same rules as the phone's CHECK constraints.
    func validate() throws {
        guard ["kg", "lb"].contains(unit), ["working", "warmUp", "failed", "drop"].contains(type),
              reps >= 0, position >= 0, workoutExerciseId.count <= 64,
              rpe.map({ (1...10).contains($0) }) ?? true,
              repsInReserve.map({ (0...3).contains($0) }) ?? true,
              (note?.count ?? 0) <= 2_000, annotations.count <= 10
        else { throw Abort(.unprocessableEntity, reason: "invalid set \(id)") }
    }
}

struct Change: Codable, Equatable {
    var table: String
    var id: String
    var op: String          // upsert | delete
    var updatedAt: Date
    var row: SetRow?

    func validate() throws {
        guard table == "workoutSet", !id.isEmpty, id.count <= 64 else { throw Abort(.unprocessableEntity, reason: "invalid change") }
        switch op {
        case "upsert":
            guard let row, row.id == id else { throw Abort(.unprocessableEntity, reason: "upsert \(id) needs its row") }
            try row.validate()
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
        return try JSONDecoder.sync.decode(T.self, from: body)
    }
}

func syncResponse(_ value: some Encodable) throws -> Response {
    let response = Response(status: .ok, body: .init(data: try JSONEncoder.sync.encode(value)))
    response.headers.contentType = .json
    return response
}
