import Foundation
import GRDB
import Testing
@testable import GymApp

/// Card 7.1: rulebook §5a, time-window bests.
struct BestStatusTests {
    let start = TestData.day(0)
    private func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    @Test func aLiftTrainedWeeklyOnlyShowsAllTimeBests() {
        // Best 100 on day 0, then weekly sessions at 90 for 20 weeks.
        let history = [(day(0), 100.0)] + (1...20).map { (day(Double($0) * 7), 90.0) }
        #expect(TrainingMath.bestStatus(e1RM: 95, history: history, at: day(147)) == .none)
        #expect(TrainingMath.bestStatus(e1RM: 101, history: history, at: day(147)) == .allTime(beat: 100))
    }

    @Test func aComebackEarnsTheLongestWindowItBeats() {
        // Best 100 eight months before, then 80, 85 and 70, then three months off.
        let now = day(300)
        let history = [(day(60), 100.0), (day(90), 80.0), (day(130), 85.0), (day(210), 70.0)]
        // The 12-month window holds the 100 (not below all-time); the 6-month window (from
        // day 118) holds 85 and 70; the 1-month window is empty.
        #expect(TrainingMath.bestStatus(e1RM: 86, history: history, at: now) == .window(months: 6, beat: 85))
        #expect(TrainingMath.bestStatus(e1RM: 75, history: history, at: now) == .none)
        // Back after the gap: the comeback session sits in the 1-month window.
        let back = history + [(day(295), 72.0)]
        #expect(TrainingMath.bestStatus(e1RM: 74, history: back, at: now) == .window(months: 1, beat: 72))
    }

    @Test func aGapUnderAMonthKeepsTheAllTimeMark() {
        let history = [(day(0), 100.0), (day(7), 90.0), (day(28), 88.0)]
        #expect(TrainingMath.bestStatus(e1RM: 95, history: history, at: day(55)) == .none)
    }

    @Test func tiesAndFirstSetsAreNotBests() {
        #expect(TrainingMath.bestStatus(e1RM: 100, history: [], at: day(0)) == .none)
        #expect(TrainingMath.bestStatus(e1RM: 100.005, history: [(day(0), 100)], at: day(1)) == .none)
        #expect(TrainingMath.bestStatus(e1RM: 100, history: [(day(0), 100), (day(10), 80)], at: day(200)) == .none)
    }

    @Test func marksAndHistoryComeFromCountedSetsOnly() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("bench", [(40, 10), (60, 8)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(100), exercises: [("bench", [(50, 5)])])
            try db.execute(sql: "UPDATE workoutSet SET type = 'warmUp' WHERE loadHundredths = 4000")
        }
        let sessions = try db.reader.read { try ExerciseQueries.sessions($0, exerciseId: "bench") }
        let history = ExerciseStats.e1RMHistory(sessions, loadMode: .total)
        #expect(history.map(\.e1RM) == [TrainingMath.e1RM(kg: 60, reps: 8), TrainingMath.e1RM(kg: 50, reps: 5)])
        let marks = ExerciseStats.marks(history, at: TestData.day(110))
        #expect(marks.allTime == 76)
        #expect(marks.windows[1] == TrainingMath.e1RM(kg: 50, reps: 5))
        #expect(marks.windows[12] == 76)
    }
}
