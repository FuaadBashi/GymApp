import Foundation
import GRDB

nonisolated struct DayItem: Identifiable, Equatable {
    var dayExercise: DayExerciseRecord
    var exercise: ExerciseRecord
    var id: String { dayExercise.id }
}

nonisolated struct DayDetail: Identifiable, Equatable {
    var day: ProgramDayRecord
    var items: [DayItem]  // in position order
    var id: String { day.id }
}

nonisolated struct ProgramSummary: Identifiable, Equatable {
    var program: ProgramRecord
    var dayCount: Int
    var id: String { program.id }
}

nonisolated enum ProgramQueries {
    /// Active first, then the rest newest first, then archived by name.
    static func programs(_ db: Database) throws -> [ProgramSummary] {
        let counts = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT programId, COUNT(*) AS n FROM programDay GROUP BY programId")
            .map { ($0["programId"] as String, $0["n"] as Int) })
        return try ProgramRecord.fetchAll(db).sorted { a, b in
            let rank = { (p: ProgramRecord) in p.isActive ? 0 : p.isArchived ? 2 : 1 }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if a.isArchived { return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
            return a.createdAt > b.createdAt
        }.map { ProgramSummary(program: $0, dayCount: counts[$0.id] ?? 0) }
    }

    static func activeProgram(_ db: Database) throws -> ProgramRecord? {
        try ProgramRecord.filter(Column("isActive") == true).fetchOne(db)
    }

    static func days(_ db: Database, programId: String) throws -> [DayDetail] {
        let days = try ProgramDayRecord.filter(Column("programId") == programId).order(Column("position")).fetchAll(db)
        return try days.map { try detail(db, day: $0) }
    }

    static func detail(_ db: Database, dayId: String) throws -> DayDetail? {
        try ProgramDayRecord.fetchOne(db, key: dayId).map { try detail(db, day: $0) }
    }

    private static func detail(_ db: Database, day: ProgramDayRecord) throws -> DayDetail {
        let items = try DayExerciseRecord.filter(Column("dayId") == day.id).order(Column("position")).fetchAll(db)
        let exercises = Dictionary(uniqueKeysWithValues: try ExerciseRecord.filter(keys: Set(items.map(\.exerciseId))).fetchAll(db).map { ($0.id, $0) })
        return DayDetail(day: day, items: items.compactMap { item in exercises[item.exerciseId].map { DayItem(dayExercise: item, exercise: $0) } })
    }

    /// The day followed by the days it was copied from (rulebook §7), stopping at a repeat
    /// or after 10 hops so a corrupt chain cannot loop.
    static func lineage(_ db: Database, dayId: String) throws -> [String] {
        var chain = [dayId]
        var current = dayId
        for _ in 0..<10 {
            guard let next = try String.fetchOne(db, sql: "SELECT copiedFromDayId FROM programDay WHERE id = ?", arguments: [current]),
                  !chain.contains(next) else { break }
            chain.append(next)
            current = next
        }
        return chain
    }

    static func lastDone(_ db: Database, dayId: String) throws -> Date? {
        let ids = try lineage(db, dayId: dayId)
        return try Date.fetchOne(db, sql: """
            SELECT MAX(startedAt) FROM workout WHERE endedAt IS NOT NULL AND programDayId IN (\(ids.map { _ in "?" }.joined(separator: ",")))
            """, arguments: StatementArguments(ids))
    }

    /// Decision #12, rolling rotation: the first day never done, else the least recently done.
    static func nextDay(_ db: Database, programId: String) throws -> ProgramDayRecord? {
        let days = try ProgramDayRecord.filter(Column("programId") == programId).order(Column("position")).fetchAll(db)
        var oldest: (day: ProgramDayRecord, date: Date)?
        for day in days {
            guard let done = try lastDone(db, dayId: day.id) else { return day }
            if oldest == nil || done < oldest!.date { oldest = (day, done) }
        }
        return oldest?.day
    }

    /// Rulebook §11 fallback: Σ sets × (40 s + rest).
    static func estimatedMinutes(for detail: DayDetail) -> Int {
        let seconds = detail.items.reduce(0) { $0 + $1.dayExercise.targetSets * (40 + $1.dayExercise.restSeconds) }
        return Int((Double(seconds) / 60).rounded())
    }
}
