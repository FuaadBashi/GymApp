import Foundation
import GRDB
import Testing
@testable import GymApp

@MainActor
final class FakeNotifier: RestScheduling {
    var scheduled: (date: Date, body: String)?
    var permissionRequests = 0
    func requestPermission() async { permissionRequests += 1 }
    func schedule(at date: Date, body: String) { scheduled = (date, body) }
    func cancel() { scheduled = nil }
}

@MainActor
struct ActiveWorkoutModelTests {
    let db = try! AppDatabase.inMemory()
    let notifier = FakeNotifier()

    /// A day with bench (2 sets) then row (1 set), rest 90, no history.
    private func model() async throws -> ActiveWorkoutModel {
        let dayId = try await db.writer.write { db in
            try TestData.exercise(db, id: "bench", name: "Bench")
            try TestData.exercise(db, id: "row", name: "Row")
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0, items: ["bench", "row"])
            try db.execute(sql: "UPDATE dayExercise SET targetSets = 2, restSeconds = 90 WHERE dayId = ? AND exerciseId = 'bench'", arguments: [d.id])
            try db.execute(sql: "UPDATE dayExercise SET targetSets = 1, restSeconds = 90 WHERE dayId = ? AND exerciseId = 'row'", arguments: [d.id])
            return d.id
        }
        let model = ActiveWorkoutModel(db: db, notifier: notifier)
        try await model.start(dayId: dayId)
        return model
    }

    @Test func selectionAdvancesThroughSetsThenItems() async throws {
        let model = try await model()
        let bench = try #require(model.snapshot?.items[0])
        let row = try #require(model.snapshot?.items[1])
        #expect(model.currentItemId == bench.id && model.selectedSetId == bench.sets[0].id)
        #expect(model.isPresented && notifier.permissionRequests == 1)

        await model.log(bench.sets[0].id)
        #expect(model.currentItemId == bench.id && model.selectedSetId == bench.sets[1].id)

        await model.log(bench.sets[1].id)
        #expect(model.currentItemId == row.id && model.selectedSetId == row.sets[0].id)

        await model.log(row.sets[0].id)
        #expect(model.selectedSetId == nil)
        #expect(model.snapshot?.completedSetCount == 3)
    }

    @Test func loggingSchedulesTheNextSetAndSkippingCancels() async throws {
        let model = try await model()
        let bench = try #require(model.snapshot?.items[0])
        await model.update(bench.sets[1].id, edit: SetEdit(loadHundredths: 5000, unit: .kg, reps: 10, type: .working))
        await model.log(bench.sets[0].id)
        let scheduled = try #require(notifier.scheduled)
        #expect(scheduled.body == "Next: Bench, set 2 — 50 kg × 10")
        #expect(scheduled.date == model.snapshot?.workout.restEndsAt)

        await model.skipRest()
        #expect(notifier.scheduled == nil)
    }

    @Test func theNotificationWrapsRoundToEarlierItems() async throws {
        let model = try await model()
        let snapshot = try #require(model.snapshot)
        let row = snapshot.items[1]
        #expect(ActiveWorkoutModel.notificationBody(snapshot, from: row.id) == "Next: Row, set 1 — 0 kg × 8")
        await model.log(row.sets[0].id)
        let after = try #require(model.snapshot)
        #expect(ActiveWorkoutModel.notificationBody(after, from: row.id) == "Next: Bench, set 1 — 0 kg × 8")
    }

    @Test func aSecondStartExplainsItself() async throws {
        let model = try await model()
        await #expect(throws: WorkoutError.alreadyInProgress) { try await model.start(dayId: nil) }
        #expect(model.lastError == "Finish or discard the workout in progress first.")
    }

    @Test func resumeFindsTheWorkoutInProgress() async throws {
        let first = try await model()
        let bench = try #require(first.snapshot?.items[0])
        await first.log(bench.sets[0].id)

        let relaunched = ActiveWorkoutModel(db: db, notifier: FakeNotifier())
        await relaunched.resumeIfNeeded()
        #expect(relaunched.snapshot?.workout.id == first.snapshot?.workout.id)
        #expect(relaunched.selectedSetId == bench.sets[1].id)
        #expect(relaunched.snapshot?.workout.restEndsAt == first.snapshot?.workout.restEndsAt)
    }

    @Test func finishingClearsTheModelAndRemembersTheWorkout() async throws {
        let model = try await model()
        let bench = try #require(model.snapshot?.items[0])
        let id = try #require(model.snapshot?.workout.id)
        await model.log(bench.sets[0].id)
        await model.finish()
        #expect(model.snapshot == nil && !model.isPresented)
        #expect(model.justFinishedWorkoutId == id)
        #expect(notifier.scheduled == nil)
    }
    @Test func failedFinishKeepsTheWorkoutOpenAndItsSetsIntact() async throws {
        let model = try await model()
        let bench = try #require(model.snapshot?.items[0])
        await model.log(bench.sets[0].id)
        let before = try #require(model.snapshot)
        try await db.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_finish BEFORE UPDATE OF endedAt ON workout
                WHEN NEW.endedAt IS NOT NULL
                BEGIN SELECT RAISE(ABORT, 'finish write failed'); END
                """)
        }
        await model.finish()
        #expect(model.snapshot == before)
        #expect(model.isPresented)
        #expect(model.justFinishedWorkoutId == nil)
        #expect(model.lastError != nil)
        let persisted = try await db.reader.read {
            try WorkoutQueries.snapshot($0, workoutId: before.workout.id, settings: try AppSettings.load($0))
        }
        #expect(persisted == before)
        #expect(notifier.scheduled != nil)
        await model.skipRest()
    }

    @Test func failedDiscardKeepsTheWorkoutOpen() async throws {
        let model = try await model()
        let before = try #require(model.snapshot)
        try await db.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_discard BEFORE DELETE ON workout
                BEGIN SELECT RAISE(ABORT, 'discard write failed'); END
                """)
        }
        await model.discard()
        #expect(model.snapshot == before)
        #expect(model.isPresented)
        #expect(model.lastError != nil)
        let id = try await db.reader.read { try WorkoutQueries.inProgress($0)?.id }
        #expect(id == before.workout.id)
    }

    @Test func restExpiresWhileTheWorkoutScreenIsMinimised() async throws {
        let model = try await model()
        let set = try #require(model.snapshot?.items.first?.sets.first)
        await model.log(set.id)
        model.isPresented = false
        await model.adjustRest(by: -89.8)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.snapshot?.workout.restEndsAt == nil)
        #expect(notifier.scheduled == nil)
    }

    @Test func extendingRestCancelsItsEarlierExpiry() async throws {
        let model = try await model()
        let set = try #require(model.snapshot?.items.first?.sets.first)
        await model.log(set.id)
        await model.adjustRest(by: -89.8)
        await model.adjustRest(by: 30)
        let end = try #require(model.snapshot?.workout.restEndsAt)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.snapshot?.workout.restEndsAt == end)
        await model.skipRest()
        #expect(model.snapshot?.workout.restEndsAt == nil)
    }

}
