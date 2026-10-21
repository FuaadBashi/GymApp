import PostgresNIO
import Vapor

/// Privacy rights: a user can take all their data and can delete their account.
struct AccountController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let account = routes.grouped("account")
        account.get("export", use: export)
        account.delete(use: delete)
    }

    struct ExportRow: Codable, Equatable {
        var table: String
        var id: String
        var updatedAt: Date
        var row: JSON
    }

    struct Export: Codable {
        var exportedAt: Date
        var rows: [ExportRow]
    }

    /// Every live row of this user, as the phone sent it. Tombstones are left out.
    func export(req: Request) async throws -> Response {
        let user = try req.userId()
        let rows = try await req.application.db.query("""
            SELECT table_name, id, payload::text, updated_at FROM sync_row
            WHERE user_id = \(user) AND NOT deleted ORDER BY server_seq
            """, logger: req.logger)
        var out: [ExportRow] = []
        for try await (table, id, payload, updated) in rows.decode((String, String, String, Date).self) {
            out.append(ExportRow(table: table, id: id, updatedAt: updated,
                                 row: try JSONDecoder.sync.decode(JSON.self, from: Data(payload.utf8))))
        }
        let response = try syncResponse(Export(exportedAt: Date(), rows: out))
        response.headers.contentDisposition = .init(.attachment, filename: "bashi-gym-export.json")
        return response
    }

    /// Deletes the user and, by cascade, every row. Backups age out on the host's schedule.
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.userId()
        try await req.application.db.query("DELETE FROM users WHERE id = \(user)", logger: req.logger)
        return .noContent
    }
}
