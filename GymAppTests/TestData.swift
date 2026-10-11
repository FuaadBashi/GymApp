import Foundation
import GRDB
@testable import GymApp

/// Builders that insert straight into a database, so data-layer tests stay short.
nonisolated enum TestData {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)  // late September 2026

    /// A date `day` days after `base`, so "3 Oct" style fixtures read as plain numbers.
    static func day(_ n: Int) -> Date { base.addingTimeInterval(TimeInterval(n) * 86_400) }

    @discardableResult
    static func exercise(_ db: Database, id: String, name: String? = nil, pattern: MovementPattern? = nil,
                         region: BodyRegion = .upper, force: Force? = nil, loadMode: LoadMode = .total,
                         archived: Bool = false, libraryId: String? = nil, source: ExerciseSource = .custom,
                         category: ExerciseCategory = .strength) throws -> ExerciseRecord {
        let record = ExerciseRecord(id: id, name: name ?? id, equipment: .machine, loadMode: loadMode, primaryMuscles: [.chest],
                                    secondaryMuscles: [], force: force, mechanic: nil, category: category, bodyRegion: region,
                                    movementPattern: pattern, instructions: [], source: source, libraryId: libraryId,
                                    stickyNote: nil, defaultRestSeconds: 60, preferredUnit: .kg, isFavorite: false,
                                    isArchived: archived, createdAt: base)
        try record.insert(db)
        return record
    }

    @discardableResult
    static func program(_ db: Database, name: String = "P", active: Bool = false) throws -> ProgramRecord {
        let record = ProgramRecord(id: UUID().uuidString, name: name, split: .custom, isActive: active, isArchived: false,
                                   sessionsPerWeekGoal: 3, source: .app, externalId: nil, createdAt: base)
        try record.insert(db)
        return record
    }

    @discardableResult
    static func day(_ db: Database, programId: String, name: String, focus: DayFocus = .fullBody, position: Int,
                    items: [String] = []) throws -> ProgramDayRecord {
        let record = ProgramDayRecord(id: UUID().uuidString, programId: programId, name: name, focus: focus,
                                      position: position, copiedFromDayId: nil, externalId: nil)
        try record.insert(db)
        for (i, exerciseId) in items.enumerated() {
            try DayExerciseRecord(id: UUID().uuidString, dayId: record.id, exerciseId: exerciseId, position: i, targetSets: 3,
                                  repMin: 8, repMax: 12, restSeconds: 90, note: nil, externalId: nil).insert(db)
        }
        return record
    }

    @discardableResult
    static func finishedWorkout(_ db: Database, dayId: String?, startedAt: Date,
                                exercises: [(String, [(kg: Double, reps: Int)])]) throws -> WorkoutRecord {
        let workout = WorkoutRecord(id: UUID().uuidString, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(3600),
                                    programDayId: dayId, title: "W", note: nil, effort: nil, restEndsAt: nil,
                                    restDurationSeconds: nil, source: .app, externalId: nil)
        try workout.insert(db)
        for (position, (exerciseId, sets)) in exercises.enumerated() {
            let we = WorkoutExerciseRecord(id: UUID().uuidString, workoutId: workout.id, exerciseId: exerciseId, position: position,
                                           dayExerciseId: nil, targetSets: nil, repMin: nil, repMax: nil, restSeconds: 60,
                                           note: nil, externalId: nil)
            try we.insert(db)
            for (n, set) in sets.enumerated() {
                try WorkoutSetRecord(id: UUID().uuidString, workoutExerciseId: we.id, position: n,
                                     loadHundredths: Int(set.kg * 100), unit: .kg, reps: set.reps, type: .working,
                                     completedAt: startedAt, rpe: nil, externalId: nil).insert(db)
            }
        }
        return workout
    }
}
