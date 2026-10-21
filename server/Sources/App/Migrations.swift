import PostgresNIO
import Logging

/// The server schema. Each statement is idempotent, so running it on every start is safe.
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
        CREATE TABLE IF NOT EXISTS workout_set (
          user_id              uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          id                   text NOT NULL,
          workout_exercise_id  text,
          position             int  CHECK (position >= 0),
          load_hundredths      int,
          unit                 text CHECK (unit IN ('kg','lb')),
          reps                 int  CHECK (reps >= 0),
          type                 text CHECK (type IN ('working','warmUp','failed','drop')),
          completed_at         timestamptz,
          rpe                  double precision CHECK (rpe BETWEEN 1 AND 10),
          reps_in_reserve      int  CHECK (reps_in_reserve BETWEEN 0 AND 3),
          note                 text,
          external_id          text,
          annotations          text[] NOT NULL DEFAULT '{}',
          updated_at           timestamptz NOT NULL,
          server_seq           bigint NOT NULL,
          deleted              boolean NOT NULL DEFAULT false,
          PRIMARY KEY (user_id, id),
          CHECK (deleted OR (workout_exercise_id IS NOT NULL AND unit IS NOT NULL AND reps IS NOT NULL AND type IS NOT NULL AND position IS NOT NULL))
        )
        """,
        "CREATE INDEX IF NOT EXISTS workout_set_pull ON workout_set(user_id, server_seq)",
    ]

    static func run(_ client: PostgresClient, logger: Logger) async throws {
        for statement in statements { try await client.query(statement, logger: logger) }
    }
}
