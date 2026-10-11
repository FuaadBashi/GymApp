import Foundation

struct SetEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var load: Load
    var reps: Int
    var type: SetType = .working
    /// nil while the row only holds values prefilled from last time.
    var loggedAt: Date?

    var isLogged: Bool { loggedAt != nil }
    var asPastSet: PastSet { PastSet(kg: load.kg, reps: reps, type: type) }
}

struct ExerciseInWorkout: Codable, Identifiable, Hashable {
    var id = UUID()
    var exerciseId: String
    var name: String
    var equipment: ProtoEquipment
    var restSeconds: Int
    var note: String?
    var noteDate: String?
    /// Snapshot taken at the start (rulebook §10), so the comparison stays what it was.
    var lastTime: HistoryEntry?
    var lastTimeIsSameDay: Bool
    var sets: [SetEntry]
    var selected: Int = 0

    var loggedSets: [SetEntry] { sets.filter(\.isLogged) }
    var nextUnlogged: Int? { sets.firstIndex { !$0.isLogged } }
    var isComplete: Bool { !sets.isEmpty && nextUnlogged == nil }
}

struct WorkoutSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var dayId: String
    var dayName: String
    var startedAt: Date
    var endedAt: Date?
    var exercises: [ExerciseInWorkout]
    var currentExercise: Int = 0
    /// Stored as an absolute time (rulebook §9) so a locked phone cannot make it drift.
    var restEndsAt: Date?
    var restDuration: TimeInterval = 0

    var loggedSetCount: Int { exercises.reduce(0) { $0 + $1.loggedSets.count } }
}
