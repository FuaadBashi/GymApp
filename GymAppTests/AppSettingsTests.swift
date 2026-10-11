import Foundation
import GRDB
import Testing
@testable import GymApp

struct AppSettingsTests {
    let db = try! AppDatabase.inMemory()

    @Test func anEmptyDatabaseGivesTheDefaults() throws {
        #expect(try db.reader.read { try AppSettings.load($0) } == AppSettings())
    }

    @Test func savingThenLoadingRoundTripsEveryField() throws {
        let s = AppSettings(weightUnit: .lb, weekStartsOn: .monday, defaultRestSeconds: 90, defaultSets: 4,
                            defaultRepMin: 6, defaultRepMax: 10, lastTimeSource: .anyWorkout)
        try db.writer.write { try s.save($0) }
        #expect(try db.reader.read { try AppSettings.load($0) } == s)
    }

    @Test func anUnknownWeekStartFallsBackToSunday() throws {
        try db.writer.write { try SettingRecord(key: "weekStartsOn", value: "tuesday").insert($0) }
        #expect(try db.reader.read { try AppSettings.load($0) }.weekStartsOn == .sunday)
    }
}
