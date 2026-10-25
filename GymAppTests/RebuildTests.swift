import Foundation
import GRDB
import Testing
@testable import GymApp

/// Rulebook §15.
@Suite struct RebuildTests {
    let now = TestData.day(400)
    func h(_ pairs: [(Int, Double)]) -> [(date: Date, e1RM: Double)] { pairs.map { (TestData.day($0.0), $0.1) } }

    @Test func aLiftBelowItsPeakShowsHowMuchIsBack() throws {
        let r = try #require(TrainingMath.rebuild(h([(10, 124), (200, 110), (390, 45), (398, 60)]), now: now))
        #expect(r.peak == 124 && r.current == 60 && r.peakDate == TestData.day(10))
        #expect(abs(r.share - 60.0 / 124) < 1e-9)
    }

    @Test func nothingToRebuildAtThePeakOrWithoutRecentTraining() {
        #expect(TrainingMath.rebuild(h([(10, 100), (395, 96)]), now: now) == nil, "95% or more is not a rebuild")
        #expect(TrainingMath.rebuild(h([(10, 100), (300, 60)]), now: now) == nil, "not trained in the last 28 days")
        #expect(TrainingMath.rebuild([], now: now) == nil)
        #expect(TrainingMath.rebuild(h([(395, 80)]), now: now) == nil, "the only session is the peak")
    }

    @Test func progressListsTheLiftsFurthestFromTheirPeakFirst() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try TestData.exercise(db, id: "squat")
            try TestData.exercise(db, id: "bench")
            try TestData.exercise(db, id: "old")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(0),
                                         exercises: [("squat", [(kg: 120, reps: 1)]), ("bench", [(kg: 90, reps: 1)]), ("old", [(kg: 50, reps: 1)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(390),
                                         exercises: [("squat", [(kg: 48, reps: 1)]), ("bench", [(kg: 72, reps: 1)])])
        }
        let list = try db.reader.read { try ProgressQueries.rebuilds($0, now: TestData.day(400)) }
        #expect(list.map(\.exercise.id) == ["squat", "bench"], "squat at 40% before bench at 80%; 'old' was not trained lately")
    }
}
