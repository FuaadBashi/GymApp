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
                _ = try? await conn.query("ROLLBACK", logger: req.logger)
                throw error
            }
        }
        return try syncResponse(PushResponse(accepted: body.changes.map(\.id)))
    }

    private func upsert(_ c: Change, user: UUID, seq: Int64, on conn: PostgresConnection, logger: Logger) async throws {
        let payload = try c.row.map { String(decoding: try JSONEncoder.sync.encode($0), as: UTF8.self) }
        let deleted = c.op == "delete"
        try await conn.query("""
            INSERT INTO sync_row (user_id, table_name, id, payload, updated_at, server_seq, deleted)
            VALUES (\(user), \(c.table), \(c.id), \(deleted ? nil : payload)::jsonb, \(c.updatedAt), \(seq), \(deleted))
            ON CONFLICT (user_id, table_name, id) DO UPDATE SET
              payload = CASE WHEN EXCLUDED.deleted THEN sync_row.payload ELSE EXCLUDED.payload END,
              updated_at = EXCLUDED.updated_at,
              server_seq = EXCLUDED.server_seq,
              deleted = EXCLUDED.deleted
            WHERE sync_row.updated_at < EXCLUDED.updated_at
            """, logger: logger)
    }

    /// `GET /v1/sync/pull?since=<cursor>&limit=<n>`: this user's changes after the cursor,
    /// tombstones included, oldest first.
    func pull(req: Request) async throws -> Response {
        let user = try req.userId()
        let since = (try? req.query.get(Int64.self, at: "since")) ?? 0
        let limit = min(max((try? req.query.get(Int.self, at: "limit")) ?? Self.maxPull, 1), Self.maxPull)
        let rows = try await req.application.db.query("""
            SELECT table_name, id, payload::text, updated_at, server_seq, deleted
            FROM sync_row WHERE user_id = \(user) AND server_seq > \(since)
            ORDER BY server_seq LIMIT \(limit + 1)
            """, logger: req.logger)
        var changes: [Change] = []
        var cursor = since
        var hasMore = false
        for try await row in rows {
            if changes.count == limit { hasMore = true; break }
            let (table, id, payload, updated, seq, deleted) = try row.decode((String, String, String?, Date, Int64, Bool).self)
            cursor = seq
            let json = deleted ? nil : try payload.map { try JSONDecoder.sync.decode(JSON.self, from: Data($0.utf8)) }
            changes.append(Change(table: table, id: id, op: deleted ? "delete" : "upsert", updatedAt: updated, row: json))
        }
        return try syncResponse(PullResponse(changes: changes, nextCursor: cursor, hasMore: hasMore))
    }
}
