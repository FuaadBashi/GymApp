import Foundation
import GRDB

nonisolated enum ProgramError: LocalizedError, Equatable {
    case onlyAppProgramsCanBeDeleted
    case copyIntoItself

    var errorDescription: String? {
        switch self {
        case .onlyAppProgramsCanBeDeleted: "Imported programs are kept: they hold your history's days."
        case .copyIntoItself: "A day can't be copied into itself."
        }
    }
}

nonisolated enum ProgramWrites {
    /// Days each split creates, in order.
    static func template(for split: Split, fullBodyDays: Int) -> [(name: String, focus: DayFocus)] {
        switch split {
        case .fullBody: (1...max(1, fullBodyDays)).map { ("Full Body \($0)", .fullBody) }
        case .upperLower4: [("Upper A", .upper), ("Lower A", .lower), ("Upper B", .upper), ("Lower B", .lower)]
        case .upperLower6: [("Upper A", .upper), ("Lower A", .lower), ("Upper B", .upper), ("Lower B", .lower),
                            ("Upper C", .upper), ("Lower C", .lower)]
        case .pushPullLegs3: [("Push", .push), ("Pull", .pull), ("Legs", .legs)]
        case .pushPullLegs6: [("Push A", .push), ("Pull A", .pull), ("Legs A", .legs),
                              ("Push B", .push), ("Pull B", .pull), ("Legs B", .legs)]
        case .custom: [("Day 1", .custom)]
        }
    }

    @discardableResult
    static func createProgram(_ db: Database, name: String, split: Split, fullBodyDays: Int = 3,
                              makeActive: Bool, now: Date) throws -> ProgramRecord {
        if makeActive { try db.execute(sql: "UPDATE program SET isActive = 0 WHERE isActive = 1") }
        let program = ProgramRecord(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    split: split, isActive: makeActive, isArchived: false, sessionsPerWeekGoal: 3,
                                    source: .app, externalId: nil, createdAt: now)
        try program.insert(db)
        for (position, day) in template(for: split, fullBodyDays: fullBodyDays).enumerated() {
            try ProgramDayRecord(id: UUID().uuidString, programId: program.id, name: day.name, focus: day.focus,
                                 position: position, copiedFromDayId: nil, externalId: nil).insert(db)
        }
        return program
    }

    static func setActive(_ db: Database, programId: String) throws {
        try db.execute(sql: "UPDATE program SET isActive = 0 WHERE isActive = 1 AND id != ?", arguments: [programId])
        try db.execute(sql: "UPDATE program SET isActive = 1, isArchived = 0 WHERE id = ?", arguments: [programId])
    }

    static func setArchived(_ db: Database, programId: String, _ archived: Bool) throws {
        try db.execute(sql: "UPDATE program SET isArchived = ?, isActive = CASE WHEN ? THEN 0 ELSE isActive END WHERE id = ?",
                       arguments: [archived, archived, programId])
    }

    static func rename(_ db: Database, programId: String, to name: String) throws {
        try db.execute(sql: "UPDATE program SET name = ? WHERE id = ?", arguments: [name.trimmingCharacters(in: .whitespacesAndNewlines), programId])
    }

    /// Workouts keep their data: their programDayId becomes nil through the foreign key.
    static func deleteProgram(_ db: Database, programId: String) throws {
        guard let program = try ProgramRecord.fetchOne(db, key: programId), program.source == .app else {
            throw ProgramError.onlyAppProgramsCanBeDeleted
        }
        try program.delete(db)
    }

    @discardableResult
    static func addDay(_ db: Database, programId: String, name: String, focus: DayFocus) throws -> ProgramDayRecord {
        let position = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM programDay WHERE programId = ?", arguments: [programId]) ?? 0
        let day = ProgramDayRecord(id: UUID().uuidString, programId: programId, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                   focus: focus, position: position, copiedFromDayId: nil, externalId: nil)
        try day.insert(db)
        return day
    }

    static func renameDay(_ db: Database, dayId: String, to name: String) throws {
        try db.execute(sql: "UPDATE programDay SET name = ? WHERE id = ?", arguments: [name.trimmingCharacters(in: .whitespacesAndNewlines), dayId])
    }

    static func setFocus(_ db: Database, dayId: String, _ focus: DayFocus) throws {
        try db.execute(sql: "UPDATE programDay SET focus = ? WHERE id = ?", arguments: [focus.rawValue, dayId])
    }

    static func deleteDay(_ db: Database, dayId: String) throws {
        guard let day = try ProgramDayRecord.fetchOne(db, key: dayId) else { return }
        try day.delete(db)
        try renumberDays(db, programId: day.programId)
    }

    static func moveDay(_ db: Database, programId: String, from: Int, to: Int) throws {
        var days = try ProgramDayRecord.filter(Column("programId") == programId).order(Column("position")).fetchAll(db)
        guard days.indices.contains(from) else { return }
        days.insert(days.remove(at: from), at: min(max(to, 0), days.count))
        for (i, var day) in days.enumerated() where day.position != i {
            day.position = i
            try day.update(db)
        }
    }

    static func addExercises(_ db: Database, dayId: String, exerciseIds: [String], settings: AppSettings) throws {
        var position = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dayExercise WHERE dayId = ?", arguments: [dayId]) ?? 0
        for id in exerciseIds {
            let rest = try Int.fetchOne(db, sql: "SELECT defaultRestSeconds FROM exercise WHERE id = ?", arguments: [id]) ?? settings.defaultRestSeconds
            try DayExerciseRecord(id: UUID().uuidString, dayId: dayId, exerciseId: id, position: position,
                                  targetSets: settings.defaultSets, repMin: settings.defaultRepMin,
                                  repMax: max(settings.defaultRepMax, settings.defaultRepMin), restSeconds: rest,
                                  note: nil, externalId: nil).insert(db)
            position += 1
        }
    }

    static func updateItem(_ db: Database, item: DayExerciseRecord) throws {
        try item.update(db)
    }

    static func removeItem(_ db: Database, itemId: String) throws {
        guard let item = try DayExerciseRecord.fetchOne(db, key: itemId) else { return }
        try item.delete(db)
        try renumberItems(db, dayId: item.dayId)
    }

    static func moveItem(_ db: Database, dayId: String, from: Int, to: Int) throws {
        var items = try DayExerciseRecord.filter(Column("dayId") == dayId).order(Column("position")).fetchAll(db)
        guard items.indices.contains(from) else { return }
        items.insert(items.remove(at: from), at: min(max(to, 0), items.count))
        for (i, var item) in items.enumerated() where item.position != i {
            item.position = i
            try item.update(db)
        }
    }

    /// Replaces the target's exercises with copies of the source's and remembers the source,
    /// so last-time values follow (rulebook §7).
    static func copyDay(_ db: Database, from sourceDayId: String, into targetDayId: String) throws {
        guard sourceDayId != targetDayId else { throw ProgramError.copyIntoItself }
        try db.execute(sql: "DELETE FROM dayExercise WHERE dayId = ?", arguments: [targetDayId])
        let source = try DayExerciseRecord.filter(Column("dayId") == sourceDayId).order(Column("position")).fetchAll(db)
        for (position, item) in source.enumerated() {
            var copy = item
            copy.id = UUID().uuidString
            copy.dayId = targetDayId
            copy.position = position
            copy.externalId = nil
            try copy.insert(db)
        }
        try db.execute(sql: "UPDATE programDay SET copiedFromDayId = ? WHERE id = ?", arguments: [sourceDayId, targetDayId])
    }

    private static func renumberDays(_ db: Database, programId: String) throws {
        let days = try ProgramDayRecord.filter(Column("programId") == programId).order(Column("position")).fetchAll(db)
        for (i, var day) in days.enumerated() where day.position != i { day.position = i; try day.update(db) }
    }

    private static func renumberItems(_ db: Database, dayId: String) throws {
        let items = try DayExerciseRecord.filter(Column("dayId") == dayId).order(Column("position")).fetchAll(db)
        for (i, var item) in items.enumerated() where item.position != i { item.position = i; try item.update(db) }
    }
}
