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

/// Card 7.5: the end screen's comparison and reopening.
struct EndScreenTests {
    let db = try! AppDatabase.inMemory()

    @Test func comparesWithTheSameDayFirstAndMarksBests() throws {
        let (dayId, today) = try db.writer.write { db -> (String, WorkoutRecord) in
            try TestData.exercise(db, id: "bench")
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "A", position: 0, items: ["bench"])
            try TestData.finishedWorkout(db, dayId: d.id, startedAt: TestData.day(1), exercises: [("bench", [(50, 10)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(3), exercises: [("bench", [(40, 10)])])
            let t = try TestData.finishedWorkout(db, dayId: d.id, startedAt: TestData.day(5), exercises: [("bench", [(55, 10)])])
            return (d.id, t)
        }
        _ = dayId
        let s = try db.reader.read { try SummaryQueries.summary($0, workoutId: today.id) }
        #expect(s.previous?.workout.startedAt == TestData.day(1))
        let line = try #require(s.exercises.first)
        #expect(line.best == .allTime(beat: TrainingMath.e1RM(kg: 50, reps: 10)))
        #expect(line.lastTime?.first?.loadHundredths == 5000)
        #expect(abs((line.e1RMChange ?? 0) - (TrainingMath.e1RM(kg: 55, reps: 10) - TrainingMath.e1RM(kg: 50, reps: 10))) < 1e-9)
        #expect(line.volumeChange == 50)
    }

    @Test func reopenThenFinishKeepsEverySetAndIsRefusedWhileAnotherIsOpen() throws {
        let w = try db.writer.write { db -> WorkoutRecord in
            try TestData.exercise(db, id: "bench")
            return try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("bench", [(50, 10), (50, 9)])])
        }
        try db.writer.write { try WorkoutWrites.reopen($0, workoutId: w.id) }
        #expect(try db.reader.read { try WorkoutQueries.inProgress($0)?.id } == w.id)
        _ = try db.writer.write { try WorkoutWrites.finish($0, workoutId: w.id, now: TestData.day(1).addingTimeInterval(4000)) }
        #expect(try db.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workoutSet") } == 2)

        _ = try db.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: TestData.day(2)) }
        #expect(throws: WorkoutError.alreadyInProgress) { try db.writer.write { try WorkoutWrites.reopen($0, workoutId: w.id) } }
    }
}
