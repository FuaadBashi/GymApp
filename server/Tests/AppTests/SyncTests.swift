@testable import App
import JWT
import PostgresNIO
import XCTVapor

/// Runs against a real Postgres: database `bashi_test` on localhost (see README).
final class SyncTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        setenv("DATABASE_NAME", ProcessInfo.processInfo.environment["TEST_DATABASE_NAME"] ?? "bashi_test", 1)
        setenv("AUTH_DEV", "1", 1)
        app = try await Application.make(.testing)
        try await configure(app)
        try await app.db.query("TRUNCATE users CASCADE", logger: app.logger)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    // MARK: helpers

    func token(_ subject: String) async throws -> String {
        var token = ""
        try await app.test(.POST, "v1/auth/dev", beforeRequest: { req async throws in try req.content.encode(["subject": subject]) }) { res async throws in
            XCTAssertEqual(res.status, .ok)
            token = try res.content.decode(TokenResponse.self).accessToken
        }
        return token
    }

    func set(_ id: String, load: Int = 10_000, reps: Int = 8, at ms: Double) -> Change {
        Change(table: "workoutSet", id: id, op: "upsert", updatedAt: Date(timeIntervalSince1970: ms / 1000),
               row: .object(["id": .string(id), "workoutExerciseId": .string("we-1"), "position": .int(0),
                             "loadHundredths": .int(Int64(load)), "unit": .string("kg"), "reps": .int(Int64(reps)),
                             "type": .string("working"), "completedAt": .int(Int64(ms)), "annotations": .array([])]))
    }

    @discardableResult
    func push(_ changes: [Change], token: String?, expect: HTTPStatus = .ok) async throws -> HTTPStatus {
        var status = HTTPStatus.ok
        try await app.test(.POST, "v1/sync/push", beforeRequest: { req async throws in
            if let token { req.headers.bearerAuthorization = .init(token: token) }
            req.headers.contentType = .json
            req.body = ByteBuffer(data: try JSONEncoder.sync.encode(PushRequest(changes: changes)))
        }) { res async throws in status = res.status }
        XCTAssertEqual(status, expect)
        return status
    }

    func pull(token: String, since: Int64 = 0) async throws -> PullResponse {
        var out: PullResponse!
        try await app.test(.GET, "v1/sync/pull?since=\(since)", beforeRequest: { req async throws in req.headers.bearerAuthorization = .init(token: token) }) { res async throws in
            XCTAssertEqual(res.status, .ok)
            out = try JSONDecoder.sync.decode(PullResponse.self, from: Data(buffer: res.body))
        }
        return out
    }

    func count(_ id: String) async throws -> Int {
        try await app.db.query("SELECT count(*)::int FROM sync_row WHERE id = \(id)", logger: app.logger)
            .collect().first!.decode(Int.self)
    }

    // MARK: Done-when check 3: the same push twice gives one row

    func testSamePushTwiceGivesOneRow() async throws {
        let a = try await token("alice")
        let change = set("S1", at: 1_000)
        try await push([change], token: a)
        let first = try await pull(token: a)
        try await push([change], token: a)
        // Two identical copies at the same moment, as after a retry that overlapped.
        async let p1: HTTPStatus = push([change], token: a)
        async let p2: HTTPStatus = push([change], token: a)
        _ = try await (p1, p2)

        let count = try await count("S1")
        XCTAssertEqual(count, 1)
        let after = try await pull(token: a)
        XCTAssertEqual(after.changes.count, 1)
        XCTAssertEqual(after.changes, first.changes, "a repeated push changes nothing, not even server_seq")
        XCTAssertEqual(after.nextCursor, first.nextCursor)
        XCTAssertEqual(after.changes.first?.row?["loadHundredths"], .int(10_000))
        XCTAssertEqual(after.changes.first?.row?["unit"], .string("kg"))
    }

    // MARK: Done-when check 4: one user cannot read another user's rows

    func testUsersCannotReadOrOverwriteEachOther() async throws {
        let a = try await token("alice")
        let b = try await token("bob")
        try await push([set("S1", load: 10_000, at: 1_000)], token: a)

        let bobPull = try await pull(token: b)
        XCTAssertTrue(bobPull.changes.isEmpty)

        // Bob pushes with Alice's row id: he gets his own row, Alice's is untouched.
        try await push([set("S1", load: 99_900, at: 9_000)], token: b)
        let alicePull = try await pull(token: a)
        XCTAssertEqual(alicePull.changes.map(\.row?["loadHundredths"]), [.int(10_000)])
        let bobAfter = try await pull(token: b)
        XCTAssertEqual(bobAfter.changes.map(\.row?["loadHundredths"]), [.int(99_900)])
    }

    func testMissingExpiredOrForeignTokensAre401() async throws {
        try await push([set("S1", at: 1)], token: nil, expect: .unauthorized)
        try await push([set("S1", at: 1)], token: "not.a.jwt", expect: .unauthorized)

        let expired = try await app.jwt.keys.sign(UserToken(sub: .init(value: UUID().uuidString), exp: .init(value: .distantPast)))
        try await push([set("S1", at: 1)], token: expired, expect: .unauthorized)

        let otherKeys = JWTKeyCollection()
        await otherKeys.add(hmac: HMACKey(from: "someone-elses-secret-of-at-least-32-bytes"), digestAlgorithm: .sha256)
        let forged = try await otherKeys.sign(UserToken(sub: .init(value: UUID().uuidString), exp: .init(value: .distantFuture)))
        try await push([set("S1", at: 1)], token: forged, expect: .unauthorized)
        let count = try await count("S1")
        XCTAssertEqual(count, 0)
    }

    // MARK: Done-when check 5: last writer wins, deletes leave a tombstone

    func testLastWriterWinsAndTombstones() async throws {
        let a = try await token("alice")
        try await push([set("S1", load: 10_000, at: 2_000)], token: a)
        try await push([set("S1", load: 5_000, at: 1_000)], token: a)    // older: ignored
        var rows = try await pull(token: a)
        XCTAssertEqual(rows.changes.first?.row?["loadHundredths"], .int(10_000))

        try await push([Change(table: "workoutSet", id: "S1", op: "delete", updatedAt: Date(timeIntervalSince1970: 3), row: nil)], token: a)
        rows = try await pull(token: a)
        XCTAssertEqual(rows.changes.map(\.op), ["delete"])

        try await push([set("S1", load: 7_000, at: 2_500)], token: a)    // older than the delete: ignored
        rows = try await pull(token: a)
        XCTAssertEqual(rows.changes.map(\.op), ["delete"])
    }

    func testPullPagesWithCursor() async throws {
        let a = try await token("alice")
        try await push((0..<5).map { set("S\($0)", at: Double(1_000 + $0)) }, token: a)
        var seen: [String] = []
        var cursor: Int64 = 0
        var more = true
        while more {
            var page: PullResponse!
            try await app.test(.GET, "v1/sync/pull?since=\(cursor)&limit=2", beforeRequest: { req async throws in req.headers.bearerAuthorization = .init(token: a) }) { res async throws in
                page = try JSONDecoder.sync.decode(PullResponse.self, from: Data(buffer: res.body))
            }
            seen += page.changes.map(\.id); cursor = page.nextCursor; more = page.hasMore
        }
        XCTAssertEqual(seen, ["S0", "S1", "S2", "S3", "S4"])
    }

    func testInvalidChangesAreRejected() async throws {
        let a = try await token("alice")
        var bad = set("S1", at: 1)
        if case .object(var o) = bad.row { o["unit"] = .string("stone"); bad.row = .object(o) }
        try await push([bad], token: a, expect: .unprocessableEntity)
        var missing = set("S1", at: 1)
        if case .object(var o) = missing.row { o["reps"] = nil; missing.row = .object(o) }
        try await push([missing], token: a, expect: .unprocessableEntity)
        var otherId = set("S1", at: 1)
        otherId.id = "S2"
        try await push([otherId], token: a, expect: .unprocessableEntity)
        var unknown = set("S1", at: 1)
        unknown.table = "bodyEntry"
        try await push([unknown], token: a, expect: .unprocessableEntity)
        try await push((0...SyncController.maxPush).map { set("S\($0)", at: 1) }, token: a, expect: .payloadTooLarge)
        let count = try await count("S1")
        XCTAssertEqual(count, 0)
    }

    // MARK: Other kinds of row

    func testEveryKindRoundTripsExactlyIncludingFieldsTheServerDoesNotKnow() async throws {
        let a = try await token("alice")
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let exercise: JSON = .object(["id": .string("custom-1"), "name": .string("Hack squat"), "source": .string("custom"),
                                      "defaultRestSeconds": .int(120), "preferredUnit": .string("kg"),
                                      "primaryMuscles": .array([.string("quads")]), "isFavorite": .bool(true)])
        let workout: JSON = .object(["id": .string("W1"), "startedAt": .int(1_790_000_000_000), "endedAt": .int(1_790_003_600_000),
                                     "title": .string("Legs"), "effort": .int(8), "restDurationSeconds": .double(92.5)])
        let we: JSON = .object(["id": .string("WE1"), "workoutId": .string("W1"), "exerciseId": .string("custom-1"),
                                "position": .int(0), "restSeconds": .int(120), "note": .null])
        let changes = [("exercise", "custom-1", exercise), ("workout", "W1", workout), ("workoutExercise", "WE1", we)]
            .map { Change(table: $0.0, id: $0.1, op: "upsert", updatedAt: at, row: $0.2) }
        try await push(changes, token: a)
        let pulled = try await pull(token: a)
        XCTAssertEqual(pulled.changes.map(\.table), ["exercise", "workout", "workoutExercise"])
        XCTAssertEqual(pulled.changes.map(\.row), [exercise, workout, we])
    }

    func testTheSameIdInTwoTablesIsTwoRows() async throws {
        let a = try await token("alice")
        let workout: JSON = .object(["id": .string("X"), "startedAt": .int(1), "title": .string("W")])
        try await push([set("X", at: 1), Change(table: "workout", id: "X", op: "upsert", updatedAt: Date(timeIntervalSince1970: 1), row: workout)], token: a)
        let pulled = try await pull(token: a)
        XCTAssertEqual(pulled.changes.count, 2)
    }

    func testInvalidRowsOfEachKindAreRejected() async throws {
        let a = try await token("alice")
        let bad: [(String, JSON)] = [
            ("exercise", .object(["id": .string("E"), "name": .string("  "), "source": .string("custom"),
                                  "defaultRestSeconds": .int(60), "preferredUnit": .string("kg")])),
            ("workout", .object(["id": .string("E"), "startedAt": .int(2_000), "endedAt": .int(1_000), "title": .string("W")])),
            ("workoutExercise", .object(["id": .string("E"), "workoutId": .string("W"), "exerciseId": .string("x"),
                                         "position": .int(-1), "restSeconds": .int(60)])),
        ]
        for (table, row) in bad {
            try await push([Change(table: table, id: "E", op: "upsert", updatedAt: Date(), row: row)], token: a, expect: .unprocessableEntity)
        }
    }

    func testDatabaseURLIsParsedAndRequiresTLS() throws {
        let c = try databaseConfig("postgresql://bashi:s3cret@ep-cool-name.eu-central-1.aws.neon.tech/bashi?sslmode=require")
        XCTAssertEqual(c.host, "ep-cool-name.eu-central-1.aws.neon.tech")
        XCTAssertEqual(c.port, 5432)
        XCTAssertEqual(c.username, "bashi")
        XCTAssertEqual(c.password, "s3cret")
        XCTAssertEqual(c.database, "bashi")
        XCTAssertTrue(String(describing: c.tls).contains("require"), "TLS is required for a hosted database")
        XCTAssertThrowsError(try databaseConfig("mysql://a@b/c"))
        XCTAssertThrowsError(try databaseConfig("not a url"))
    }

    func testProgramsRoundTripAndAreChecked() async throws {
        let a = try await token("alice")
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let program: JSON = .object(["id": .string("P"), "name": .string("Full Body"), "split": .string("fullBody"),
                                     "isActive": .bool(true), "sessionsPerWeekGoal": .int(3)])
        let day: JSON = .object(["id": .string("D"), "programId": .string("P"), "name": .string("Full Body 1"),
                                 "focus": .string("fullBody"), "position": .int(0)])
        let item: JSON = .object(["id": .string("I"), "dayId": .string("D"), "exerciseId": .string("bench"), "position": .int(0),
                                  "targetSets": .int(3), "repMin": .int(8), "repMax": .int(12), "restSeconds": .int(90)])
        try await push([("program", "P", program), ("programDay", "D", day), ("dayExercise", "I", item)]
            .map { Change(table: $0.0, id: $0.1, op: "upsert", updatedAt: at, row: $0.2) }, token: a)
        let pulled = try await pull(token: a)
        XCTAssertEqual(pulled.changes.map(\.row), [program, day, item])

        if case .object(var o) = item { o["repMax"] = .int(4); o["repMin"] = .int(8)
            try await push([Change(table: "dayExercise", id: "I", op: "upsert", updatedAt: at.addingTimeInterval(1), row: .object(o))],
                           token: a, expect: .unprocessableEntity) }
    }

    func testExportHasEveryLiveRowAndDeleteRemovesTheAccount() async throws {
        let a = try await token("alice")
        let b = try await token("bob")
        try await push([set("S1", at: 1_000), set("S2", at: 1_000)], token: a)
        try await push([Change(table: "workoutSet", id: "S2", op: "delete", updatedAt: Date(timeIntervalSince1970: 2), row: nil)], token: a)
        try await push([set("B1", at: 1_000)], token: b)

        try await app.test(.GET, "v1/account/export", beforeRequest: { req async throws in req.headers.bearerAuthorization = .init(token: a) }) { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.headers.contentDisposition?.filename, "bashi-gym-export.json")
            let export = try JSONDecoder.sync.decode(AccountController.Export.self, from: Data(buffer: res.body))
            XCTAssertEqual(export.rows.map(\.id), ["S1"], "live rows only, and only this user's")
            XCTAssertEqual(export.rows.first?.row["loadHundredths"], .int(10_000))
        }

        try await app.test(.DELETE, "v1/account", beforeRequest: { req async throws in req.headers.bearerAuthorization = .init(token: a) }) { res async throws in
            XCTAssertEqual(res.status, .noContent)
        }
        let left = try await app.db.query("SELECT count(*)::int FROM sync_row", logger: app.logger).collect().first!.decode(Int.self)
        XCTAssertEqual(left, 1, "only bob's row is left")
        // The deleted user's token no longer works for a push.
        try await push([set("S3", at: 3_000)], token: a, expect: .unauthorized)
        try await app.test(.GET, "v1/account/export") { res async throws in XCTAssertEqual(res.status, .unauthorized) }
    }

    func testNotesBodyEntriesAndCuesRoundTripAndAreChecked() async throws {
        let a = try await token("alice")
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let note: JSON = .object(["id": .string("N"), "exerciseId": .string("bench"), "date": .string("2026-10-23"),
                                  "text": .string("Seat on 4"), "source": .string("app")])
        let body: JSON = .object(["id": .string("B"), "date": .string("2026-10-23"), "weightHundredths": .int(8_250),
                                  "weightUnit": .string("kg"), "measurements": .object([:]), "source": .string("app")])
        let cue: JSON = .object(["id": .string("C"), "exerciseId": .string("bench"), "kind": .string("setup"),
                                 "text": .string("Shoulder blades back"), "position": .int(0), "showOnOpen": .bool(true), "source": .string("owner")])
        try await push([("exerciseNote", "N", note), ("bodyEntry", "B", body), ("formCue", "C", cue)]
            .map { Change(table: $0.0, id: $0.1, op: "upsert", updatedAt: at, row: $0.2) }, token: a)
        let pulled = try await pull(token: a)
        XCTAssertEqual(pulled.changes.map(\.row), [note, body, cue])
        if case .object(var o) = body { o["weightUnit"] = .string("stone")
            try await push([Change(table: "bodyEntry", id: "B", op: "upsert", updatedAt: at.addingTimeInterval(1), row: .object(o))],
                           token: a, expect: .unprocessableEntity) }
    }
}
