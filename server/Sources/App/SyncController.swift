import PostgresNIO
import Vapor

struct SyncController: RouteCollection {
    static let maxPush = 200
    static let maxPull = 500

    func boot(routes: any RoutesBuilder) throws {
        let sync = routes.grouped("sync")
        sync.on(.POST, "push", body: .collect(maxSize: "1mb"), use: push)
        sync.get("pull", use: pull)
    }

    /// One transaction: lock the user's row and take a block of change numbers, then upsert
    /// each change. The lock makes one user's pushes run one at a time, so `server_seq` commits
    /// in order and a pull cursor can never skip a row. The `WHERE` on the upsert is
    /// last-writer-wins and makes a repeated push change nothing.
    func push(req: Request) async throws -> Response {
        let user = try req.userId()
        let body = try req.decodeSync(PushRequest.self)
        guard !body.changes.isEmpty, body.changes.count <= Self.maxPush else { throw Abort(.payloadTooLarge) }
        try body.changes.forEach { try $0.validate() }

        try await req.application.db.withConnection { conn in
            try await conn.query("BEGIN", logger: req.logger)
            do {
                let n = Int64(body.changes.count)
                let top = try await conn.query(
                    "UPDATE users SET change_seq = change_seq + \(n) WHERE id = \(user) RETURNING change_seq",
                    logger: req.logger).collect().first?.decode(Int64.self)
                guard let top else { throw Abort(.unauthorized) }
                for (i, change) in body.changes.enumerated() {
                    try await upsert(change, user: user, seq: top - n + 1 + Int64(i), on: conn, logger: req.logger)
                }
                try await conn.query("COMMIT", logger: req.logger)
            } catch {
                try? await conn.query("ROLLBACK", logger: req.logger)
                throw error
            }
        }
        return try syncResponse(PushResponse(accepted: body.changes.map(\.id)))
    }

    private func upsert(_ c: Change, user: UUID, seq: Int64, on conn: PostgresConnection, logger: Logger) async throws {
        let r = c.row
        let deleted = c.op == "delete"
        try await conn.query("""
            INSERT INTO workout_set (user_id, id, workout_exercise_id, position, load_hundredths, unit, reps, type,
              completed_at, rpe, reps_in_reserve, note, external_id, annotations, updated_at, server_seq, deleted)
            VALUES (\(user), \(c.id), \(r?.workoutExerciseId), \(r?.position), \(r?.loadHundredths), \(r?.unit), \(r?.reps),
              \(r?.type), \(r?.completedAt), \(r?.rpe), \(r?.repsInReserve), \(r?.note), \(r?.externalId),
              \(r?.annotations ?? []), \(c.updatedAt), \(seq), \(deleted))
            ON CONFLICT (user_id, id) DO UPDATE SET
              workout_exercise_id = COALESCE(EXCLUDED.workout_exercise_id, workout_set.workout_exercise_id),
              position = COALESCE(EXCLUDED.position, workout_set.position),
              load_hundredths = CASE WHEN EXCLUDED.deleted THEN workout_set.load_hundredths ELSE EXCLUDED.load_hundredths END,
              unit = COALESCE(EXCLUDED.unit, workout_set.unit),
              reps = COALESCE(EXCLUDED.reps, workout_set.reps),
              type = COALESCE(EXCLUDED.type, workout_set.type),
              completed_at = CASE WHEN EXCLUDED.deleted THEN workout_set.completed_at ELSE EXCLUDED.completed_at END,
              rpe = CASE WHEN EXCLUDED.deleted THEN workout_set.rpe ELSE EXCLUDED.rpe END,
              reps_in_reserve = CASE WHEN EXCLUDED.deleted THEN workout_set.reps_in_reserve ELSE EXCLUDED.reps_in_reserve END,
              note = CASE WHEN EXCLUDED.deleted THEN workout_set.note ELSE EXCLUDED.note END,
              external_id = CASE WHEN EXCLUDED.deleted THEN workout_set.external_id ELSE EXCLUDED.external_id END,
              annotations = CASE WHEN EXCLUDED.deleted THEN workout_set.annotations ELSE EXCLUDED.annotations END,
              updated_at = EXCLUDED.updated_at,
              server_seq = EXCLUDED.server_seq,
              deleted = EXCLUDED.deleted
            WHERE workout_set.updated_at < EXCLUDED.updated_at
            """, logger: logger)
    }

    /// `GET /v1/sync/pull?since=<cursor>&limit=<n>`: this user's changes after the cursor,
    /// tombstones included, oldest first.
    func pull(req: Request) async throws -> Response {
        let user = try req.userId()
        let since = (try? req.query.get(Int64.self, at: "since")) ?? 0
        let limit = min(max((try? req.query.get(Int.self, at: "limit")) ?? Self.maxPull, 1), Self.maxPull)
        let rows = try await req.application.db.query("""
            SELECT id, workout_exercise_id, position, load_hundredths, unit, reps, type, completed_at, rpe,
              reps_in_reserve, note, external_id, annotations, updated_at, server_seq, deleted
            FROM workout_set WHERE user_id = \(user) AND server_seq > \(since)
            ORDER BY server_seq LIMIT \(limit + 1)
            """, logger: req.logger)
        var changes: [Change] = []
        var cursor = since
        var hasMore = false
        for try await row in rows {
            if changes.count == limit { hasMore = true; break }
            let (id, weId, position, load, unit, reps, type, completed, rpe, rir, note, ext, ann, updated, seq, deleted) =
                try row.decode((String, String?, Int?, Int?, String?, Int?, String?, Date?, Double?, Int?, String?, String?, [String], Date, Int64, Bool).self)
            cursor = seq
            let setRow = deleted ? nil : SetRow(id: id, workoutExerciseId: weId ?? "", position: position ?? 0, loadHundredths: load,
                unit: unit ?? "kg", reps: reps ?? 0, type: type ?? "working", completedAt: completed, rpe: rpe,
                externalId: ext, note: note, repsInReserve: rir, annotations: ann)
            changes.append(Change(table: "workoutSet", id: id, op: deleted ? "delete" : "upsert", updatedAt: updated, row: setRow))
        }
        return try syncResponse(PullResponse(changes: changes, nextCursor: cursor, hasMore: hasMore))
    }
}
