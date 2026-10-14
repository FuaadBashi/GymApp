import Foundation
import GRDB
import Testing
@testable import GymApp

/// Card 6.2: Apple Health daily totals.
struct HealthTests {
    let db = try! AppDatabase.inMemory()

    @Test func upsertingTheSameDayTwiceKeepsOneRowWithTheLatestValues() throws {
        try db.writer.write { db in
            try HealthWrites.upsert(db, days: [.init(date: "2026-10-01", steps: 4000, weightKg: 80.25)])
            try HealthWrites.upsert(db, days: [.init(date: "2026-10-01", steps: 9500, weightKg: nil)])
        }
        let rows = try db.reader.read { try HealthDayRecord.fetchAll($0) }
        #expect(rows.count == 1)
        #expect(rows[0].steps == 9500 && rows[0].weightHundredths == nil && rows[0].weightUnit == nil)
        #expect(rows[0].source == "health")
    }

    @Test func aWeightWithoutAUnitIsRejected() throws {
        #expect(throws: (any Error).self) {
            try db.writer.write { try $0.execute(sql: "INSERT INTO healthDay (date, weightHundredths) VALUES ('2026-10-01', 8000)") }
        }
    }

    @Test func typedWeightWinsOverHealthOnTheSameDay() throws {
        try db.writer.write { db in
            try HealthWrites.upsert(db, days: [.init(date: "2026-10-01", steps: nil, weightKg: 81),
                                               .init(date: "2026-10-03", steps: nil, weightKg: 82)])
            try BodyEntryRecord(id: "e", date: "2026-10-01", weightHundredths: 17600, weightUnit: .lb,
                                bodyFatPercent: nil, measurements: [:], source: .app, externalId: nil).insert(db)
        }
        let weights = try db.reader.read { try BodyQueries.weights($0) }
        #expect(weights.map(\.day) == ["2026-10-01", "2026-10-03"])
        #expect(abs(weights[0].kg - 176 * WeightUnit.kgPerLb) < 0.001)
        #expect(weights[1].kg == 82)
    }

    @Test func bodyweightLookupReadsHealthWeights() throws {
        try db.writer.write { try HealthWrites.upsert($0, days: [.init(date: DayString.from(TestData.day(2)), steps: nil, weightKg: 75.5)]) }
        let kg = try db.reader.read { try BodyQueries.weightKg($0, onOrBefore: TestData.day(5)) }
        #expect(kg == 75.5)
        #expect(try db.reader.read { try BodyQueries.weightKg($0, onOrBefore: TestData.day(1)) } == nil)
    }

    @Test func stepsSummaryAveragesOnlyDaysWithACount() throws {
        let now = TestData.day(30)
        let thisWeek = HistoryQueries.weekStart(of: now, weekStartsOn: .monday)
        let calendar = HistoryQueries.calendar(.monday)
        func day(_ offset: Int, from: Date) -> String { DayString.from(calendar.date(byAdding: .day, value: offset, to: from)!) }
        try db.writer.write { db in
            try HealthWrites.upsert(db, days: [
                .init(date: day(0, from: thisWeek), steps: 10_000, weightKg: nil),
                .init(date: day(-7, from: thisWeek), steps: 4_000, weightKg: nil),
                .init(date: day(-6, from: thisWeek), steps: 6_000, weightKg: nil),
                .init(date: day(-60, from: thisWeek), steps: 50_000, weightKg: nil),
            ])
        }
        let s = try db.reader.read { try ProgressQueries.steps($0, now: now, weekStartsOn: .monday) }
        #expect(s.days.count == 3)
        #expect(s.dailyAverage == 6_667)
        #expect(s.thisWeek == 10_000 && s.lastWeek == 5_000)
    }

    @Test func recoveryAcceptsEveryLeadingRunOfMigrationsAndRejectsGaps() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for version in Schema.versions {
            let url = folder.appending(path: "\(version).sqlite")
            let queue = try DatabaseQueue(path: url.path)
            try Schema.migrator.migrate(queue, upTo: version)
            try queue.close()
            #expect(throws: Never.self) { try RecoveryStore.inspect(url) }
        }
        let gap = folder.appending(path: "gap.sqlite")
        let queue = try DatabaseQueue(path: gap.path)
        try Schema.migrator.migrate(queue)
        try queue.write { try $0.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v2'") }
        try queue.close()
        #expect(throws: (any Error).self) { try RecoveryStore.inspect(gap) }
    }
}
