import Foundation
import GRDB
import Testing
@testable import GymApp

/// Card 6.3: the studio suggestions inbox.
struct StudioSuggestionTests {
    let db = try! AppDatabase.inMemory()

    private let file = """
    [
      {"id": "t1", "created": "2026-10-14T09:00:00Z", "kind": "target", "title": "Bench 52.5 kg × 8",
       "detail": "Next session", "reason": "Hit 12 reps on every set", "rule": "double_progression",
       "exerciseId": "bench", "change": {"weight": 52.5, "unit": "kg", "reps": 8}},
      {"id": "s1", "created": "2026-10-14T09:01:00.500Z", "kind": "swap", "title": "Swap bench for incline",
       "detail": "", "reason": "Plateau for 3 weeks", "rule": "plateau_swap",
       "dayId": "DAY", "change": {"from": "bench", "to": "incline"}},
      {"id": "n1", "created": "2026-10-13T09:00:00Z", "kind": "note", "title": "Hamstrings are behind",
       "detail": "6 sets a week", "reason": "Below the 10–20 band", "rule": "weak_point", "change": null},
      {"id": "bad1", "created": "2026-10-14T09:00:00Z", "kind": "target", "title": "No reps",
       "detail": "", "reason": "", "rule": "x", "exerciseId": "bench", "change": {"weight": 50, "unit": "kg"}},
      {"id": "bad2", "created": "2026-10-14T09:00:00Z", "kind": "deload", "title": "Unknown kind",
       "detail": "", "reason": "", "rule": "x"},
      {"id": "bad3", "kind": "note", "title": "No date", "detail": "", "reason": "", "rule": "x"}
    ]
    """

    private func suggestions(dayId: String = "DAY") throws -> [StudioSuggestion] {
        try StudioSuggestions.parse(Data(file.replacingOccurrences(of: "\"DAY\"", with: "\"\(dayId)\"").utf8))
    }

    @Test func parsingKeepsValidItemsNewestFirstAndSkipsTheRest() throws {
        let items = try suggestions()
        #expect(items.map(\.id) == ["s1", "t1", "n1"])
        let target = try #require(items.first { $0.id == "t1" })
        #expect(target.loadHundredths == 5250 && target.change?.unit == .kg && target.change?.reps == 8)
        #expect(throws: (any Error).self) { try StudioSuggestions.parse(Data("{}".utf8)) }
    }

    @Test func acceptingATargetShowsItInTheNextWorkoutOnly() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let target = try #require(try suggestions().first { $0.id == "t1" })
        try db.writer.write { try StudioSuggestions.accept($0, target, now: TestData.day(10)) }

        let workout = try db.writer.write { try WorkoutWrites.start($0, dayId: nil, settings: AppSettings(), now: TestData.day(11)) }
        try db.writer.write { _ = try WorkoutWrites.addExercise($0, workoutId: workout.id, exerciseId: "bench", settings: AppSettings()) }
        let item = try #require(try db.reader.read { try WorkoutQueries.snapshot($0, workoutId: workout.id, settings: AppSettings()) }.items.first)
        #expect(item.studioTarget?.loadHundredths == 5250 && item.studioTarget?.unit == .kg && item.studioTarget?.reps == 8)

        // Once a workout with the exercise is finished after acceptance, the target is spent.
        try db.writer.write { db in
            try WorkoutWrites.logSet(db, setId: item.sets[0].id, now: TestData.day(11))
            _ = try WorkoutWrites.finish(db, workoutId: workout.id, now: TestData.day(11).addingTimeInterval(600))
        }
        #expect(try db.reader.read { try StudioSuggestions.activeTarget($0, exerciseId: "bench") } == nil)
    }

    @Test func acceptingASwapChangesTheDayAndNothingElse() throws {
        let dayId = try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.exercise(db, id: "incline")
            let p = try TestData.program(db)
            return try TestData.day(db, programId: p.id, name: "A", position: 0, items: ["bench"]).id
        }
        try db.writer.write { try TestData.finishedWorkout($0, dayId: dayId, startedAt: TestData.day(2), exercises: [("bench", [(50, 8)])]) }
        let swap = try #require(try suggestions(dayId: dayId).first { $0.id == "s1" })
        try db.writer.write { try StudioSuggestions.accept($0, swap, now: TestData.day(10)) }
        let items = try db.reader.read { try ProgramQueries.detail($0, dayId: dayId) }?.items
        #expect(items?.map(\.exercise.id) == ["incline"])
        #expect(try db.reader.read { try ExerciseQueries.sessions($0, exerciseId: "bench") }.count == 1)
        // A second decision on the same suggestion is refused.
        #expect(throws: StudioSuggestions.Failure.alreadyDecided) {
            try db.writer.write { try StudioSuggestions.dismiss($0, swap, now: TestData.day(11)) }
        }
    }

    @Test func aSwapWhoseExerciseLeftTheDayIsRefusedAndNotRecorded() throws {
        let dayId = try db.writer.write { db in
            try TestData.exercise(db, id: "row")
            try TestData.exercise(db, id: "incline")
            let p = try TestData.program(db)
            return try TestData.day(db, programId: p.id, name: "A", position: 0, items: ["row"]).id
        }
        let swap = try #require(try suggestions(dayId: dayId).first { $0.id == "s1" })
        #expect(throws: StudioSuggestions.Failure.changed) { try db.writer.write { try StudioSuggestions.accept($0, swap, now: TestData.day(10)) } }
        #expect(try db.reader.read { try StudioDecisionRecord.fetchCount($0) } == 0)
    }

    @Test func dismissingRemovesItFromPendingAndChangesNothing() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let all = try suggestions()
        let target = try #require(all.first { $0.id == "t1" })
        try db.writer.write { try StudioSuggestions.dismiss($0, target, now: TestData.day(10)) }
        #expect(try db.reader.read { try StudioSuggestions.pending($0, all) }.map(\.id) == ["s1", "n1"])
        #expect(try db.reader.read { try StudioSuggestions.activeTarget($0, exerciseId: "bench") } == nil)
        let decisions = try JSONSerialization.jsonObject(with: try db.reader.read { try StudioSuggestions.decisionsJSON($0) }) as? [[String: String]]
        #expect(decisions?.first?["id"] == "t1" && decisions?.first?["decision"] == "dismissed")
    }
}

/// Card 7.9: reports from the studio.
struct StudioReportTests {
    @Test func parsingSkipsBadReportsAndOrdersNewestFirst() throws {
        let json = """
        [
          {"id": "2026-W41", "kind": "week", "title": "Week of 5 Oct", "from": "2026-10-05", "to": "2026-10-12",
           "headline": "2 workouts", "sections": [{"title": "Totals", "lines": ["2 workouts"]}]},
          {"id": "2026-10", "kind": "month", "title": "October 2026", "from": "2026-10-01", "to": "2026-11-01",
           "headline": "5 workouts", "sections": [{"title": "Totals", "lines": ["5 workouts"]}]},
          {"id": "2026-W42", "kind": "week", "title": "Week of 12 Oct", "from": "2026-10-12", "to": "2026-10-19",
           "headline": "1 workout", "sections": [{"title": "Totals", "lines": ["1 workout"]}]},
          {"id": "broken", "kind": "year", "title": "x", "from": "2026-01-01", "to": "2027-01-01", "headline": "", "sections": []},
          {"id": "empty", "kind": "week", "title": "x", "from": "2026-01-01", "to": "2026-01-08", "headline": "", "sections": []}
        ]
        """
        let reports = try StudioReports.parse(Data(json.utf8))
        #expect(reports.map(\.id) == ["2026-W42", "2026-W41", "2026-10"])
        #expect(throws: (any Error).self) { try StudioReports.parse(Data("{}".utf8)) }
    }
}

/// Card 8.3: fix suggestions correct one set.
struct FixSuggestionTests {
    let db = try! AppDatabase.inMemory()

    private func fix(_ setId: String, weight: Double = 59) throws -> StudioSuggestion {
        let json = """
        [{"id": "f1", "created": "2026-10-14T09:00:00Z", "kind": "fix", "title": "Row 590 → 59", "detail": "", "reason": "slip",
          "rule": "data_health", "exerciseId": "bench", "change": {"setId": "\(setId)", "weight": \(weight), "unit": "kg", "reps": 8}}]
        """
        return try #require(try StudioSuggestions.parse(Data(json.utf8)).first)
    }

    @Test func acceptingAFixChangesOnlyThatSet() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("bench", [(59, 8), (590, 8)])])
        }
        let ids = try db.reader.read { try String.fetchAll($0, sql: "SELECT id FROM workoutSet ORDER BY loadHundredths") }
        try db.writer.write { try StudioSuggestions.accept($0, try fix(ids[1]), now: TestData.day(5)) }
        let loads = try db.reader.read { try Int.fetchAll($0, sql: "SELECT loadHundredths FROM workoutSet ORDER BY id") }
        #expect(loads.sorted() == [5900, 5900])
        #expect(try db.reader.read { try StudioDecisionRecord.fetchOne($0, key: "f1") }?.kind == .fix)
    }

    @Test func aFixForAMissingSetIsRefusedAndNotRecorded() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        #expect(throws: StudioSuggestions.Failure.notFound) {
            try db.writer.write { try StudioSuggestions.accept($0, try fix("gone"), now: TestData.day(5)) }
        }
        #expect(try db.reader.read { try StudioDecisionRecord.fetchCount($0) } == 0)
    }

    @Test func migrationV7KeepsEarlierDecisions() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v6")
        try queue.write { try $0.execute(sql: "INSERT INTO studioDecision (suggestionId, kind, decision, decidedAt, title) VALUES ('t', 'note', 'accepted', '2026-10-14 10:00:00.000', 'x')") }
        try Schema.migrator.migrate(queue)
        #expect(try queue.read { try String.fetchAll($0, sql: "SELECT suggestionId FROM studioDecision") } == ["t"])
    }
}
