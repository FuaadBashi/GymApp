import Foundation
import GRDB
import Testing
@testable import GymApp

/// Card 7.8: goal projection and strength standards.
struct GoalStandardsTests {
    let start = TestData.day(0)
    private func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    /// Weekly sessions on e1RM = 120 − 40·e^(−t/100).
    private var curve: [(date: Date, value: Double)] {
        (0..<20).map { w in let t = Double(w * 7); return (day(t), 120 - 40 * exp(-t / 100)) }
    }

    @Test func theFitRecoversASaturatingCurve() throws {
        let fit = try #require(Projection.fit(curve))
        #expect(abs(fit.a - 120) < 0.5 && abs(fit.b - 40) < 0.5)
        #expect(abs(fit.c - 100) / 100 < 0.05)
        // 110 is reached when e^(−t/100) = 0.25: t = 138.6 days.
        let reach = try #require(fit.date(reaching: 110))
        #expect(abs(reach.timeIntervalSince(start) / 86_400 - 138.6) < 4)
    }

    @Test func outcomesCoverReachedUnreachableAndTooLittleData() {
        #expect(Projection.outcome(goal: 90, points: curve, now: day(140)) == .reached)
        if case .unreachable(let ceiling) = Projection.outcome(goal: 130, points: curve, now: day(140)) {
            #expect(abs(ceiling - 120) < 0.5)
        } else { Issue.record("expected unreachable") }
        #expect(Projection.outcome(goal: 110, points: Array(curve.prefix(5)), now: day(140)) == .notEnoughData)
        // Already past the goal says so even with too little data to fit.
        #expect(Projection.outcome(goal: 85, points: Array(curve.prefix(5)), now: day(140)) == .reached)
        // Six sessions inside 8 weeks are still too little.
        let short = (0..<7).map { (day(Double($0 * 7)), 80 + Double($0)) }
        #expect(Projection.fit(short) == nil)
        if case .projected = Projection.outcome(goal: 115, points: curve, now: day(140)) {} else { Issue.record("expected a projection") }
    }

    @Test func percentilesInterpolateAndClampAtTheTableEdges() throws {
        let json = """
        {"attribution": "Powered by FitnessVolt", "url": "https://fitnessvolt.com/strength-standards/", "lifts": {
          "bench-press": {"label": "Bench press", "match": [["bench", "press"]], "exclude": ["incline"], "sexes": {"male": [
            {"upperKg": 83, "sample": 1, "percentiles": {"10": 60, "50": 90, "90": 120}},
            {"upperKg": null, "sample": 1, "percentiles": {"10": 80, "50": 110, "90": 140}}]}}}}
        """
        let s = try JSONDecoder().decode(StrengthStandards.self, from: Data(json.utf8))
        #expect(s.percentile(lift: "bench-press", sex: "male", bodyWeightKg: 83, e1RM: 90) == 50)
        #expect(s.percentile(lift: "bench-press", sex: "male", bodyWeightKg: 80, e1RM: 105) == 70)
        #expect(s.percentile(lift: "bench-press", sex: "male", bodyWeightKg: 95, e1RM: 110) == 50)
        #expect(s.percentile(lift: "bench-press", sex: "male", bodyWeightKg: 80, e1RM: 200) == 99)
        #expect(s.percentile(lift: "bench-press", sex: "female", bodyWeightKg: 80, e1RM: 90) == nil)
        #expect(StrengthStandards.tier(49.9) == "Intermediate" && StrengthStandards.tier(50) == "Proficient")
        #expect(StrengthStandards.tier(9.99) == "Beginner" && StrengthStandards.tier(99) == "Top 1%")
    }

    @Test func theBundledTableLoadsAndMatchesBarbellLiftsByName() throws {
        let s = try #require(StrengthStandards.bundled)
        func exercise(_ name: String, _ equipment: Equipment) -> ExerciseRecord {
            ExerciseRecord(id: name, name: name, equipment: equipment, loadMode: .total, primaryMuscles: [.chest], secondaryMuscles: [],
                           force: nil, mechanic: nil, category: .strength, bodyRegion: .upper, movementPattern: nil, instructions: [],
                           source: .custom, libraryId: nil, stickyNote: nil, defaultRestSeconds: 60, preferredUnit: .kg,
                           isFavorite: false, isArchived: false, createdAt: start)
        }
        #expect(s.lift(for: exercise("Barbell Bench Press", .barbell)) == "bench-press")
        #expect(s.lift(for: exercise("Barbell Incline Bench Press", .barbell)) == "incline-bench-press")
        #expect(s.lift(for: exercise("Barbell Squat", .barbell)) == "squat")
        #expect(s.lift(for: exercise("Barbell Bent-Over Row", .barbell)) == "pendlay-row")
        #expect(s.lift(for: exercise("Machine Chest Press", .machine)) == nil)
    }

    @Test func goalsRoundTripAsEntered() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { try GoalQueries.setGoal($0, exerciseId: "bench", goal: Load(hundredths: 22500, unit: .lb)) }
        #expect(try db.reader.read { try GoalQueries.goal($0, exerciseId: "bench") } == Load(hundredths: 22500, unit: .lb))
        try db.writer.write { try GoalQueries.setGoal($0, exerciseId: "bench", goal: nil) }
        #expect(try db.reader.read { try GoalQueries.goal($0, exerciseId: "bench") } == nil)
    }
}
