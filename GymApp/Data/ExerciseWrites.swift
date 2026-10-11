import Foundation
import GRDB

nonisolated struct ExerciseDraft: Equatable {
    var name = ""
    var equipment: Equipment = .machine
    var loadMode: LoadMode = .total
    var primaryMuscles: [Muscle] = []
    var secondaryMuscles: [Muscle] = []
    var movementPattern: MovementPattern? = nil
    var defaultRestSeconds = 60
    var preferredUnit: WeightUnit = .kg

    /// Decision #22: one region when every primary muscle shares it, full body otherwise.
    var bodyRegion: BodyRegion { ExerciseWrites.region(for: primaryMuscles) }
}

nonisolated enum ExerciseError: LocalizedError, Equatable {
    case duplicateName(existingId: String)
    case emptyName
    case loadModeLockedByHistory

    var errorDescription: String? {
        switch self {
        case .duplicateName: "You already have an exercise with that name."
        case .emptyName: "Give the exercise a name."
        case .loadModeLockedByHistory: "Load mode can't change once an exercise has history. Create a new exercise instead."
        }
    }
}

nonisolated enum ExerciseWrites {
    static func region(for muscles: [Muscle]) -> BodyRegion {
        let regions = Set(muscles.map(\.region))
        return regions.count == 1 ? regions.first! : .fullBody
    }

    @discardableResult
    static func createCustom(_ db: Database, draft: ExerciseDraft, now: Date) throws -> ExerciseRecord {
        let name = try validName(db, draft.name, excluding: nil)
        let record = ExerciseRecord(
            id: "custom:\(UUID().uuidString)", name: name, equipment: draft.equipment, loadMode: draft.loadMode,
            primaryMuscles: draft.primaryMuscles, secondaryMuscles: draft.secondaryMuscles, force: nil, mechanic: nil,
            category: .strength, bodyRegion: draft.bodyRegion, movementPattern: draft.movementPattern, instructions: [],
            source: .custom, libraryId: nil, stickyNote: nil, defaultRestSeconds: draft.defaultRestSeconds,
            preferredUnit: draft.preferredUnit, isFavorite: false, isArchived: false, createdAt: now)
        try record.insert(db)
        return record
    }

    static func update(_ db: Database, exercise: ExerciseRecord) throws {
        var exercise = exercise
        exercise.name = try validName(db, exercise.name, excluding: exercise.id)
        if let stored = try ExerciseRecord.fetchOne(db, key: exercise.id), stored.loadMode != exercise.loadMode,
           try hasHistory(db, exerciseId: exercise.id) {
            // Rulebook §2: changing the mode would change what every past set means.
            throw ExerciseError.loadModeLockedByHistory
        }
        if exercise.source == .custom { exercise.bodyRegion = region(for: exercise.primaryMuscles) }
        try exercise.update(db)
    }

    static func hasHistory(_ db: Database, exerciseId: String) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM workoutSet s JOIN workoutExercise we ON we.id = s.workoutExerciseId
                           WHERE we.exerciseId = ?)
            """, arguments: [exerciseId]) ?? false
    }

    static func setFavorite(_ db: Database, id: String, _ value: Bool) throws {
        try db.execute(sql: "UPDATE exercise SET isFavorite = ? WHERE id = ?", arguments: [value, id])
    }

    static func setArchived(_ db: Database, id: String, _ value: Bool) throws {
        try db.execute(sql: "UPDATE exercise SET isArchived = ? WHERE id = ?", arguments: [value, id])
    }

    static func setStickyNote(_ db: Database, id: String, text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.execute(sql: "UPDATE exercise SET stickyNote = ? WHERE id = ?", arguments: [trimmed.isEmpty ? nil : trimmed, id])
    }

    static func addNote(_ db: Database, exerciseId: String, text: String, date: Date) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try ExerciseNoteRecord(id: UUID().uuidString, exerciseId: exerciseId, date: DayString.from(date),
                               text: trimmed, source: .app, externalId: nil).insert(db)
    }

    private static func validName(_ db: Database, _ name: String, excluding id: String?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExerciseError.emptyName }
        let clash = try String.fetchOne(db, sql: """
            SELECT id FROM exercise WHERE isArchived = 0 AND lower(trim(name)) = lower(?) AND id != ?
            """, arguments: [trimmed, id ?? ""])
        if let clash { throw ExerciseError.duplicateName(existingId: clash) }
        return trimmed
    }
}

/// `yyyy-MM-dd` in the device's calendar, the format of note and body-entry dates.
nonisolated enum DayString {
    static func from(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Local midnight of a "yyyy-MM-dd" string.
    static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
