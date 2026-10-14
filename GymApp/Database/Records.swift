import Foundation
import GRDB

// One struct per table, properties named as the columns. GRDB stores Date as UTC text,
// arrays and dictionaries as JSON, Bool as 0/1 and enums as their raw value.

nonisolated struct ExerciseRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "exercise"
    var id: String
    var name: String
    var equipment: Equipment
    var loadMode: LoadMode
    var primaryMuscles: [Muscle]
    var secondaryMuscles: [Muscle]
    var force: Force?
    var mechanic: Mechanic?
    var category: ExerciseCategory
    var bodyRegion: BodyRegion
    var movementPattern: MovementPattern?
    var instructions: [String]
    var source: ExerciseSource
    var libraryId: String?
    var stickyNote: String?
    var defaultRestSeconds: Int
    var preferredUnit: WeightUnit
    var isFavorite: Bool
    var isArchived: Bool
    var createdAt: Date
}

nonisolated struct ProgramRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "program"
    var id: String
    var name: String
    var split: Split
    var isActive: Bool
    var isArchived: Bool
    var sessionsPerWeekGoal: Int
    var source: RecordSource
    var externalId: String?
    var createdAt: Date
}

nonisolated struct ProgramDayRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "programDay"
    var id: String
    var programId: String
    var name: String
    var focus: DayFocus
    var position: Int
    var copiedFromDayId: String?
    var externalId: String?
}

nonisolated struct DayExerciseRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "dayExercise"
    var id: String
    var dayId: String
    var exerciseId: String
    var position: Int
    var targetSets: Int
    var repMin: Int
    var repMax: Int
    var restSeconds: Int
    var note: String?
    var externalId: String?
    var supersetGroup: String? = nil
    var supersetRestSeconds: Int = 0
    var warmUps: Bool = false
}

nonisolated struct WorkoutRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout"
    var id: String
    var startedAt: Date
    var endedAt: Date?
    var programDayId: String?
    var title: String
    var note: String?
    var effort: Int?
    var restEndsAt: Date?
    var restDurationSeconds: Double?
    var source: RecordSource
    var externalId: String?
}

nonisolated struct WorkoutExerciseRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workoutExercise"
    var id: String
    var workoutId: String
    var exerciseId: String
    var position: Int
    var dayExerciseId: String?
    var targetSets: Int?
    var repMin: Int?
    var repMax: Int?
    var restSeconds: Int
    var note: String?
    var externalId: String?
    var supersetGroup: String? = nil
    var supersetRestSeconds: Int = 0
}

nonisolated struct WorkoutSetRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workoutSet"
    var id: String
    var workoutExerciseId: String
    var position: Int
    var loadHundredths: Int?
    var unit: WeightUnit
    var reps: Int
    var type: SetType
    var completedAt: Date?
    var rpe: Double?
    var externalId: String?
    var note: String? = nil
    var repsInReserve: Int? = nil
    var annotations: [SetAnnotation] = []

}

nonisolated struct ExerciseNoteRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "exerciseNote"
    var id: String
    var exerciseId: String
    var date: String
    var text: String
    var source: RecordSource
    var externalId: String?
}

nonisolated struct HealthDayRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "healthDay"
    var date: String          // yyyy-MM-dd, local
    var steps: Int?
    var weightHundredths: Int?
    var weightUnit: WeightUnit?
    var source: String = "health"
    var id: String { date }
}

nonisolated struct StudioDecisionRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "studioDecision"
    enum Decision: String, Codable, Sendable { case accepted, dismissed }
    var suggestionId: String
    var kind: StudioSuggestion.Kind
    var decision: Decision
    var decidedAt: Date
    var title: String
    var exerciseId: String?
    var loadHundredths: Int?
    var unit: WeightUnit?
    var reps: Int?
    var id: String { suggestionId }
}

nonisolated struct BodyEntryRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bodyEntry"
    var id: String
    var date: String
    var weightHundredths: Int?
    var weightUnit: WeightUnit
    var bodyFatPercent: Double?
    var measurements: [String: Double]
    var source: RecordSource
    var externalId: String?
}

nonisolated struct SettingRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "setting"
    var key: String
    var value: String
    var id: String { key }
}

nonisolated struct ImportRunRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "importRun"
    var id: String
    var source: String
    var fileName: String
    var fileSHA256: String
    var ranAt: Date
    var report: ImportReport
}
