import Foundation
import GRDB

nonisolated struct SetEdit: Equatable, Codable, Sendable {
    var loadHundredths: Int?
    var unit: WeightUnit
    var reps: Int
    var type: SetType
}

nonisolated enum WorkoutError: Error, Equatable {
    case alreadyInProgress, notFound, swapAfterLogging, invalidReps, emptyTitle, lastSet
}

/// Every workout operation as a database write (docs/specs/02-workout-screen.md, card 2.1).
nonisolated enum WorkoutWrites {
    @discardableResult
    static func start(_ db: Database, dayId: String?, settings: AppSettings, now: Date) throws -> WorkoutRecord {
        guard try WorkoutQueries.inProgress(db) == nil else { throw WorkoutError.alreadyInProgress }
        let day = try dayId.flatMap { try ProgramDayRecord.fetchOne(db, key: $0) }
        let workout = WorkoutRecord(id: UUID().uuidString, startedAt: now, endedAt: nil, programDayId: day?.id,
                                    title: day?.name ?? "Workout", note: nil, effort: nil, restEndsAt: nil,
                                    restDurationSeconds: nil, source: .app, externalId: nil)
        try workout.insert(db)
        guard let day else { return workout }
        let items = try DayExerciseRecord.filter(Column("dayId") == day.id).order(Column("position")).fetchAll(db)
        for (position, item) in items.enumerated() {
            let we = WorkoutExerciseRecord(id: UUID().uuidString, workoutId: workout.id, exerciseId: item.exerciseId,
                                           position: position, dayExerciseId: item.id, targetSets: item.targetSets,
                                           repMin: item.repMin, repMax: item.repMax, restSeconds: item.restSeconds,
                                           note: nil, externalId: nil)
            try we.insert(db)
            try prefill(db, workout: workout, workoutExercise: we, settings: settings)
        }
        return workout
    }

    static func logSet(_ db: Database, setId: String, now: Date) throws {
        guard var set = try WorkoutSetRecord.fetchOne(db, key: setId),
              let we = try WorkoutExerciseRecord.fetchOne(db, key: set.workoutExerciseId) else { throw WorkoutError.notFound }
        set.completedAt = now
        try set.update(db)
        if we.restSeconds > 0 {
            try db.execute(sql: "UPDATE workout SET restEndsAt = ?, restDurationSeconds = ? WHERE id = ?",
                           arguments: [now.addingTimeInterval(TimeInterval(we.restSeconds)), Double(we.restSeconds), we.workoutId])
        }
    }

    static func unlogSet(_ db: Database, setId: String) throws {
        try db.execute(sql: "UPDATE workoutSet SET completedAt = NULL WHERE id = ?", arguments: [setId])
    }

    static func updateSet(_ db: Database, setId: String, edit: SetEdit) throws {
        guard edit.reps >= 0 else { throw WorkoutError.invalidReps }
        guard var set = try WorkoutSetRecord.fetchOne(db, key: setId) else { throw WorkoutError.notFound }
        set.loadHundredths = edit.loadHundredths
        set.unit = edit.unit
        set.reps = edit.reps
        set.type = edit.type
        try set.update(db)
    }

    @discardableResult
    static func addSet(_ db: Database, workoutExerciseId: String, settings: AppSettings) throws -> WorkoutSetRecord {
        guard let we = try WorkoutExerciseRecord.fetchOne(db, key: workoutExerciseId),
              let exercise = try ExerciseRecord.fetchOne(db, key: we.exerciseId) else { throw WorkoutError.notFound }
        let sets = try WorkoutSetRecord.filter(Column("workoutExerciseId") == we.id).order(Column("position")).fetchAll(db)
        var set = sets.last.map { last in
            WorkoutSetRecord(id: "", workoutExerciseId: we.id, position: 0, loadHundredths: last.loadHundredths,
                             unit: last.unit, reps: last.reps, type: .working, completedAt: nil, rpe: nil, externalId: nil)
        } ?? defaultSet(we, exercise: exercise, settings: settings)
        set.id = UUID().uuidString
        set.position = sets.count
        try set.insert(db)
        return set
    }

    static func deleteSet(_ db: Database, setId: String) throws {
        guard let set = try WorkoutSetRecord.fetchOne(db, key: setId) else { return }
        try set.delete(db)
        try renumberSets(db, workoutExerciseId: set.workoutExerciseId)
    }

    @discardableResult
    static func addExercise(_ db: Database, workoutId: String, exerciseId: String, settings: AppSettings) throws -> WorkoutExerciseRecord {
        guard let workout = try WorkoutRecord.fetchOne(db, key: workoutId),
              let exercise = try ExerciseRecord.fetchOne(db, key: exerciseId) else { throw WorkoutError.notFound }
        let position = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workoutExercise WHERE workoutId = ?", arguments: [workoutId]) ?? 0
        let we = WorkoutExerciseRecord(id: UUID().uuidString, workoutId: workoutId, exerciseId: exerciseId, position: position,
                                       dayExerciseId: nil, targetSets: nil, repMin: nil, repMax: nil,
                                       restSeconds: exercise.defaultRestSeconds, note: nil, externalId: nil)
        try we.insert(db)
        try prefill(db, workout: workout, workoutExercise: we, settings: settings)
        return we
    }

    static func swapExercise(_ db: Database, workoutExerciseId: String, to exerciseId: String,
                             alsoInProgram: Bool, settings: AppSettings) throws {
        guard var we = try WorkoutExerciseRecord.fetchOne(db, key: workoutExerciseId),
              let workout = try WorkoutRecord.fetchOne(db, key: we.workoutId) else { throw WorkoutError.notFound }
        let logged = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workoutSet WHERE workoutExerciseId = ? AND completedAt IS NOT NULL",
                                      arguments: [we.id]) ?? 0
        guard logged == 0 else { throw WorkoutError.swapAfterLogging }
        try db.execute(sql: "DELETE FROM workoutSet WHERE workoutExerciseId = ?", arguments: [we.id])
        we.exerciseId = exerciseId
        try we.update(db)
        try prefill(db, workout: workout, workoutExercise: we, settings: settings)
        if alsoInProgram, let dayExerciseId = we.dayExerciseId {
            try db.execute(sql: "UPDATE dayExercise SET exerciseId = ? WHERE id = ?", arguments: [exerciseId, dayExerciseId])
        }
    }

    static func removeExercise(_ db: Database, workoutExerciseId: String) throws {
        guard let we = try WorkoutExerciseRecord.fetchOne(db, key: workoutExerciseId) else { return }
        try we.delete(db)
        try renumberExercises(db, workoutId: we.workoutId)
    }

    static func moveExercise(_ db: Database, workoutId: String, from: Int, to: Int) throws {
        var items = try WorkoutExerciseRecord.filter(Column("workoutId") == workoutId).order(Column("position")).fetchAll(db)
        guard items.indices.contains(from) else { return }
        items.insert(items.remove(at: from), at: min(max(to, 0), items.count))
        for (i, var item) in items.enumerated() where item.position != i {
            item.position = i
            try item.update(db)
        }
    }

    static func adjustRest(_ db: Database, workoutId: String, by seconds: Double, now: Date) throws {
        guard var workout = try WorkoutRecord.fetchOne(db, key: workoutId), let end = workout.restEndsAt else { return }
        let newEnd = end.addingTimeInterval(seconds)
        if newEnd <= now {
            workout.restEndsAt = nil
            workout.restDurationSeconds = nil
        } else {
            workout.restEndsAt = newEnd
            workout.restDurationSeconds = (workout.restDurationSeconds ?? 0) + seconds
        }
        try workout.update(db)
    }

    static func clearRest(_ db: Database, workoutId: String) throws {
        try db.execute(sql: "UPDATE workout SET restEndsAt = NULL, restDurationSeconds = NULL WHERE id = ?", arguments: [workoutId])
    }

    /// Keeps only completed sets. A workout with nothing logged is discarded (rulebook §10).
    @discardableResult
    static func finish(_ db: Database, workoutId: String, now: Date) throws -> WorkoutRecord? {
        guard var workout = try WorkoutRecord.fetchOne(db, key: workoutId) else { throw WorkoutError.notFound }
        try db.execute(sql: """
            DELETE FROM workoutSet WHERE completedAt IS NULL
              AND workoutExerciseId IN (SELECT id FROM workoutExercise WHERE workoutId = ?)
            """, arguments: [workoutId])
        try db.execute(sql: """
            DELETE FROM workoutExercise WHERE workoutId = ?
              AND NOT EXISTS (SELECT 1 FROM workoutSet s WHERE s.workoutExerciseId = workoutExercise.id)
            """, arguments: [workoutId])
        try renumberExercises(db, workoutId: workoutId)
        let remaining = try WorkoutExerciseRecord.filter(Column("workoutId") == workoutId).fetchAll(db)
        guard !remaining.isEmpty else {
            try workout.delete(db)
            return nil
        }
        for we in remaining { try renumberSets(db, workoutExerciseId: we.id) }
        workout.endedAt = max(now, workout.startedAt)
        workout.restEndsAt = nil
        workout.restDurationSeconds = nil
        try workout.update(db)
        return workout
    }

    static func discard(_ db: Database, workoutId: String) throws {
        _ = try WorkoutRecord.deleteOne(db, key: workoutId)
    }

    static func setNoteAndEffort(_ db: Database, workoutId: String, note: String?, effort: Int?) throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.execute(sql: "UPDATE workout SET note = ?, effort = ? WHERE id = ?",
                       arguments: [trimmed?.isEmpty == false ? trimmed : nil, effort, workoutId])
    }

    static func setMetadata(_ db: Database, setId: String, note: String?, reserve: Int?, annotations: [SetAnnotation]) throws {
        guard var set = try WorkoutSetRecord.fetchOne(db, key: setId) else { throw WorkoutError.notFound }
        set.note = note?.isEmpty == false ? note : nil
        set.repsInReserve = reserve
        set.annotations = SetAnnotation.allCases.filter { annotations.contains($0) }
        try set.update(db)
    }

    /// Reps left in the tank (0–3) for one set, leaving its note and labels as they are.
    static func setReserve(_ db: Database, setId: String, reserve: Int?) throws {
        guard reserve.map({ (0...3).contains($0) }) ?? true else { throw WorkoutError.invalidReps }
        guard try WorkoutSetRecord.fetchOne(db, key: setId) != nil else { throw WorkoutError.notFound }
        try db.execute(sql: "UPDATE workoutSet SET repsInReserve = ? WHERE id = ?", arguments: [reserve, setId])
    }

    static func setExerciseNote(_ db: Database, itemId: String, note: String?) throws {
        guard var item = try WorkoutExerciseRecord.fetchOne(db, key: itemId) else { throw WorkoutError.notFound }
        item.note = note?.isEmpty == false ? note : nil
        try item.update(db)
    }

    // MARK: Finished workouts (card 3.3). Each keeps endedAt, so the workout stays history.

    static func rename(_ db: Database, workoutId: String, title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkoutError.emptyTitle }
        try db.execute(sql: "UPDATE workout SET title = ? WHERE id = ?", arguments: [trimmed, workoutId])
    }

    /// Adds a completed copy of the last set, logged at the workout's end.
    @discardableResult
    static func addLoggedSet(_ db: Database, workoutExerciseId: String, settings: AppSettings) throws -> WorkoutSetRecord {
        guard let we = try WorkoutExerciseRecord.fetchOne(db, key: workoutExerciseId),
              let workout = try WorkoutRecord.fetchOne(db, key: we.workoutId) else { throw WorkoutError.notFound }
        var set = try addSet(db, workoutExerciseId: workoutExerciseId, settings: settings)
        set.completedAt = workout.endedAt ?? workout.startedAt
        try set.update(db)
        return set
    }

    /// Deleting the last set of an exercise removes the exercise; the last set of the whole
    /// workout is refused, so a workout is only ever deleted on purpose (rulebook §10).
    static func deleteLoggedSet(_ db: Database, setId: String) throws {
        guard let set = try WorkoutSetRecord.fetchOne(db, key: setId),
              let we = try WorkoutExerciseRecord.fetchOne(db, key: set.workoutExerciseId) else { throw WorkoutError.notFound }
        let total = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM workoutSet s JOIN workoutExercise we ON we.id = s.workoutExerciseId WHERE we.workoutId = ?
            """, arguments: [we.workoutId]) ?? 0
        guard total > 1 else { throw WorkoutError.lastSet }
        try set.delete(db)
        let left = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workoutSet WHERE workoutExerciseId = ?", arguments: [we.id]) ?? 0
        if left == 0 {
            try we.delete(db)
            try renumberExercises(db, workoutId: we.workoutId)
        } else {
            try renumberSets(db, workoutExerciseId: we.id)
        }
    }

    static func deleteFinished(_ db: Database, workoutId: String) throws {
        guard try WorkoutRecord.deleteOne(db, key: workoutId) else { throw WorkoutError.notFound }
    }

    // MARK: Prefill

    /// Copy last time, pad up to the target, keep extras (spec card 2.1).
    private static func prefill(_ db: Database, workout: WorkoutRecord, workoutExercise we: WorkoutExerciseRecord,
                                settings: AppSettings) throws {
        guard let exercise = try ExerciseRecord.fetchOne(db, key: we.exerciseId) else { throw WorkoutError.notFound }
        let days = try WorkoutQueries.preferredDays(db, workout: workout, settings: settings)
        let previous = try ExerciseQueries.lastSession(db, exerciseId: exercise.id, preferringDays: days, before: workout.startedAt)
        var rows = (previous?.session.sets ?? []).map {
            WorkoutSetRecord(id: "", workoutExerciseId: we.id, position: 0, loadHundredths: $0.loadHundredths,
                             unit: $0.unit, reps: $0.reps, type: $0.type, completedAt: nil, rpe: nil, externalId: nil)
        }
        let target = we.targetSets ?? settings.defaultSets
        if rows.isEmpty {
            rows = Array(repeating: defaultSet(we, exercise: exercise, settings: settings), count: target)
        } else {
            while rows.count < target {
                var copy = rows[rows.count - 1]
                copy.type = .working
                rows.append(copy)
            }
        }
        for (position, var row) in rows.enumerated() {
            row.id = UUID().uuidString
            row.position = position
            try row.insert(db)
        }
    }

    private static func defaultSet(_ we: WorkoutExerciseRecord, exercise: ExerciseRecord, settings: AppSettings) -> WorkoutSetRecord {
        WorkoutSetRecord(id: "", workoutExerciseId: we.id, position: 0,
                         loadHundredths: exercise.loadMode == .repsOnly ? nil : 0, unit: exercise.preferredUnit,
                         reps: we.repMin ?? settings.defaultRepMin, type: .working, completedAt: nil, rpe: nil, externalId: nil)
    }

    private static func renumberSets(_ db: Database, workoutExerciseId: String) throws {
        let sets = try WorkoutSetRecord.filter(Column("workoutExerciseId") == workoutExerciseId).order(Column("position")).fetchAll(db)
        for (i, var set) in sets.enumerated() where set.position != i { set.position = i; try set.update(db) }
    }

    private static func renumberExercises(_ db: Database, workoutId: String) throws {
        let items = try WorkoutExerciseRecord.filter(Column("workoutId") == workoutId).order(Column("position")).fetchAll(db)
        for (i, var item) in items.enumerated() where item.position != i { item.position = i; try item.update(db) }
    }
}
