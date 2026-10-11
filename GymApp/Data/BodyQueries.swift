import Foundation
import GRDB

nonisolated enum BodyQueries {
    /// The latest recorded body weight on or before `date`'s day, in kg. Used for
    /// `bodyweightPlus` volume (rulebook §2).
    static func weightKg(_ db: Database, onOrBefore date: Date) throws -> Double? {
        let day = DayString.from(date)
        guard let entry = try BodyEntryRecord
            .filter(Column("date") <= day && Column("weightHundredths") != nil)
            .order(Column("date").desc).fetchOne(db),
              let hundredths = entry.weightHundredths else { return nil }
        return Load(hundredths: hundredths, unit: entry.weightUnit).kg
    }

    /// Every recorded weight at once, for bulk queries over the whole history: the result
    /// answers `weightKg(onOrBefore:)` for any date without another query.
    static func weightLookup(_ db: Database) throws -> @Sendable (Date) -> Double? {
        let entries: [(day: String, kg: Double)] = try BodyEntryRecord
            .filter(Column("weightHundredths") != nil).order(Column("date")).fetchAll(db)
            .compactMap { e in e.weightHundredths.map { (e.date, Load(hundredths: $0, unit: e.weightUnit).kg) } }
        return { date in
            let day = DayString.from(date)
            return entries.last { $0.day <= day }?.kg
        }
    }
}
