# Bashi Gym sync server

The practice backend from [docs/backend/01-plan.md](../docs/backend/01-plan.md): Vapor and
Postgres. It syncs exercises, workouts, workout exercises and sets. Each row is stored as
the phone's JSON in one table, `sync_row`, keyed by user, table and id. The server checks
each kind of row against its rules before it stores the row.

## Run on the Mac

Needs Postgres (Homebrew `postgresql@17` works) and Swift 6.

```bash
createdb bashi_dev; createdb bashi_test
AUTH_DEV=1 swift run Run serve --hostname 0.0.0.0 --port 8080
```

Settings:

| Variable | Default | Meaning |
|---|---|---|
| `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_NAME` | localhost, 5432, `$USER`, none, `bashi_dev` | Postgres |
| `DATABASE_TLS` | off | `1` to require TLS (hosted databases need it) |
| `JWT_SECRET` | a development value | Required in production, 32 bytes or more |
| `APPLE_BUNDLE_ID` | none | For `POST /v1/auth/apple` |
| `AUTH_DEV` | off | `1` enables `POST /v1/auth/dev`, sign-in with no Apple account. Never in production |

The schema is created on start (`Sources/App/Migrations.swift`).

## Endpoints

- `POST /v1/auth/dev {"subject"}` and `POST /v1/auth/apple {"identityToken"}` return
  `{accessToken, expiresIn}`.
- `POST /v1/sync/push {"changes": [...]}`: at most 200 changes. Needs `Authorization: Bearer`.
- `GET /v1/sync/pull?since=<cursor>&limit=<n>` returns `{changes, nextCursor, hasMore}`.

Dates on the wire are milliseconds since 1970.

## Tests

```bash
swift test
```

These run against the `bashi_test` database. They check:

- the same push twice gives one row;
- one user cannot read or overwrite another user's rows;
- the 401 cases;
- last-writer-wins, with tombstones;
- paging;
- the checks for each kind of row;
- an exact round trip, including fields the server does not know.

The app's tests against this server, run from the repository root with the server running:

```bash
SYNC_SERVER=1 TEST_RUNNER_SYNC_SERVER=http://localhost:8080 xcodebuild test -project GymApp.xcodeproj -scheme GymApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:GymAppTests/SyncServerIntegrationTests
```

## Load test

```bash
k6 run -e BASE=http://localhost:8080 loadtest/sync.js
```

The test sends 14 pushes/s and 3 pulls/s for 5 minutes, which is 10× the planned peak. It
passes when p95 is under 300 ms and fewer than 0.1% of requests fail.

## Deploy (free): Render + Neon

You do these steps yourself: each needs an account.

1. **Neon** (neon.tech): sign up and create a project named `bashi`, in AWS US East 2 (Ohio):
   render.yaml puts the server in Ohio too, so the two are close. Under **Connect**, turn **connection pooling off** (the server keeps its own pool) and copy the
   connection string. It looks like
   `postgresql://user:password@ep-….neon.tech/neondb?sslmode=require`.
2. **Render** (render.com): sign up with GitHub. Choose **New → Blueprint**, then pick this
   repository. Render reads `render.yaml` at the repository root.
3. When Render asks for `DATABASE_URL`, paste the Neon string. Render generates `JWT_SECRET`.
4. Deploy. The first build takes about 10 minutes (it compiles Swift). Then check:

   ```bash
   curl https://<your-service>.onrender.com/health
   ```

5. Load test against the deployed host:

   ```bash
   k6 run -e BASE=https://<your-service>.onrender.com loadtest/sync.js
   ```

6. On the phone: Settings → Sync (beta). Enter the `https://…onrender.com` address and an
   account name, then tap Turn on sync.

Free-tier limits:

- Render's free service sleeps after 15 minutes idle. The first request after that takes
  about a minute, so the app's retries cover it.
- Neon's free storage is 0.5 GB.
- `AUTH_DEV=1` lets anyone with the URL create an account. That is acceptable for practice
  only; replace it with Sign in with Apple before real users.

## Free tier first: when to pay

Start on a free Postgres (Neon or Supabase, about 0.5 GB). Check the size each week:

```bash
psql "$DATABASE_URL" -c "SELECT pg_size_pretty(pg_database_size(current_database())), (SELECT count(*) FROM workout_set) AS sets"
```

Move to the paid plan at **80% of the free limit** (about 400 MB), or when you need
point-in-time restore. At 1,000 active users a day, that is about three months. Moving is a
`pg_dump` and a `pg_restore`, because the server uses only plain Postgres.
