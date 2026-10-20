import Foundation
import GRDB
import Testing
@testable import GymApp

/// Redesign card R.0: local usage counts.
struct UsageTests {
    @Test func countsAddUpAndExportMostUsedFirst() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            for _ in 0..<3 { try Usage.record(db, key: "tap.log", now: TestData.base) }
            try Usage.record(db, key: "screen.train", now: TestData.base.addingTimeInterval(60))
        }
        let csv = try db.reader.read { try Usage.csv($0) }
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines[0] == "key,count,last")
        #expect(lines[1].hasPrefix("tap.log,3,"))
        #expect(lines[2].hasPrefix("screen.train,1,"))
    }

    @MainActor @Test func loggingASetIsCounted() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { try TestData.exercise($0, id: "a") }
        let model = ActiveWorkoutModel(db: db, notifier: FakeNotifier())
        try await model.start(dayId: nil)
        await model.addExercise("a")
        let set = try #require(model.snapshot?.items.first?.sets.first)
        await model.log(set.id)
        try await Task.sleep(for: .milliseconds(200))   // counts are written in the background
        let counts = try await db.reader.read { try [String: Int](uniqueKeysWithValues: Row.fetchAll($0, sql: "SELECT key, count FROM usageCount").map { ($0["key"], $0["count"]) }) }
        #expect(counts["tap.log"] == 1 && counts["tap.start"] == 1)
    }
}
