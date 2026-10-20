import Foundation
import Testing
@testable import GymApp

/// Rulebook §13: double progression and the comeback ramp.
struct NextSetTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A finished session `daysAgo` before `now` with working sets of (kg, reps).
    private func session(_ daysAgo: Double, _ sets: [(Double, Int)], unit: WeightUnit = .kg, reserve: [Int?]? = nil) -> ExerciseSession {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        let w = WorkoutRecord(id: UUID().uuidString, startedAt: start, endedAt: start.addingTimeInterval(3600), programDayId: nil,
                              title: "W", note: nil, effort: nil, restEndsAt: nil, restDurationSeconds: nil, source: .app, externalId: nil)
        let we = WorkoutExerciseRecord(id: UUID().uuidString, workoutId: w.id, exerciseId: "e", position: 0, dayExerciseId: nil,
                                       targetSets: nil, repMin: nil, repMax: nil, restSeconds: 90, note: nil, externalId: nil)
        let records = sets.enumerated().map { i, s in
            var r = WorkoutSetRecord(id: UUID().uuidString, workoutExerciseId: we.id, position: i, loadHundredths: Int(s.0 * 100), unit: unit,
                                     reps: s.1, type: .working, completedAt: start, rpe: nil, externalId: nil)
            r.repsInReserve = reserve?[i]
            return r
        }
        return ExerciseSession(workout: w, workoutExercise: we, sets: records)
    }

    private func suggest(_ sessions: [ExerciseSession], step: Double = 2.5, range: ClosedRange<Int> = 8...12,
                         mode: LoadMode = .total) -> NextSet.Suggestion? {
        NextSet.suggest(sessions: sessions, repRange: range, stepKg: step, loadMode: mode, now: now)
    }

    @Test func everySetAtTheTopAddsAStepAndResetsReps() throws {
        let s = try #require(suggest([session(3, [(60, 12), (60, 12), (60, 12)])]))
        #expect(s.kind == .addWeight && s.loadHundredths == 6250 && s.reps == 8)
    }

    @Test func otherwiseBeatTheLowestSet() throws {
        let s = try #require(suggest([session(3, [(60, 12), (60, 10), (60, 9)])]))
        #expect(s.kind == .addReps && s.loadHundredths == 6000 && s.reps == 10)
    }

    @Test func onlySetsAtTheTopLoadCount() throws {
        // The lighter back-off set at 9 reps does not hold the progression back.
        let s = try #require(suggest([session(3, [(60, 12), (60, 12), (50, 9)])]))
        #expect(s.kind == .addWeight && s.loadHundredths == 6250)
    }

    @Test func repsNeverGoAboveTheRange() throws {
        let s = try #require(suggest([session(3, [(60, 12), (60, 15)])], range: 8...12))
        #expect(s.kind == .addWeight)
        let t = try #require(suggest([session(3, [(60, 11), (60, 13)])], range: 8...12))
        #expect(t.reps == 12)
    }

    @Test func aMonthAwayStartsAtNinetyPercentRoundedDown() throws {
        let s = try #require(suggest([session(40, [(80, 8)])]))
        #expect(s.kind == .comeback && s.loadHundredths == 7000 && s.reps == 8)   // 72 → 70 in 2.5 steps
        #expect(s.reason.contains("40 days"))
    }

    @Test func threeMonthsAwayStartsAtEightyPercent() throws {
        let s = try #require(suggest([session(120, [(100, 5)])]))
        #expect(s.kind == .comeback && s.loadHundredths == 8000)
    }

    @Test func afterTheFirstSessionBackTheRampClimbsFivePercent() throws {
        let s = try #require(suggest([session(3, [(70, 8)]), session(50, [(80, 8)])]))
        // 70 + max(2.5, 4) = 74 → 75, below the 80 target.
        #expect(s.kind == .comeback && s.loadHundredths == 7500)
    }

    @Test func theRampNeverOvershootsThePreBreakLoad() throws {
        let s = try #require(suggest([session(3, [(78, 8)]), session(50, [(80, 8)])]))
        #expect(s.loadHundredths == 8000)
    }

    @Test func onceBackAtThePreBreakLoadNormalProgressionResumes() throws {
        let s = try #require(suggest([session(3, [(80, 9)]), session(50, [(80, 8)])]))
        #expect(s.kind == .addReps)
    }

    @Test func anOldBreakNoLongerSetsTheTarget() throws {
        let recent = (1...7).map { session(Double($0 * 3), [(60, 9)]) }
        let s = try #require(suggest(recent + [session(200, [(100, 8)])]))
        #expect(s.kind == .addReps && s.loadHundredths == 6000)
    }

    @Test func poundsStayInPounds() throws {
        let s = try #require(suggest([session(3, [(135, 12), (135, 12)], unit: .lb)]))
        #expect(s.unit == .lb && s.loadHundredths == 14000)   // a 2.5 kg step is 5 lb
    }

    @Test func bodyWeightAndRepsOnlyGetNoSuggestion() {
        #expect(suggest([session(3, [(0, 10)])], mode: .repsOnly) == nil)
        #expect(suggest([session(3, [(10, 10)])], mode: .bodyweightPlus) == nil)
        #expect(suggest([]) == nil)
    }

    // Rule 4: reps in reserve.

    @Test func easySetsAtTheTopAddTwoSteps() throws {
        let s = try #require(suggest([session(3, [(60, 12), (60, 12)], reserve: [2, 3])]))
        #expect(s.kind == .addWeight && s.loadHundredths == 6500)
        #expect(s.reason.contains("reps in reserve"))
    }

    @Test func easySetsBelowTheTopAddTwoReps() throws {
        let s = try #require(suggest([session(3, [(60, 9), (60, 10)], reserve: [2, 2])]))
        #expect(s.kind == .addReps && s.reps == 11)
    }

    @Test func oneHardSetOrAMissingReserveKeepsTheNormalStep() throws {
        #expect(try #require(suggest([session(3, [(60, 9), (60, 10)], reserve: [2, 1])])).reps == 10)
        #expect(try #require(suggest([session(3, [(60, 9), (60, 10)], reserve: [3, nil])])).reps == 10)
        #expect(try #require(suggest([session(3, [(60, 12), (60, 12)], reserve: [0, 0])])).loadHundredths == 6250)
    }

    @Test func easyRepsStillStopAtTheTopOfTheRange() throws {
        let s = try #require(suggest([session(3, [(60, 11), (60, 12)], reserve: [3, 3])]))
        #expect(s.reps == 12)
    }
}
