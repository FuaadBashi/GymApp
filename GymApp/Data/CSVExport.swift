import Foundation
import GRDB

/// Card 4.1: every completed set of every finished workout, one row each. The first twelve
/// columns are Strong's, so other apps can read the file; the rest are GymApp's own.
nonisolated enum CSVExport {
    static let header = [
        "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight", "Reps", "Distance", "Seconds",
        "Notes", "Workout Notes", "RPE",
        "Weight Unit", "Set Type", "Reps In Reserve", "Labels", "Exercise Note", "Load Mode", "Equipment",
        "Primary Muscles", "Effort", "Workout ID", "Exercise ID",
    ]

    static func csv(_ db: Database, calendar: Calendar = .current) throws -> String {
        let workouts = try WorkoutRecord.fetchAll(db, sql: "SELECT * FROM workout WHERE endedAt IS NOT NULL ORDER BY startedAt")
        let wes = Dictionary(grouping: try WorkoutExerciseRecord.fetchAll(db, sql: "SELECT * FROM workoutExercise ORDER BY position"),
                             by: \.workoutId)
        let exercises = Dictionary(uniqueKeysWithValues: try ExerciseRecord.fetchAll(db).map { ($0.id, $0) })
        let sets = Dictionary(grouping: try WorkoutSetRecord.fetchAll(db, sql: """
            SELECT * FROM workoutSet WHERE completedAt IS NOT NULL ORDER BY workoutExerciseId, position
            """), by: \.workoutExerciseId)

        let dateFormat = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            timeZone: calendar.timeZone, calendar: calendar)

        var lines = [row(header)]
        for workout in workouts {
            let date = workout.startedAt.formatted(dateFormat)
            let duration = durationText((workout.endedAt ?? workout.startedAt).timeIntervalSince(workout.startedAt))
            for we in wes[workout.id] ?? [] {
                guard let exercise = exercises[we.exerciseId] else { continue }
                var working = 0
                for set in sets[we.id] ?? [] {
                    let order: String
                    switch set.type {
                    case .warmUp: order = "W"
                    case .drop: order = "D"
                    case .working, .failed:
                        working += 1
                        order = "\(working)"
                    }
                    let weight = exercise.loadMode == .repsOnly ? "" : set.loadHundredths.map { decimal($0) } ?? ""
                    lines.append(row([
                        date, workout.title, duration, exercise.name, order, weight, "\(set.reps)", "", "0",
                        set.note ?? "", workout.note ?? "", set.rpe.map { Load.format($0) } ?? "",
                        set.unit.rawValue, set.type.rawValue, set.repsInReserve.map(String.init) ?? "",
                        set.annotations.map(\.rawValue).joined(separator: ";"), we.note ?? "",
                        exercise.loadMode.rawValue, exercise.equipment.rawValue,
                        exercise.primaryMuscles.map(\.rawValue).joined(separator: ";"),
                        workout.effort.map(String.init) ?? "", workout.id, exercise.id,
                    ]))
                }
            }
        }
        return lines.joined()
    }

    /// Writes the export to the temporary directory for the share sheet.
    static func write(_ db: Database, now: Date = .now) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "GymApp-sets-\(DayString.from(now)).csv")
        try Data(try csv(db).utf8).write(to: url, options: .atomic)
        return url
    }

    /// Hundredths as a plain decimal with a dot, whatever the locale: "62.5", "-45", "20".
    static func decimal(_ hundredths: Int) -> String {
        let sign = hundredths < 0 ? "-" : ""
        let a = abs(hundredths)
        let whole = a / 100, frac = a % 100
        if frac == 0 { return "\(sign)\(whole)" }
        return frac % 10 == 0 ? "\(sign)\(whole).\(frac / 10)" : "\(sign)\(whole).\(String(format: "%02d", frac))"
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// RFC 4180: quote fields holding a comma, quote or line break; double inner quotes.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + "\r\n"
    }
}
