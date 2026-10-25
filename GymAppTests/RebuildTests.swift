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

    // Rulebook §17

    @Test func theUsualFirstSetIsTheMedianOfRecentSessions() {
        #expect(TrainingMath.usualFirstSet([100, 90, 110]) == 100)
        #expect(TrainingMath.usualFirstSet([100, 90, 110, 104]) == 102)
        #expect(TrainingMath.usualFirstSet([100, 90, 110, 104, 96, 20]) == 100, "only the five newest count")
        #expect(TrainingMath.usualFirstSet([100, 90]) == nil, "too little to judge")
    }

    @Test func anOffDayIsTenPercentOrMoreBelowTheUsual() {
        #expect(TrainingMath.tiredDayShortfall(first: 91, usual: 100) == nil)
        #expect(abs((TrainingMath.tiredDayShortfall(first: 88, usual: 100) ?? 0) - 0.12) < 1e-9)
        #expect(TrainingMath.tiredDayShortfall(first: 80, usual: nil) == nil)
    }

    // Rulebook §8

    func scores(_ pairs: [(Int, Double)]) -> [(date: Date, score: Double)] { pairs.map { (TestData.day($0.0), $0.1) } }

    @Test func aPlateauIsThreeSessionsWithNoBetterBestThanTheWeeksBefore() throws {
        let now = TestData.day(42)
        let p = try #require(TrainingMath.plateau(scores([(15, 100), (25, 98), (30, 100), (40, 99)]), now: now))
        #expect(p == TrainingMath.Plateau(recentBest: 100, recentSessions: 3, earlierBest: 100))
        #expect(TrainingMath.plateau(scores([(15, 100), (25, 98), (30, 101), (40, 99)]), now: now) == nil, "one better session is progress")
        #expect(TrainingMath.plateau(scores([(15, 100), (35, 99), (40, 99)]), now: now) == nil, "only two sessions in the window")
        #expect(TrainingMath.plateau(scores([(30, 90), (35, 90), (40, 90)]), now: now) == nil, "a return from a break: nothing before")
    }

    @Test func oneMoreRepCountsAsProgressForBodyweightLifts() {
        let a = [PastSet(kg: 0, reps: 8, type: .working), PastSet(kg: 0, reps: 10, type: .working), PastSet(kg: 0, reps: 15, type: .warmUp)]
        #expect(TrainingMath.progressScore(a, loadMode: .repsOnly) == 10)
        let b = [PastSet(kg: 100, reps: 5, type: .working), PastSet(kg: 60, reps: 25, type: .working)]
        #expect(TrainingMath.progressScore(b, loadMode: .total) == TrainingMath.e1RM(kg: 100, reps: 5), "25 reps is outside 1–20")
    }

    @Test func theDeloadPromptNeedsTwoStalledLifts() throws {
        let p = TrainingMath.Plateau(recentBest: 1, recentSessions: 3, earlierBest: 1)
        let db = try AppDatabase.inMemory()
        let (a, b) = try db.writer.write { db in (try TestData.exercise(db, id: "Bench"), try TestData.exercise(db, id: "Row")) }
        #expect(ProgressQueries.deloadMessage([(a, p)]) == nil)
        #expect(ProgressQueries.deloadMessage([(a, p), (b, p)])?.hasPrefix("2 lifts have stalled for 3 weeks: Bench, Row.") == true)
    }
}
