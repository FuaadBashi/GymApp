import Foundation
import Observation

/// Holds the routine (from the seed), the workout in progress and finished workouts.
/// Every change is written to disk immediately: iOS can kill a backgrounded app while
/// you are in Spotify between sets, and a logged set must survive that.
@Observable
final class WorkoutStore {
    private(set) var seed: Seed?
    private(set) var loadError: String?
    private(set) var completed: [WorkoutSession] = []

    var active: WorkoutSession? {
        didSet { save() }
    }

    /// The workout just finished, for the summary sheet.
    var justFinished: WorkoutSession?

    private let rest = RestNotifier()
    private let stateURL: URL

    init() {
        let support = URL.applicationSupportDirectory.appending(path: "GymApp", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        stateURL = support.appending(path: "state.json")

        do { seed = try Seed.loadBundled() } catch { loadError = error.localizedDescription }
        restore()
    }

    var days: [RoutineDay] { seed?.days ?? [] }
    var bodyWeightKg: Double? { seed?.bodyWeightKg }

    // MARK: History

    /// Seed history plus workouts finished in this app, oldest first.
    func history(for exerciseId: String) -> [HistoryEntry] {
        let imported = days.lazy.flatMap(\.exercises).first { $0.id == exerciseId }?.history ?? []
        let here = completed.compactMap { session -> HistoryEntry? in
            let sets = session.exercises
                .filter { $0.exerciseId == exerciseId }
                .flatMap(\.loggedSets)
                .map(\.asPastSet)
            return sets.isEmpty ? nil : HistoryEntry(date: session.startedAt, dayId: session.dayId, sets: sets)
        }
        return (imported + here).sorted { $0.date < $1.date }
    }

    /// Rulebook §7: same routine day first, any workout as the fallback.
    func lastTime(for exerciseId: String, dayId: String) -> (entry: HistoryEntry, sameDay: Bool)? {
        let all = history(for: exerciseId)
        if let same = all.last(where: { $0.dayId == dayId }) { return (same, true) }
        return all.last.map { ($0, false) }
    }

    func lastDone(_ day: RoutineDay) -> Date? {
        let imported = day.exercises.flatMap(\.history).filter { $0.dayId == day.id }.map(\.date)
        let here = completed.filter { $0.dayId == day.id }.map(\.startedAt)
        return (imported + here).max()
    }

    /// Decision #12, rolling rotation: whichever day was done least recently is next.
    var nextDay: RoutineDay? {
        days.min { (lastDone($0) ?? .distantPast) < (lastDone($1) ?? .distantPast) }
    }

    // MARK: Workout lifecycle

    func start(_ day: RoutineDay) {
        let exercises = day.exercises.map { plan -> ExerciseInWorkout in
            let last = lastTime(for: plan.id, dayId: day.id)
            var rows = (last?.entry.sets ?? []).map {
                SetEntry(load: Load($0.kg, .kg), reps: $0.reps, type: $0.type)
            }
            while rows.count < plan.targetSets {
                rows.append(rows.last.map { SetEntry(load: $0.load, reps: $0.reps) }
                            ?? SetEntry(load: Load(0, .kg), reps: 10))
            }
            return ExerciseInWorkout(
                exerciseId: plan.id, name: plan.name, equipment: plan.equipment,
                restSeconds: plan.restSeconds, note: plan.note?.text, noteDate: plan.note?.date,
                lastTime: last?.entry, lastTimeIsSameDay: last?.sameDay ?? false, sets: rows
            )
        }
        active = WorkoutSession(dayId: day.id, dayName: day.name, startedAt: .now, exercises: exercises)
        Task { await rest.requestPermission() }
    }

    /// Unlogged rows were only ever suggestions, so they are dropped. A workout with
    /// nothing logged is discarded silently (rulebook §10).
    func finish() {
        guard var session = active else { return }
        rest.cancel()
        for i in session.exercises.indices {
            session.exercises[i].sets.removeAll { !$0.isLogged }
        }
        session.exercises.removeAll { $0.sets.isEmpty }
        session.endedAt = .now
        session.restEndsAt = nil
        active = nil
        guard !session.exercises.isEmpty else { return }
        completed.append(session)
        save()
        justFinished = session
    }

    func discard() {
        rest.cancel()
        active = nil
    }

    // MARK: Editing the workout in progress

    func select(exercise index: Int) {
        active?.currentExercise = index
    }

    func select(set setIndex: Int, in exerciseIndex: Int) {
        active?.exercises[exerciseIndex].selected = setIndex
    }

    func stepLoad(_ direction: Double, exercise e: Int, set s: Int) {
        guard let ex = active?.exercises[e] else { return }
        active?.exercises[e].sets[s].load = ex.sets[s].load.adding(direction * ex.equipment.stepKg)
    }

    func setLoad(_ value: Double, exercise e: Int, set s: Int) {
        guard let unit = active?.exercises[e].sets[s].load.unit else { return }
        active?.exercises[e].sets[s].load = Load(value, unit)
    }

    func setReps(_ reps: Int, exercise e: Int, set s: Int) {
        active?.exercises[e].sets[s].reps = max(0, reps)
    }

    func setType(_ type: SetType, exercise e: Int, set s: Int) {
        active?.exercises[e].sets[s].type = type
    }

    func addSet(exercise e: Int) {
        guard let ex = active?.exercises[e] else { return }
        let template = ex.sets.last ?? SetEntry(load: Load(0, .kg), reps: 10)
        active?.exercises[e].sets.append(SetEntry(load: template.load, reps: template.reps))
        active?.exercises[e].selected = ex.sets.count
    }

    func deleteSet(exercise e: Int, set s: Int) {
        guard let ex = active?.exercises[e], ex.sets.indices.contains(s) else { return }
        active?.exercises[e].sets.remove(at: s)
        active?.exercises[e].selected = min(ex.selected, max(0, ex.sets.count - 2))
    }

    /// Ticking a logged row again un-logs it, for a mis-tap.
    func toggleLogged(exercise e: Int, set s: Int) {
        guard let entry = active?.exercises[e].sets[s] else { return }
        if entry.isLogged {
            active?.exercises[e].sets[s].loggedAt = nil
        } else {
            log(exercise: e, set: s)
        }
    }

    func logSelected(exercise e: Int) {
        guard let ex = active?.exercises[e] else { return }
        let s = ex.sets.indices.contains(ex.selected) && !ex.sets[ex.selected].isLogged
            ? ex.selected : (ex.nextUnlogged ?? ex.selected)
        log(exercise: e, set: s)
    }

    private func log(exercise e: Int, set s: Int) {
        guard active?.exercises[e].sets.indices.contains(s) == true else { return }
        active?.exercises[e].sets[s].loggedAt = .now
        if let next = active?.exercises[e].nextUnlogged { active?.exercises[e].selected = next }
        startRest(after: e)
    }

    func setRest(seconds: Int, exercise e: Int) {
        active?.exercises[e].restSeconds = seconds
    }

    // MARK: Rest

    private func startRest(after e: Int) {
        guard let seconds = active?.exercises[e].restSeconds, seconds > 0 else { return }
        active?.restDuration = TimeInterval(seconds)
        active?.restEndsAt = .now.addingTimeInterval(TimeInterval(seconds))
        scheduleRestAlert()
    }

    func adjustRest(by seconds: TimeInterval) {
        guard let ends = active?.restEndsAt else { return }
        let newEnd = ends.addingTimeInterval(seconds)
        guard newEnd > .now else { return skipRest() }
        active?.restEndsAt = newEnd
        active?.restDuration += seconds
        scheduleRestAlert()
    }

    func skipRest() {
        active?.restEndsAt = nil
        rest.cancel()
    }

    /// Called by the screen when the countdown reaches zero while the app is open.
    func restFinished() {
        active?.restEndsAt = nil
    }

    private func scheduleRestAlert() {
        guard let session = active, let ends = session.restEndsAt else { return }
        rest.schedule(at: ends, body: Self.nextUpText(session))
    }

    private static func nextUpText(_ session: WorkoutSession) -> String {
        let order = Array(session.exercises.indices[session.currentExercise...])
            + Array(session.exercises.indices[..<session.currentExercise])
        for e in order {
            let ex = session.exercises[e]
            if let s = ex.nextUnlogged {
                let set = ex.sets[s]
                return "Next: \(ex.name), set \(s + 1) — \(set.load.formatted) \(set.load.unit.rawValue) × \(set.reps)"
            }
        }
        return "All sets logged. Finish when ready."
    }

    // MARK: Persistence

    private struct State: Codable {
        var active: WorkoutSession?
        var completed: [WorkoutSession]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(State(active: active, completed: completed))
            try data.write(to: stateURL, options: .atomic)
        } catch {
            loadError = "Could not save: \(error.localizedDescription)"
        }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let state = try decoder.decode(State.self, from: data)
            completed = state.completed
            active = state.active
        } catch {
            // Never overwrite a file we failed to read: keep it for inspection.
            let aside = stateURL.deletingLastPathComponent().appending(path: "state-unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: stateURL, to: aside)
            loadError = "Saved workouts could not be read and were set aside: \(error.localizedDescription)"
        }
    }
}
