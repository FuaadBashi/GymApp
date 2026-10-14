import Foundation
import GRDB
import Testing
@testable import GymApp

/// Card 7.6: supersets rotate members and rest only at the end of a round.
@MainActor
struct SupersetTests {
    let db = try! AppDatabase.inMemory()

    /// A day of `ids`, two sets each, rest 90, with the first `grouped` in one superset.
    private func model(_ ids: [String], grouped: Int) async throws -> ActiveWorkoutModel {
        let dayId = try await db.writer.write { db in
            for id in ids { try TestData.exercise(db, id: id, name: id) }
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0, items: ids)
            try db.execute(sql: "UPDATE dayExercise SET targetSets = 2, restSeconds = 90 WHERE dayId = ?", arguments: [d.id])
            let items = try DayExerciseRecord.filter(Column("dayId") == d.id).order(Column("position")).fetchAll(db)
            for other in items.prefix(grouped).dropFirst() { try ProgramWrites.superset(db, itemId: items[0].id, with: other.id) }
            return d.id
        }
        let model = ActiveWorkoutModel(db: db, notifier: FakeNotifier())
        try await model.start(dayId: dayId)
        return model
    }

    private func name(_ model: ActiveWorkoutModel) -> String? {
        model.snapshot?.items.first { $0.sets.contains { $0.id == model.selectedSetId } }?.exercise.id
    }

    @Test func aPairAlternatesAndRestsAfterTheSecond() async throws {
        let model = try await model(["A", "B", "C"], grouped: 2)
        var order: [String] = []
        var rested: [Bool] = []
        for _ in 0..<4 {
            order.append(try #require(name(model)))
            await model.log(try #require(model.selectedSetId))
            rested.append(model.snapshot?.workout.restEndsAt != nil)
        }
        #expect(order == ["A", "B", "A", "B"])
        #expect(rested == [false, true, false, true])
        #expect(name(model) == "C")
    }

    @Test func aGroupOfThreeRotatesThroughAll() async throws {
        let model = try await model(["A", "B", "C"], grouped: 3)
        var order: [String] = []
        for _ in 0..<6 {
            order.append(try #require(name(model)))
            await model.log(try #require(model.selectedSetId))
        }
        #expect(order == ["A", "B", "C", "A", "B", "C"])
    }

    @Test func ungroupingRestoresNormalRest() async throws {
        let model = try await model(["A", "B"], grouped: 2)
        let a = try #require(model.snapshot?.items.first)
        await model.unsuperset(a.id)
        #expect(model.snapshot?.items.allSatisfy { $0.workoutExercise.supersetGroup == nil } == true)
        await model.log(try #require(model.selectedSetId))
        #expect(model.snapshot?.workout.restEndsAt != nil)
        #expect(name(model) == "A")
    }
}
