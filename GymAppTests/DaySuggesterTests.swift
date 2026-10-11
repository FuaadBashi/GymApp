import Foundation
import GRDB
import Testing
@testable import GymApp

struct DaySuggesterTests {
    let db = try! AppDatabase.inMemory()

    /// The spec's fixture: D1 holds bench, D2 is empty. `TestData.day(n)` stands in for "n Oct".
    private func fixture() throws -> String {
        try db.writer.write { db in
            let history: [(String, MovementPattern, Int?, Bool)] = [
                ("squatA", .squat, 10, false), ("squatB", .squat, 1, false),
                ("bench", .horizontalPush, 9, false), ("incline", .inclinePush, 2, false),
                ("pulldown", .verticalPull, 8, false), ("rdl", .hinge, nil, false),
                ("legCurl", .kneeFlexion, 5, false), ("rowA", .horizontalPull, 7, true),
                ("rowB", .horizontalPull, 3, false), ("legExt", .kneeExtension, 6, false),
                ("curl", .bicepsCurl, 4, false), ("pushdown", .tricepsExtension, 4, false),
            ]
            for (id, pattern, lastDone, archived) in history {
                try TestData.exercise(db, id: id, pattern: pattern, archived: archived)
                if let lastDone {
                    try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(lastDone), exercises: [(id, [(50, 8)])])
                }
            }
            let p = try TestData.program(db)
            try TestData.day(db, programId: p.id, name: "D1", position: 0, items: ["bench"])
            return try TestData.day(db, programId: p.id, name: "D2", position: 1).id
        }
    }

    @Test func aFullBodyDayIsFilledFromHistory() throws {
        let d2 = try fixture()
        let suggestions = try db.reader.read { try DaySuggester.suggest($0, dayId: d2, now: TestData.day(20)) }
        #expect(suggestions.map(\.slot.name) == ["Squat", "Press", "Vertical pull", "Hinge or leg curl", "Row",
                                                 "Overhead press", "Leg extension", "Biceps", "Triceps"])
        #expect(suggestions.map { $0.exercise?.id } == ["squatA", "incline", "pulldown", "legCurl", "rowB",
                                                        nil, "legExt", "curl", "pushdown"])
        #expect(suggestions[0].alternatives.map(\.id) == ["squatB"])
        #expect(suggestions[5].reason == "Nothing in your history for this movement.")
        #expect(suggestions[0].reason.hasPrefix("Not in your other days · last done"))
    }

    @Test func anExerciseInAnotherDayStillFillsASlotWhenNothingElseCan() throws {
        let d2 = try fixture()
        try db.writer.write { try ExerciseWrites.setArchived($0, id: "incline", true) }
        let press = try db.reader.read { try DaySuggester.suggest($0, dayId: d2, now: TestData.day(20)) }[1]
        #expect(press.exercise?.id == "bench")
        #expect(press.reason.hasPrefix("Last done"))
        #expect(press.reason.hasSuffix("1 session this year"))
    }

    @Test func exercisesAlreadyInTheDayAreSkipped() throws {
        let d2 = try fixture()
        try db.writer.write { try ProgramWrites.addExercises($0, dayId: d2, exerciseIds: ["squatA"], settings: AppSettings()) }
        let squat = try db.reader.read { try DaySuggester.suggest($0, dayId: d2, now: TestData.day(20)) }[0]
        #expect(squat.exercise?.id == "squatB")
        #expect(squat.alternatives.isEmpty)
    }

    @Test func eachFocusHasItsSlots() {
        #expect(DaySuggester.slots(for: .legs).last?.name == "Abs")
        #expect(DaySuggester.slots(for: .legs).count == DaySuggester.slots(for: .lower).count + 1)
        #expect(DaySuggester.slots(for: .custom).isEmpty)
        #expect(DaySuggester.slots(for: .push).first?.patterns == [.horizontalPush])
    }
}
