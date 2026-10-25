import PostgresNIO
import Logging

/// The server schema. Each statement is idempotent, so running it on every start is safe.
/// Synced rows are stored as the phone's JSON, one table for all kinds: the server checks
/// each kind against its own rules (SyncDTO.swift) but never needs to read the fields.
enum Migrations {
    static let statements: [PostgresQuery] = [
        """
        CREATE TABLE IF NOT EXISTS users (
          id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          apple_sub   text UNIQUE NOT NULL,
          change_seq  bigint NOT NULL DEFAULT 0,
          created_at  timestamptz NOT NULL DEFAULT now()
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS sync_row (
          user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          table_name  text NOT NULL,
          id          text NOT NULL,
          payload     jsonb,
          updated_at  timestamptz NOT NULL,
          server_seq  bigint NOT NULL,
          deleted     boolean NOT NULL DEFAULT false,
          PRIMARY KEY (user_id, table_name, id),
          CHECK (deleted OR payload IS NOT NULL)
        )
        """,
        "CREATE INDEX IF NOT EXISTS sync_row_pull ON sync_row(user_id, server_seq)",
        """
        CREATE TABLE IF NOT EXISTS refresh_token (
          token_hash  text PRIMARY KEY,
          user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          expires_at  timestamptz NOT NULL,
          created_at  timestamptz NOT NULL DEFAULT now()
        )
        """,
        // The table list lives in SyncDTO's Change.rowTypes; a CHECK here needed a migration per table.
        "ALTER TABLE sync_row DROP CONSTRAINT IF EXISTS sync_row_table_name_check",
    ]

    static func run(_ client: PostgresClient, logger: Logger) async throws {
        for statement in statements { try await client.query(statement, logger: logger) }
    }
}
