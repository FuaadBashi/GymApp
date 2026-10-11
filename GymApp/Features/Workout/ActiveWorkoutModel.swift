import ActivityKit
import OSLog
import Foundation
import GRDB
import Observation

/// The one workout in progress, for the whole app. Every change is a `WorkoutWrites` call,
/// then a reload, then the rest alert is brought in line with `restEndsAt`.
@Observable
final class ActiveWorkoutModel {
    private(set) var snapshot: WorkoutSnapshot?
    var currentItemId: String?   // the card that is open
    var selectedSetId: String?   // the row the editor and Log button act on
    var focusMode = false
    var isPresented = false      // full-screen workout showing
    private(set) var justFinishedWorkoutId: String?
    var lastError: String?

    let db: AppDatabase
    private let notifier: RestScheduling
    private var askedPermission = false
    private var restActivity: Activity<RestActivityAttributes>?
    private var activityEndTask: Task<Void, Never>?
    private static let activityLog = Logger(subsystem: "com.fuaadshurie.GymApp", category: "RestActivity")

    init(db: AppDatabase, notifier: RestScheduling = RestNotifier()) {
        self.db = db
        self.notifier = notifier
    }

    var isActive: Bool { snapshot != nil }
    var currentItem: WorkoutSnapshot.Item? { snapshot?.items.first { $0.id == currentItemId } }

    // MARK: Lifecycle

    func resumeIfNeeded() async {
        guard snapshot == nil else { return }
        let id = try? await db.reader.read { try WorkoutQueries.inProgress($0)?.id }
        guard let id else { await endRestActivity(); return }
        await reload(workoutId: id)
        selectFirstPlanned()
    }

    func start(dayId: String?) async throws {
        do {
            let workout = try await db.writer.write { db in
                try WorkoutWrites.start(db, dayId: dayId, settings: try AppSettings.load(db), now: .now)
            }
            if !askedPermission {
                askedPermission = true
                await notifier.requestPermission()
            }
            justFinishedWorkoutId = nil
            await reload(workoutId: workout.id)
            selectFirstPlanned()
            isPresented = true
        } catch WorkoutError.alreadyInProgress {
            lastError = Self.message(for: WorkoutError.alreadyInProgress)
            throw WorkoutError.alreadyInProgress
        }
    }

    func finish() async {
        guard let id = snapshot?.workout.id else { return }
        guard let finished = await write({ try WorkoutWrites.finish($0, workoutId: id, now: .now) }) else { return }
        notifier.cancel()
        await endRestActivity()
        snapshot = nil
        currentItemId = nil
        selectedSetId = nil
        isPresented = false
        justFinishedWorkoutId = finished?.id
    }

    func discard() async {
        guard let id = snapshot?.workout.id else { return }
        guard await write({ try WorkoutWrites.discard($0, workoutId: id) }) != nil else { return }
        notifier.cancel()
        await endRestActivity()
        snapshot = nil
        currentItemId = nil
        selectedSetId = nil
        isPresented = false
    }

    func clearJustFinished() { justFinishedWorkoutId = nil }

    /// Reload after a change made outside the engine, such as an exercise's sticky note.
    func refresh() async {
        guard let id = snapshot?.workout.id else { return }
        await reload(workoutId: id)
    }

    // MARK: Sets

    func log(_ setId: String) async {
        let itemId = snapshot?.items.first { $0.sets.contains { $0.id == setId } }?.id
        guard await change({ try WorkoutWrites.logSet($0, setId: setId, now: .now) }) != nil else { return }
        advance(from: itemId)
    }

    func unlog(_ setId: String) async {
        guard await change({ try WorkoutWrites.unlogSet($0, setId: setId) }) != nil else { return }
        selectedSetId = setId
    }

    func update(_ setId: String, edit: SetEdit) async {
        await change { try WorkoutWrites.updateSet($0, setId: setId, edit: edit) }
    }

    func addSet(to itemId: String) async {
        guard let newId = await change({ db in
            try WorkoutWrites.addSet(db, workoutExerciseId: itemId, settings: try AppSettings.load(db)).id
        }) else { return }
        currentItemId = itemId
        selectedSetId = newId
    }

    func deleteSet(_ setId: String) async {
        await change { try WorkoutWrites.deleteSet($0, setId: setId) }
        if selectedSetId == setId { selectFirstPlanned(preferring: currentItemId) }
    }

    // MARK: Exercises

    func addExercise(_ exerciseId: String) async {
        guard let id = snapshot?.workout.id else { return }
        guard let newId = await change({ db in
            try WorkoutWrites.addExercise(db, workoutId: id, exerciseId: exerciseId, settings: try AppSettings.load(db)).id
        }) else { return }
        select(itemId: newId)
    }

    func swap(_ itemId: String, to exerciseId: String, alsoInProgram: Bool) async {
        await change { db in
            try WorkoutWrites.swapExercise(db, workoutExerciseId: itemId, to: exerciseId, alsoInProgram: alsoInProgram,
                                           settings: try AppSettings.load(db))
        }
        if currentItemId == itemId { select(itemId: itemId) }
    }

    func removeExercise(_ itemId: String) async {
        await change { try WorkoutWrites.removeExercise($0, workoutExerciseId: itemId) }
        if currentItemId == itemId { selectFirstPlanned() }
    }

    func moveExercise(from: Int, to: Int) async {
        guard let id = snapshot?.workout.id else { return }
        await change { try WorkoutWrites.moveExercise($0, workoutId: id, from: from, to: to) }
    }

    // MARK: Rest and notes

    func adjustRest(by seconds: Double) async {
        guard let id = snapshot?.workout.id else { return }
        await change { try WorkoutWrites.adjustRest($0, workoutId: id, by: seconds, now: .now) }
    }

    func skipRest() async {
        guard let id = snapshot?.workout.id else { return }
        await change { try WorkoutWrites.clearRest($0, workoutId: id) }
    }

    /// The countdown reached zero with the app open; the notification has already sounded.
    func restDidEnd() async {
        guard let id = snapshot?.workout.id, let end = snapshot?.workout.restEndsAt, end <= .now else { return }
        await change { try WorkoutWrites.clearRest($0, workoutId: id) }
    }

    func setNote(_ note: String?, effort: Int?) async {
        guard let id = snapshot?.workout.id else { return }
        await change { try WorkoutWrites.setNoteAndEffort($0, workoutId: id, note: note, effort: effort) }
    }

    // MARK: Selection

    /// Tapping a card: open it on its first planned set, or its last set when all are logged.
    func select(itemId: String?) {
        currentItemId = itemId
        let item = snapshot?.items.first { $0.id == itemId }
        selectedSetId = item?.plannedSets.first?.id ?? item?.sets.last?.id
    }

    func select(setId: String) {
        currentItemId = snapshot?.items.first { $0.sets.contains { $0.id == setId } }?.id
        selectedSetId = setId
    }

    private func selectFirstPlanned(preferring itemId: String? = nil) {
        guard let items = snapshot?.items else { return }
        let item = items.first { $0.id == itemId && !$0.plannedSets.isEmpty } ?? items.first { !$0.plannedSets.isEmpty }
        if let item {
            currentItemId = item.id
            selectedSetId = item.plannedSets.first?.id
        } else {
            currentItemId = items.last?.id
            selectedSetId = nil
        }
    }

    /// After a log: the next planned set of the same item, else the next item with planned
    /// sets (wrapping round), else nothing left to do.
    private func advance(from itemId: String?) {
        guard let items = snapshot?.items, let index = items.firstIndex(where: { $0.id == itemId }) else {
            selectFirstPlanned()
            return
        }
        if let next = items[index].plannedSets.first {
            currentItemId = items[index].id
            selectedSetId = next.id
            return
        }
        for offset in 1..<max(items.count, 1) {
            let item = items[(index + offset) % items.count]
            if let next = item.plannedSets.first {
                currentItemId = item.id
                selectedSetId = next.id
                return
            }
        }
        selectedSetId = nil
    }

    // MARK: Writes

    /// Runs a write, reloads and syncs the alert. Returns nil when the write failed.
    @discardableResult
    private func change<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async -> T? {
        guard let id = snapshot?.workout.id else { return nil }
        let result = await write(body)
        await reload(workoutId: id)
        return result
    }

    private func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async -> T? {
        do {
            return try await db.writer.write(body)
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    private func reload(workoutId: String) async {
        do {
            snapshot = try await db.reader.read { db in
                try WorkoutQueries.snapshot(db, workoutId: workoutId, settings: try AppSettings.load(db))
            }
        } catch {
            snapshot = nil
        }
        syncNotification()
        await syncRestActivity()
    }

    private func endRestActivity() async {
        activityEndTask?.cancel()
        activityEndTask = nil
        restActivity = nil
        for activity in Activity<RestActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func syncRestActivity() async {
        guard let snapshot, let end = snapshot.workout.restEndsAt, end > .now else {
            await endRestActivity()
            return
        }
        let items = snapshot.items
        let start = items.firstIndex { $0.id == currentItemId } ?? 0
        let next = (0..<items.count).map { items[(start + $0) % items.count] }
            .first { !$0.plannedSets.isEmpty }
        let state = RestActivityAttributes.ContentState(
            exerciseName: next?.exercise.name ?? "All sets logged",
            restEndsAt: end,
            nextSetText: Self.notificationBody(snapshot, from: currentItemId))
        let content = ActivityContent(state: state, staleDate: end)
        if restActivity == nil {
            restActivity = Activity<RestActivityAttributes>.activities.first {
                $0.attributes.workoutTitle == snapshot.workout.title && $0.activityState == .active
            }
        }
        if let activity = restActivity {
            await activity.update(content)
        } else {
            do {
                restActivity = try Activity.request(
                    attributes: RestActivityAttributes(workoutTitle: snapshot.workout.title),
                    content: content, pushType: nil)
            } catch {
                Self.activityLog.error("Rest activity request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        activityEndTask?.cancel()
        activityEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self,
                  self.snapshot?.workout.restEndsAt == end else { return }
            await self.restDidEnd()
        }
    }

    private func syncNotification() {
        guard let snapshot, let end = snapshot.workout.restEndsAt else {
            notifier.cancel()
            return
        }
        notifier.schedule(at: end, body: Self.notificationBody(snapshot, from: currentItemId))
    }

    /// "Next: Barbell Bench Press, set 2 — 50 kg × 10", searching from `itemId` onward and
    /// wrapping round.
    static func notificationBody(_ snapshot: WorkoutSnapshot, from itemId: String?) -> String {
        let items = snapshot.items
        guard !items.isEmpty else { return "Time for your next set." }
        let start = items.firstIndex { $0.id == itemId } ?? 0
        for offset in 0..<items.count {
            let item = items[(start + offset) % items.count]
            if let set = item.plannedSets.first {
                return "Next: \(item.exercise.name), set \(set.position + 1) — \(SetFormat.long(set, loadMode: item.exercise.loadMode))"
            }
        }
        return "All sets logged. Finish when you're ready."
    }

    static func message(for error: Error) -> String {
        switch error as? WorkoutError {
        case .alreadyInProgress: "Finish or discard the workout in progress first."
        case .swapAfterLogging: "Sets are already logged for this exercise. Add the new one instead."
        case .invalidReps: "Reps can't be negative."
        case .notFound: "That workout is no longer there."
        case nil: error.localizedDescription
        }
    }
}
