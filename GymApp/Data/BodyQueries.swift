import Foundation
import GRDB

nonisolated enum BodyQueries {
    /// Every recorded body weight, oldest first, in kg: entries typed in the app or imported
    /// from JEFIT, and daily weights from Apple Health. On a day with both, the typed entry wins.
    static func weights(_ db: Database) throws -> [(day: String, kg: Double)] {
        var byDay: [String: Double] = [:]
        for h in try HealthDayRecord.filter(Column("weightHundredths") != nil).fetchAll(db) {
            if let hundredths = h.weightHundredths, let unit = h.weightUnit {
                byDay[h.date] = Load(hundredths: hundredths, unit: unit).kg
            }
        }
        for e in try BodyEntryRecord.filter(Column("weightHundredths") != nil).fetchAll(db) {
            if let hundredths = e.weightHundredths { byDay[e.date] = Load(hundredths: hundredths, unit: e.weightUnit).kg }
        }
        return byDay.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// The latest body weight on or before `date`'s day, in kg. Used for `bodyweightPlus`
    /// volume (rulebook §2).
    static func weightKg(_ db: Database, onOrBefore date: Date) throws -> Double? {
        let day = DayString.from(date)
        return try weights(db).last { $0.day <= day }?.kg
    }

    /// Every weight at once, for bulk queries over the whole history: the result answers
    /// `weightKg(onOrBefore:)` for any date without another query.
    static func weightLookup(_ db: Database) throws -> @Sendable (Date) -> Double? {
        let entries = try weights(db)
        return { date in
            let day = DayString.from(date)
            return entries.last { $0.day <= day }?.kg
        }
    }

    /// Daily steps from Apple Health, oldest first.
    static func steps(_ db: Database, since day: String) throws -> [(day: String, steps: Int)] {
        try HealthDayRecord.filter(Column("date") >= day && Column("steps") != nil).order(Column("date")).fetchAll(db)
            .compactMap { r in r.steps.map { (r.date, $0) } }
    }
}

nonisolated enum HealthWrites {
    nonisolated struct Day: Equatable, Sendable {
        var date: String
        var steps: Int?
        var weightKg: Double?
    }

    /// Upserts daily totals. A value Health no longer reports for a day is cleared, so the
    /// table always mirrors Health for the synced range.
    static func upsert(_ db: Database, days: [Day]) throws {
        for d in days {
            let hundredths = d.weightKg.map { Int(($0 * 100).rounded()) }
            try db.execute(sql: """
                INSERT INTO healthDay (date, steps, weightHundredths, weightUnit) VALUES (?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET steps = excluded.steps, weightHundredths = excluded.weightHundredths,
                  weightUnit = excluded.weightUnit
                """, arguments: [d.date, d.steps, hundredths, hundredths == nil ? nil : "kg"])
        }
    }
}
