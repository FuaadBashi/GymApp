import Foundation
import GRDB
import Testing
@testable import GymApp

struct SummaryTests {
    let db = try! AppDatabase.inMemory()

    private func bodyWeight(_ db: Database, kg: Double, on date: Date) throws {
        try BodyEntryRecord(id: UUID().uuidString, date: DayString.from(date), weightHundredths: Int(kg * 100), weightUnit: .kg,
                            bodyFatPercent: nil, measurements: [:], source: .app, externalId: nil).insert(db)
    }

    @Test func volumeUsesBodyWeightAndRecordsBeatEarlierBests() throws {
        let id = try db.writer.write { db -> String in
            try TestData.exercise(db, id: "pullup", loadMode: .bodyweightPlus)
            try TestData.exercise(db, id: "bench")
            try bodyWeight(db, kg: 90, on: TestData.day(1))
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(2), exercises: [("bench", [(57.5, 8)])])
            return try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5),
                                                exercises: [("pullup", [(-45, 6)]), ("bench", [(60, 8)])]).id
        }
        let summary = try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }
        #expect(abs(summary.volumeKg - 750) < 0.001)
        #expect(summary.records.map(\.kind) == [.heaviest, .e1RM])
        #expect(summary.records[0].valueKg == 60 && summary.records[0].previousKg == 57.5)
        #expect(abs(summary.records[1].valueKg - 76.0) < 0.005)
        #expect(abs(summary.records[1].previousKg - 72.83) < 0.005)
        #expect(summary.setCount == 2)
    }

    @Test func aFirstEverSessionSetsNoRecord() throws {
        let id = try db.writer.write { db -> String in
            try TestData.exercise(db, id: "bench")
            return try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5), exercises: [("bench", [(60, 8)])]).id
        }
        #expect(try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }.records.isEmpty)
    }

    @Test func musclesCountHardSets() throws {
        let id = try db.writer.write { db -> String in
            var bench = try TestData.exercise(db, id: "bench")
            bench.primaryMuscles = [.chest]
            bench.secondaryMuscles = [.triceps, .shoulders]
            try bench.update(db)
            return try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5), exercises: [("bench", [(60, 8), (60, 7)])]).id
        }
        let muscles = try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }.muscles
        #expect(muscles.map(\.muscle) == [.chest, .shoulders, .triceps])
        #expect(muscles.map(\.sets) == [2, 1, 1])
    }

    @Test func previousVolumeComesFromTheDayLineage() throws {
        let (first, second) = try db.writer.write { db -> (String, String) in
            try TestData.exercise(db, id: "bench")
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0)
            let a = try TestData.finishedWorkout(db, dayId: d.id, startedAt: TestData.day(2), exercises: [("bench", [(50, 10)])])
            let b = try TestData.finishedWorkout(db, dayId: d.id, startedAt: TestData.day(5), exercises: [("bench", [(60, 8)])])
            return (a.id, b.id)
        }
        #expect(try db.reader.read { try SummaryQueries.summary($0, workoutId: first) }.previousVolumeKg == nil)
        #expect(try db.reader.read { try SummaryQueries.summary($0, workoutId: second) }.previousVolumeKg == 500)
    }

    @Test func bodyWeightIsTheLatestOnOrBeforeTheDay() throws {
        try db.writer.write { db in
            try bodyWeight(db, kg: 88, on: TestData.day(1))
            try bodyWeight(db, kg: 90, on: TestData.day(3))
            try bodyWeight(db, kg: 95, on: TestData.day(9))
        }
        #expect(try db.reader.read { try BodyQueries.weightKg($0, onOrBefore: TestData.day(5)) } == 90)
        #expect(try db.reader.read { try BodyQueries.weightKg($0, onOrBefore: TestData.day(0)) } == nil)
    }
}
