import Foundation
import GRDB
import Testing
@testable import GymApp

struct HistoryTests {
    let db = try! AppDatabase.inMemory()
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Weeks

    @Test func weeksStartOnTheChosenDay() {
        // Saturday 10 October 2026, 23:30: still the week that began Sunday 4 Oct, or Monday 5 Oct.
        let late = date(2026, 10, 10, 23, 30)
        #expect(HistoryQueries.weekStart(of: late, weekStartsOn: .sunday, calendar: utc) == date(2026, 10, 4, 0))
        #expect(HistoryQueries.weekStart(of: late, weekStartsOn: .monday, calendar: utc) == date(2026, 10, 5, 0))
        // Sunday 11 October: a new week for Sunday starts, still the old one for Monday starts.
        let sunday = date(2026, 10, 11, 8)
        #expect(HistoryQueries.weekStart(of: sunday, weekStartsOn: .sunday, calendar: utc) == date(2026, 10, 11, 0))
        #expect(HistoryQueries.weekStart(of: sunday, weekStartsOn: .monday, calendar: utc) == date(2026, 10, 5, 0))
    }

    @Test func weeksGroupNewestFirstAndSkipUnfinishedWorkouts() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            for n in [1, 2, 9, 20] {
                try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(n), exercises: [("bench", [(50, 10)])])
            }
            _ = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: TestData.day(21))
        }
        let weeks = try db.reader.read { try HistoryQueries.weeks($0, settings: AppSettings()) }
        let all = weeks.flatMap(\.workouts)
        #expect(all.count == 4)
        #expect(all.map(\.workout.startedAt) == [20, 9, 2, 1].map(TestData.day))
        #expect(weeks.map(\.start) == weeks.map(\.start).sorted(by: >))
        for week in weeks {
            #expect(week.workouts.allSatisfy { HistoryQueries.weekStart(of: $0.workout.startedAt, weekStartsOn: .sunday) == week.start })
        }
    }

    // MARK: Figures

    @Test func aRowsFiguresEqualItsSummary() throws {
        let id = try db.writer.write { db -> String in
            try TestData.exercise(db, id: "pullup", name: "Pull-up", loadMode: .bodyweightPlus)
            try TestData.exercise(db, id: "bench", name: "Bench")
            try BodyEntryRecord(id: "b", date: DayString.from(TestData.day(1)), weightHundredths: 9000, weightUnit: .kg,
                                bodyFatPercent: nil, measurements: [:], source: .app, externalId: nil).insert(db)
            let w = try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5),
                                                 exercises: [("pullup", [(-45, 6)]), ("bench", [(20, 10), (60, 8)])])
            try db.execute(sql: """
                UPDATE workoutSet SET type = 'warmUp' WHERE loadHundredths = 2000
                """)
            return w.id
        }
        let item = try #require(try db.reader.read { try HistoryQueries.items($0) }.first)
        let summary = try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }
        #expect(item.volumeKg == summary.volumeKg)
        #expect(abs(item.volumeKg - 750) < 0.001)
        #expect(item.setCount == summary.setCount && item.setCount == 2)
        #expect(item.exerciseNames == ["Pull-up", "Bench"])
        #expect(item.duration == 3600)
    }

    // MARK: Calendar and goal

    @Test func workoutDaysCoverOnlyTheMonthAsked() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            for n in [0, 3, 3, 40] {   // late Sept, early Oct twice, November
                try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(n), exercises: [("bench", [(50, 10)])])
            }
        }
        let october = TestData.day(3)
        let days = try db.reader.read { try HistoryQueries.workoutDays($0, inMonthOf: october) }
        let month = Calendar.current.dateInterval(of: .month, for: october)!
        #expect(days.keys.allSatisfy { month.contains($0) })
        #expect(days[Calendar.current.startOfDay(for: TestData.day(3))]?.count == 2)
    }

    @Test func thisWeekCountsFinishedWorkoutsAgainstTheActiveGoal() throws {
        let now = Date.now
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.program(db, active: true)
            try TestData.finishedWorkout(db, dayId: nil, startedAt: HistoryQueries.weekStart(of: now, weekStartsOn: .sunday).addingTimeInterval(60),
                                         exercises: [("bench", [(50, 10)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now.addingTimeInterval(-30 * 86_400), exercises: [("bench", [(50, 10)])])
            _ = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: now)
        }
        let week = try db.reader.read { try HistoryQueries.sessionsThisWeek($0, settings: AppSettings(), now: now) }
        #expect(week.done == 1 && week.goal == 3)
    }

    // MARK: Real export

    @Test(.enabled(if: Fixtures.hasRealExport))
    func theWholeImportedHistoryIsListed() async throws {
        try await db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        _ = try await ImportService.importJEFIT(fileAt: Fixtures.realExport, into: db)
        let weeks = try await db.reader.read { try HistoryQueries.weeks($0, settings: AppSettings()) }
        let items = weeks.flatMap(\.workouts)
        #expect(items.count == 468)
        let hardSets = try await db.reader.read {
            try Int.fetchOne($0, sql: """
                SELECT COUNT(*) FROM workoutSet s JOIN workoutExercise we ON we.id = s.workoutExerciseId
                JOIN workout w ON w.id = we.workoutId
                WHERE w.endedAt IS NOT NULL AND s.completedAt IS NOT NULL AND s.type NOT IN ('warmUp', 'drop')
                """)
        }
        #expect(items.reduce(0) { $0 + $1.setCount } == hardSets)
    }
}

struct WorkoutEditingTests {
    let db = try! AppDatabase.inMemory()

    private func finished() throws -> (workout: String, sets: [String]) {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.exercise(db, id: "row")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(2), exercises: [("bench", [(57.5, 8)])])
            let w = try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5),
                                                 exercises: [("bench", [(55, 8), (55, 8)]), ("row", [(50, 10)])])
            let sets = try String.fetchAll(db, sql: """
                SELECT s.id FROM workoutSet s JOIN workoutExercise we ON we.id = s.workoutExerciseId
                WHERE we.workoutId = ? ORDER BY we.position, s.position
                """, arguments: [w.id])
            return (w.id, sets)
        }
    }

    @Test func correctingALoadChangesVolumeAndRecords() throws {
        let (id, sets) = try finished()
        let before = try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }
        #expect(before.records.isEmpty)
        #expect(before.volumeKg == 55 * 8 * 2 + 500)
        try db.writer.write { try WorkoutWrites.updateSet($0, setId: sets[0], edit: SetEdit(loadHundredths: 6000, unit: .kg, reps: 8, type: .working)) }
        let after = try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }
        #expect(after.volumeKg == 60 * 8 + 55 * 8 + 500)
        #expect(after.records.map(\.kind) == [.heaviest, .e1RM])
        #expect(after.workout.endedAt != nil)
    }

    @Test func addingALoggedSetKeepsItHistory() throws {
        let (id, _) = try finished()
        let we = try #require(try db.reader.read { try String.fetchOne($0, sql: "SELECT id FROM workoutExercise WHERE workoutId = ? AND exerciseId = 'row'", arguments: [id]) })
        let set = try db.writer.write { try WorkoutWrites.addLoggedSet($0, workoutExerciseId: we, settings: AppSettings()) }
        let workout = try #require(try db.reader.read { try WorkoutRecord.fetchOne($0, key: id) })
        #expect(set.completedAt == workout.endedAt && set.loadHundredths == 5000)
        #expect(try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }.setCount == 4)
    }

    @Test func deletingAnExercisesLastSetRemovesItButTheWorkoutsLastIsRefused() throws {
        let (id, sets) = try finished()
        try db.writer.write { try WorkoutWrites.deleteLoggedSet($0, setId: sets[2]) }   // the only row set
        var s = try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }
        #expect(s.exercises.map(\.exercise.id) == ["bench"])
        try db.writer.write { try WorkoutWrites.deleteLoggedSet($0, setId: sets[0]) }
        s = try db.reader.read { try SummaryQueries.summary($0, workoutId: id) }
        #expect(s.exercises[0].sets.map(\.position) == [0])
        #expect(throws: WorkoutError.lastSet) { try db.writer.write { try WorkoutWrites.deleteLoggedSet($0, setId: sets[1]) } }
    }

    @Test func deletingAWorkoutLeavesTheOthers() throws {
        let (id, _) = try finished()
        try db.writer.write { try WorkoutWrites.deleteFinished($0, workoutId: id) }
        #expect(try db.reader.read { try WorkoutRecord.fetchCount($0) } == 1)
        #expect(try db.reader.read { try WorkoutSetRecord.fetchCount($0) } == 1)
    }

    @Test func renamingTrimsAndRejectsEmpty() throws {
        let (id, _) = try finished()
        try db.writer.write { try WorkoutWrites.rename($0, workoutId: id, title: "  Heavy day ") }
        #expect(try db.reader.read { try WorkoutRecord.fetchOne($0, key: id)?.title } == "Heavy day")
        #expect(throws: WorkoutError.emptyTitle) { try db.writer.write { try WorkoutWrites.rename($0, workoutId: id, title: "  ") } }
    }
}
