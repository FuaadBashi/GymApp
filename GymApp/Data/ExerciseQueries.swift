import Foundation
import GRDB

nonisolated struct ExerciseFilter: Equatable {
    var searchText = ""
    var regions: Set<BodyRegion> = []      // empty = any
    var muscles: Set<Muscle> = []          // match primary or secondary
    var equipment: Set<Equipment> = []
    var force: Force? = nil
    var onlyDoneBefore = false
    var onlyFavorites = false
    var includeNonStrength = false         // stretching, plyometrics, cardio
    var focus: DayFocus? = nil             // card 1.8: a day's focus rule
    var movementPattern: MovementPattern? = nil  // card 2.7: swap within the same movement

    var isEmpty: Bool { self == ExerciseFilter() }
}

nonisolated struct ExerciseListItem: Identifiable, Equatable {
    var exercise: ExerciseRecord
    var lastDoneAt: Date?
    var sessionCount: Int
    var lastSets: [WorkoutSetRecord]       // completed sets of the latest session, in order
    var id: String { exercise.id }
}

nonisolated struct ExerciseSession: Identifiable, Equatable {
    var workout: WorkoutRecord
    var workoutExercise: WorkoutExerciseRecord
    var sets: [WorkoutSetRecord]           // completed only, in position order
    var id: String { workoutExercise.id }
}

/// "History" everywhere below means finished workouts (endedAt set) and completed sets.
nonisolated enum ExerciseQueries {
    static let strengthCategories: Set<ExerciseCategory> = [.strength, .powerlifting, .olympicWeightlifting, .strongman]

    static func browse(_ db: Database, filter: ExerciseFilter) throws -> [ExerciseListItem] {
        // The user's version of an exercise replaces its library duplicate (decision #28).
        let replaced = Set(try String.fetchAll(db, sql: """
            SELECT libraryId FROM exercise
            WHERE source != 'library' AND isArchived = 0 AND libraryId IS NOT NULL
            """))
        var stats: [String: (last: Date, count: Int)] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT we.exerciseId AS id, MAX(w.startedAt) AS last, COUNT(DISTINCT w.id) AS n
            FROM workoutExercise we JOIN workout w ON w.id = we.workoutId
            WHERE w.endedAt IS NOT NULL
              AND EXISTS (SELECT 1 FROM workoutSet s WHERE s.workoutExerciseId = we.id AND s.completedAt IS NOT NULL)
            GROUP BY we.exerciseId
            """) {
            stats[row["id"]] = (row["last"], row["n"])
        }

        let terms = filter.searchText.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let candidates = try ExerciseRecord.filter(Column("isArchived") == false).fetchAll(db).filter { e in
            if replaced.contains(e.id) { return false }
            if !filter.includeNonStrength, !strengthCategories.contains(e.category) { return false }
            let name = e.name.lowercased()
            if !terms.allSatisfy({ name.contains($0) }) { return false }
            if !filter.regions.isEmpty, !filter.regions.contains(e.bodyRegion) { return false }
            if !filter.muscles.isEmpty, filter.muscles.isDisjoint(with: e.primaryMuscles + e.secondaryMuscles) { return false }
            if !filter.equipment.isEmpty, !filter.equipment.contains(e.equipment) { return false }
            if let force = filter.force, e.force != force { return false }
            if filter.onlyDoneBefore, stats[e.id] == nil { return false }
            if filter.onlyFavorites, !e.isFavorite { return false }
            if let focus = filter.focus, !matches(e, focus: focus) { return false }
            if let pattern = filter.movementPattern, e.movementPattern != pattern { return false }
            return true
        }

        let ordered = candidates.sorted { a, b in
            switch (stats[a.id]?.last, stats[b.id]?.last) {
            case let (x?, y?): return x != y ? x > y : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }

        let lastSets = try latestSets(db, exerciseIds: Set(ordered.lazy.filter { stats[$0.id] != nil }.map(\.id)))
        return ordered.map {
            ExerciseListItem(exercise: $0, lastDoneAt: stats[$0.id]?.last, sessionCount: stats[$0.id]?.count ?? 0,
                             lastSets: lastSets[$0.id] ?? [])
        }
    }

    /// Card 1.8: the rule that narrows a day's picker to its focus. Full body and custom
    /// days have none.
    static func matches(_ e: ExerciseRecord, focus: DayFocus) -> Bool {
        switch focus {
        case .upper: e.bodyRegion == .upper
        case .lower, .legs: e.bodyRegion == .lower
        case .push: e.bodyRegion == .upper && e.force == .push
        case .pull: e.bodyRegion == .upper && e.force == .pull
        case .fullBody, .custom: true
        }
    }

    /// The completed sets of each exercise's latest finished session, in three queries
    /// whatever the number of exercises.
    private static func latestSets(_ db: Database, exerciseIds: Set<String>) throws -> [String: [WorkoutSetRecord]] {
        guard !exerciseIds.isEmpty else { return [:] }
        var latest: [String: String] = [:]  // exerciseId → workoutExerciseId
        for row in try Row.fetchAll(db, sql: """
            SELECT we.exerciseId AS exerciseId, we.id AS id FROM workoutExercise we
            JOIN workout w ON w.id = we.workoutId
            WHERE w.endedAt IS NOT NULL
              AND EXISTS (SELECT 1 FROM workoutSet s WHERE s.workoutExerciseId = we.id AND s.completedAt IS NOT NULL)
            ORDER BY w.startedAt DESC, we.position
            """) {
            let exerciseId: String = row["exerciseId"]
            if exerciseIds.contains(exerciseId), latest[exerciseId] == nil { latest[exerciseId] = row["id"] }
        }
        let sets = try WorkoutSetRecord
            .filter(latest.values.contains(Column("workoutExerciseId")) && Column("completedAt") != nil)
            .order(Column("position")).fetchAll(db)
        let byWorkoutExercise = Dictionary(grouping: sets, by: \.workoutExerciseId)
        return latest.mapValues { byWorkoutExercise[$0] ?? [] }
    }

    /// Every finished session of an exercise, newest first.
    static func sessions(_ db: Database, exerciseId: String) throws -> [ExerciseSession] {
        let workoutExercises = try WorkoutExerciseRecord.fetchAll(db, sql: """
            SELECT we.* FROM workoutExercise we JOIN workout w ON w.id = we.workoutId
            WHERE we.exerciseId = ? AND w.endedAt IS NOT NULL
            ORDER BY w.startedAt DESC, we.position
            """, arguments: [exerciseId])
        let workouts = Dictionary(uniqueKeysWithValues: try WorkoutRecord
            .filter(keys: Set(workoutExercises.map(\.workoutId))).fetchAll(db).map { ($0.id, $0) })
        let sets = Dictionary(grouping: try WorkoutSetRecord
            .filter(workoutExercises.map(\.id).contains(Column("workoutExerciseId")) && Column("completedAt") != nil)
            .order(Column("position")).fetchAll(db), by: \.workoutExerciseId)
        return workoutExercises.compactMap { we in
            guard let workout = workouts[we.workoutId], let done = sets[we.id], !done.isEmpty else { return nil }
            return ExerciseSession(workout: workout, workoutExercise: we, sets: done)
        }
    }

    /// Rulebook §7: the newest session on one of `dayIds` (a day and the days it was copied
    /// from), otherwise the newest anywhere.
    static func lastSession(_ db: Database, exerciseId: String, preferringDays dayIds: Set<String>,
                            before: Date? = nil) throws -> (session: ExerciseSession, isSameDay: Bool)? {
        var all = try sessions(db, exerciseId: exerciseId)
        if let before { all = all.filter { $0.workout.startedAt < before } }
        if let same = all.first(where: { $0.workout.programDayId.map(dayIds.contains) ?? false }) { return (same, true) }
        return all.first.map { ($0, false) }
    }

    static func notes(_ db: Database, exerciseId: String) throws -> [ExerciseNoteRecord] {
        try ExerciseNoteRecord.filter(Column("exerciseId") == exerciseId)
            .order(Column("date").desc, Column("id").desc).fetchAll(db)
    }
}
