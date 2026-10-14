import Foundation
import GRDB

/// Card 7.8: an exercise's goal is a target estimated 1RM, kept as entered (hundredths plus
/// unit) in the setting table under "goal:<exercise id>".
nonisolated enum GoalQueries {
    static func key(_ exerciseId: String) -> String { "goal:" + exerciseId }

    static func goal(_ db: Database, exerciseId: String) throws -> Load? {
        guard let value = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key(exerciseId)]) else { return nil }
        let parts = value.split(separator: " ")
        guard parts.count == 2, let hundredths = Int(parts[0]), hundredths > 0,
              let unit = WeightUnit(rawValue: String(parts[1])) else { return nil }
        return Load(hundredths: hundredths, unit: unit)
    }

    static func setGoal(_ db: Database, exerciseId: String, goal: Load?) throws {
        if let goal {
            try SettingRecord(key: key(exerciseId), value: "\(goal.hundredths) \(goal.unit.rawValue)").save(db)
        } else {
            try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key(exerciseId)])
        }
    }
}
