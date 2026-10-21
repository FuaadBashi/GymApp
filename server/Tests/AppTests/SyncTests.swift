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
               row: SetRow(id: id, workoutExerciseId: "we-1", position: 0, loadHundredths: load, unit: "kg", reps: reps,
                           type: "working", completedAt: Date(timeIntervalSince1970: ms / 1000), rpe: nil, externalId: nil,
                           note: nil, repsInReserve: nil, annotations: []))
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
        try await app.db.query("SELECT count(*)::int FROM workout_set WHERE id = \(id)", logger: app.logger)
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
        XCTAssertEqual(after.changes.first?.row?.loadHundredths, 10_000)
        XCTAssertEqual(after.changes.first?.row?.unit, "kg")
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
        XCTAssertEqual(alicePull.changes.map(\.row?.loadHundredths), [10_000])
        let bobAfter = try await pull(token: b)
        XCTAssertEqual(bobAfter.changes.map(\.row?.loadHundredths), [99_900])
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
        XCTAssertEqual(rows.changes.first?.row?.loadHundredths, 10_000)

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
        bad.row?.unit = "stone"
        try await push([bad], token: a, expect: .unprocessableEntity)
        try await push((0...SyncController.maxPush).map { set("S\($0)", at: 1) }, token: a, expect: .payloadTooLarge)
        let count = try await count("S1")
        XCTAssertEqual(count, 0)
    }
}
