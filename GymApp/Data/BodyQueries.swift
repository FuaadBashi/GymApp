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
}
