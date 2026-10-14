import Foundation
import GRDB

nonisolated enum WeekStart: String, CaseIterable { case sunday, monday }
nonisolated enum LastTimeSource: String, CaseIterable { case sameDay, anyWorkout }

/// Settings live in the `setting` table as key/value strings. A missing or unreadable value
/// falls back to its default rather than failing: a bad row must never stop the app.
nonisolated struct AppSettings: Equatable {
    var weightUnit: WeightUnit = .kg
    var weekStartsOn: WeekStart = .sunday
    var defaultRestSeconds = 60
    var defaultSets = 3
    var defaultRepMin = 8
    var defaultRepMax = 12
    var lastTimeSource: LastTimeSource = .sameDay
    var platesKg = "25, 20, 15, 10, 5, 2.5, 1.25"
    var platesLb = "45, 35, 25, 10, 5, 2.5"
    // Card 7.8: the profile for strength standards. Empty or 0 means not set.
    var sex = ""
    var birthYear = 0
    var heightCm = 0

    /// A comma-separated plate list as numbers, largest first; junk entries are ignored.
    static func plates(_ text: String) -> [Double] {
        text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }.sorted(by: >)
    }

    static func load(_ db: Database) throws -> AppSettings {
        let values = Dictionary(uniqueKeysWithValues: try SettingRecord.fetchAll(db).map { ($0.key, $0.value) })
        var s = AppSettings()
        if let v = values["weightUnit"].flatMap(WeightUnit.init(rawValue:)) { s.weightUnit = v }
        if let v = values["weekStartsOn"].flatMap(WeekStart.init(rawValue:)) { s.weekStartsOn = v }
        if let v = values["defaultRestSeconds"].flatMap(Int.init), (0...900).contains(v) { s.defaultRestSeconds = v }
        if let v = values["defaultSets"].flatMap(Int.init), (1...20).contains(v) { s.defaultSets = v }
        if let v = values["defaultRepMin"].flatMap(Int.init), v >= 1 { s.defaultRepMin = v }
        if let v = values["defaultRepMax"].flatMap(Int.init), v >= s.defaultRepMin { s.defaultRepMax = v }
        if let v = values["lastTimeSource"].flatMap(LastTimeSource.init(rawValue:)) { s.lastTimeSource = v }
        if let v = values["platesKg"], !plates(v).isEmpty { s.platesKg = v }
        if let v = values["platesLb"], !plates(v).isEmpty { s.platesLb = v }
        if let v = values["sex"], ["male", "female"].contains(v) { s.sex = v }
        if let v = values["birthYear"].flatMap(Int.init), (1900...2100).contains(v) { s.birthYear = v }
        if let v = values["heightCm"].flatMap(Int.init), (50...260).contains(v) { s.heightCm = v }
        return s
    }

    func save(_ db: Database) throws {
        let values: [String: String] = [
            "weightUnit": weightUnit.rawValue,
            "weekStartsOn": weekStartsOn.rawValue,
            "defaultRestSeconds": String(defaultRestSeconds),
            "defaultSets": String(defaultSets),
            "defaultRepMin": String(defaultRepMin),
            "defaultRepMax": String(defaultRepMax),
            "lastTimeSource": lastTimeSource.rawValue,
            "platesKg": platesKg,
            "platesLb": platesLb,
            "sex": sex,
            "birthYear": String(birthYear),
            "heightCm": String(heightCm),
        ]
        for (key, value) in values {
            try SettingRecord(key: key, value: value).save(db)
        }
    }
}
