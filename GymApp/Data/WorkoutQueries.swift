import Foundation
import GRDB

nonisolated struct WorkoutSnapshot: Equatable {
    var workout: WorkoutRecord
    var items: [Item]

    nonisolated struct Item: Identifiable, Equatable {
        var workoutExercise: WorkoutExerciseRecord
        var exercise: ExerciseRecord
        var sets: [WorkoutSetRecord]       // position order, completed and planned
        var previous: ExerciseSession?     // rulebook §7, finished sessions only
        var previousIsSameDay: Bool
        var studioTarget: StudioDecisionRecord? = nil   // card 6.3, an accepted target
        var id: String { workoutExercise.id }
        var plannedSets: [WorkoutSetRecord] { sets.filter { $0.completedAt == nil } }
    }

    var completedSetCount: Int
    var totalSetCount: Int
    var bests: [String: TrainingMath.BestStatus] = [:]   // card 7.2: set id → status
    var hints: [String: BestHint] = [:]                   // card 7.3: exercise id → marks
    var defaultRepRange: ClosedRange<Int> = 8...12

    /// Card 7.3: what a set is measured against, including sets logged in this workout.
    nonisolated struct BestHint: Equatable {
        var allTime: Double?
        var windowMonths: Int?
        var windowBest: Double?
        var step: Double
        var allTimeSet: WorkoutSetRecord? = nil   // the set that made each best, for "70 × 12"
        var windowSet: WorkoutSetRecord? = nil
        var next: NextSet.Suggestion? = nil          // rulebook §13
    }
}

nonisolated enum WorkoutQueries {
    static func inProgress(_ db: Database) throws -> WorkoutRecord? {
        try WorkoutRecord.filter(Column("endedAt") == nil).fetchOne(db)
    }

    static func snapshot(_ db: Database, workoutId: String, settings: AppSettings) throws -> WorkoutSnapshot {
        guard let workout = try WorkoutRecord.fetchOne(db, key: workoutId) else { throw WorkoutError.notFound }
        let workoutExercises = try WorkoutExerciseRecord.filter(Column("workoutId") == workoutId)
            .order(Column("position")).fetchAll(db)
        let exercises = Dictionary(uniqueKeysWithValues: try ExerciseRecord
            .filter(keys: Set(workoutExercises.map(\.exerciseId))).fetchAll(db).map { ($0.id, $0) })
        let sets = Dictionary(grouping: try WorkoutSetRecord
            .filter(workoutExercises.map(\.id).contains(Column("workoutExerciseId")))
            .order(Column("position")).fetchAll(db), by: \.workoutExerciseId)
        let days = try preferredDays(db, workout: workout, settings: settings)

        let items = try workoutExercises.compactMap { we -> WorkoutSnapshot.Item? in
            guard let exercise = exercises[we.exerciseId] else { return nil }
            let last = try ExerciseQueries.lastSession(db, exerciseId: exercise.id, preferringDays: days, before: workout.startedAt)
            return WorkoutSnapshot.Item(workoutExercise: we, exercise: exercise, sets: sets[we.id] ?? [],
                                        previous: last?.session, previousIsSameDay: last?.isSameDay ?? false,
                                        studioTarget: try StudioSuggestions.activeTarget(db, exerciseId: exercise.id))
        }
        let all = items.flatMap(\.sets)
        var hints: [String: WorkoutSnapshot.BestHint] = [:]
        let range = settings.defaultRepMin...max(settings.defaultRepMin, settings.defaultRepMax)
        return WorkoutSnapshot(workout: workout, items: items,
                               completedSetCount: all.filter { $0.completedAt != nil }.count, totalSetCount: all.count,
                               bests: try bests(db, items: items, hints: &hints, defaultRange: range, startedAt: workout.startedAt),
                               hints: hints,
                               defaultRepRange: range)
    }

    /// Card 7.2 (rulebook §5a): the best status of every logged set in the workout, each judged
    /// against the exercise's finished history and the sets logged before it in this workout.
    static func bests(_ db: Database, items: [WorkoutSnapshot.Item],
                      hints: inout [String: WorkoutSnapshot.BestHint], defaultRange: ClosedRange<Int> = 8...12,
                      startedAt: Date? = nil, now: Date = .now) throws -> [String: TrainingMath.BestStatus] {
        var out: [String: TrainingMath.BestStatus] = [:]
        for exerciseId in Set(items.map(\.exercise.id)) {
            let mine = items.filter { $0.exercise.id == exerciseId }
            guard let loadMode = mine.first?.exercise.loadMode, loadMode != .bodyweightPlus, loadMode != .repsOnly else { continue }
            let sessions = try ExerciseQueries.sessions(db, exerciseId: exerciseId)
            let loads = sessions.flatMap(\.sets).compactMap { set in set.loadHundredths.map { Load(hundredths: $0, unit: set.unit).kg } }
            let logged = mine.flatMap(\.sets).filter { $0.completedAt != nil }
            let run = ExerciseStats.statuses(logged, history: ExerciseStats.e1RMHistory(sessions, loadMode: loadMode),
                                             loadMode: loadMode, fallbackDate: now)
            out.merge(run.bests) { a, _ in a }
            let history = run.history
            let window = TrainingMath.eligibleWindows(history: history, at: now).first
            let allTime = history.map(\.e1RM).max()
            let candidates = sessions.flatMap { s in s.sets.map { ($0.completedAt ?? s.workout.startedAt, $0) } }
                + logged.map { ($0.completedAt ?? now, $0) }
            func setMaking(_ best: Double?, since: Date) -> WorkoutSetRecord? {
                guard let best else { return nil }
                return candidates.last { date, set in
                    guard date >= since, set.type != .warmUp, set.type != .drop, let load = set.loadHundredths,
                          let e = TrainingMath.displayableE1RM(kg: Load(hundredths: load, unit: set.unit).kg, reps: set.reps, loadMode: loadMode)
                    else { return false }
                    return abs(e - best) <= 0.01
                }?.1
            }
            let windowDays = TrainingMath.bestWindows.first { $0.months == window?.months }?.days ?? 0
            hints[exerciseId] = .init(allTime: allTime, windowMonths: window?.months,
                                      windowBest: window?.best, step: TrainingMath.step(loads: loads),
                                      allTimeSet: setMaking(allTime, since: .distantPast),
                                      windowSet: setMaking(window?.best, since: now.addingTimeInterval(-Double(windowDays) * 86_400)),
                                      next: NextSet.suggest(sessions: sessions, repRange: repRange(mine.first?.workoutExercise, defaultRange),
                                                            stepKg: TrainingMath.step(loads: loads), loadMode: loadMode, now: startedAt ?? now))
        }
        return out
    }

    static func repRange(_ we: WorkoutExerciseRecord?, _ fallback: ClosedRange<Int>) -> ClosedRange<Int> {
        guard let lo = we?.repMin, let hi = we?.repMax, lo >= 1, hi >= lo else { return fallback }
        return lo...hi
    }

    /// The workout's day and the days it was copied from, when last time should prefer them.
    static func preferredDays(_ db: Database, workout: WorkoutRecord, settings: AppSettings) throws -> Set<String> {
        guard settings.lastTimeSource == .sameDay, let dayId = workout.programDayId else { return [] }
        return Set(try ProgramQueries.lineage(db, dayId: dayId))
    }
}
