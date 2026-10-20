import Foundation
import GRDB

nonisolated enum LogCSVImportError: LocalizedError, Equatable {
    case unrecognised
    case badRow(Int, String)

    var errorDescription: String? {
        switch self {
        case .unrecognised: "This isn't a Strong or Hevy workout export (its header row wasn't recognised)."
        case .badRow(let line, let why): "Row \(line) can't be read: \(why)."
        }
    }
}

/// CORE_JOBS item 5: workouts from a Strong (or GymApp) CSV or a Hevy workouts.csv, one row per
/// set. Workouts are stored with source "app" and externalId "strong:…" or "hevy:…" (the
/// workout.source CHECK predates these formats; see DECISIONS.md). One transaction; a
/// workout starting in the same minute as an existing one counts as already present, so
/// re-importing, or importing GymApp's own export, never duplicates.
nonisolated enum LogCSVImporter {
    enum Format: String { case strong, hevy }

    struct SetRow: Equatable {
        var start: Date
        var end: Date?
        var title: String
        var exercise: String
        var type: SetType
        var load: Double?
        var unit: WeightUnit
        var reps: Int
        var rpe: Double?
        var note: String?
        var workoutNote: String?
    }

    // MARK: Parsing

    static func parse(_ data: Data, timeZone: TimeZone = .current) throws -> (Format, [SetRow]) {
        let records = JEFITExport.records(in: data).filter { !($0.count == 1 && $0[0].isEmpty) }
        guard let header = records.first?.map({ $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{FEFF}", with: "") })
        else { throw LogCSVImportError.unrecognised }
        let column = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        if column["exercise_title"] != nil, column["start_time"] != nil {
            return (.hevy, try rows(records.dropFirst(), column, timeZone, hevy: true))
        }
        if column["Exercise Name"] != nil, column["Date"] != nil, column["Set Order"] != nil {
            return (.strong, try rows(records.dropFirst(), column, timeZone, hevy: false))
        }
        throw LogCSVImportError.unrecognised
    }

    private static func rows(_ records: ArraySlice<[String]>, _ column: [String: Int], _ zone: TimeZone, hevy: Bool) throws -> [SetRow] {
        var out: [SetRow] = []
        for (offset, record) in records.enumerated() {
            let line = offset + 2
            func field(_ name: String) -> String? {
                guard let i = column[name], i < record.count else { return nil }
                let v = record[i].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            let startText = field(hevy ? "start_time" : "Date")
            guard let startText, let start = date(startText, zone) else { throw LogCSVImportError.badRow(line, "no readable date") }
            guard let name = field(hevy ? "exercise_title" : "Exercise Name") else { throw LogCSVImportError.badRow(line, "no exercise name") }
            let repsText = field(hevy ? "reps" : "Reps") ?? "0"
            guard let reps = Int(Double(repsText) ?? -1).nonNegative else { throw LogCSVImportError.badRow(line, "reps \"\(repsText)\"") }

            var unit = WeightUnit.kg
            var loadText: String?
            if hevy {
                if let kg = field("weight_kg") { loadText = kg } else if let lb = field("weight_lbs") { loadText = lb; unit = .lb }
            } else {
                loadText = field("Weight") ?? field("Weight (kg)") ?? field("Weight (lbs)").map { unit = .lb; return $0 }
                if field("Weight Unit") == "lb" { unit = .lb }      // GymApp's own export
            }
            let load = loadText.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }

            let type: SetType
            if hevy {
                switch field("set_type") ?? "normal" {
                case "warmup": type = .warmUp
                case "dropset": type = .drop
                case "failure": type = .failed
                default: type = .working
                }
            } else {
                switch field("Set Type") ?? field("Set Order") ?? "" {   // GymApp's export names the type
                case "warmUp", "W": type = .warmUp
                case "drop", "D": type = .drop
                case "failed", "F": type = .failed
                default: type = .working
                }
            }
            let end = hevy ? field("end_time").flatMap { date($0, zone) } : field("Duration").flatMap(duration).map { start.addingTimeInterval($0) }
            out.append(SetRow(start: start, end: end, title: field(hevy ? "title" : "Workout Name") ?? "Workout", exercise: name,
                              type: type, load: load, unit: unit, reps: reps,
                              rpe: field(hevy ? "rpe" : "RPE").flatMap(Double.init).flatMap { (1...10).contains($0) ? $0 : nil },
                              note: field(hevy ? "exercise_notes" : "Notes"), workoutNote: field(hevy ? "description" : "Workout Notes")))
        }
        return out
    }

    /// Strong: "2023-01-05 18:30:00"; Hevy: "15 Jul 2026, 09:52" (also ISO 8601).
    static func date(_ text: String, _ zone: TimeZone) -> Date? {
        if let iso = ISO8601DateFormatter().date(from: text) { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "d MMM yyyy, HH:mm", "d MMM yyyy HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }

    /// Strong's "1h 5m", "45m", "50s"; GymApp writes the same.
    static func duration(_ text: String) -> TimeInterval? {
        var total = 0.0, found = false
        for part in text.split(separator: " ") {
            guard let unit = part.last, let n = Double(part.dropLast()) else { continue }
            switch unit {
            case "h": total += n * 3600; found = true
            case "m": total += n * 60; found = true
            case "s": total += n; found = true
            default: continue
            }
        }
        return found ? total : nil
    }

    // MARK: Writing

    static func run(_ format: Format, _ rows: [SetRow], in db: Database, now: Date,
                    fileName: String, fileSHA256: String) throws -> ImportReport {
        var report = ImportReport()
        var exerciseIds: [String: String] = [:]
        let byStart = Dictionary(grouping: rows) { $0.start }
        for start in byStart.keys.sorted() {
            let sets = byStart[start]!
            let minute = Date(timeIntervalSince1970: (start.timeIntervalSince1970 / 60).rounded(.down) * 60)
            let clash = try WorkoutRecord.filter(Column("startedAt") >= minute && Column("startedAt") < minute.addingTimeInterval(60)).fetchCount(db)
            if clash > 0 { report.alreadyPresent["workout", default: 0] += 1; continue }
            let first = sets[0]
            let longest = sets.compactMap(\.end).max() ?? start.addingTimeInterval(3600)
            let workout = WorkoutRecord(id: UUID().uuidString, startedAt: start, endedAt: max(longest, start), programDayId: nil,
                                        title: first.title, note: first.workoutNote, effort: nil, restEndsAt: nil, restDurationSeconds: nil,
                                        source: .app, externalId: "\(format.rawValue):\(Int(start.timeIntervalSince1970))")
            try workout.insert(db)
            report.inserted["workout", default: 0] += 1
            var order: [String] = []
            for s in sets where !order.contains(s.exercise) { order.append(s.exercise) }
            for (position, name) in order.enumerated() {
                let exerciseId = try exerciseIds[name] ?? exercise(named: name, in: db, now: now, report: &report)
                exerciseIds[name] = exerciseId
                let mine = sets.filter { $0.exercise == name }
                let we = WorkoutExerciseRecord(id: UUID().uuidString, workoutId: workout.id, exerciseId: exerciseId, position: position,
                                               dayExerciseId: nil, targetSets: nil, repMin: nil, repMax: nil, restSeconds: 90,
                                               note: mine.compactMap(\.note).first, externalId: nil)
                try we.insert(db)
                report.inserted["workoutExercise", default: 0] += 1
                var n = 0
                for s in mine {
                    guard s.reps > 0 else { report.skipped[SkipReason.setZeroReps.rawValue, default: 0] += 1; continue }
                    var set = WorkoutSetRecord(id: UUID().uuidString, workoutExerciseId: we.id, position: n,
                                               loadHundredths: s.load.map { Int(($0 * 100).rounded()) }, unit: s.unit, reps: s.reps,
                                               type: s.type, completedAt: start, rpe: s.rpe, externalId: nil)
                    set.note = nil
                    try set.insert(db)
                    n += 1
                    report.inserted["workoutSet", default: 0] += 1
                }
                if n == 0 { try we.delete(db); report.inserted["workoutExercise", default: 0] -= 1 }
            }
            if try WorkoutExerciseRecord.filter(Column("workoutId") == workout.id).fetchCount(db) == 0 {
                try workout.delete(db)
                report.inserted["workout", default: 0] -= 1
                report.skipped[SkipReason.workoutEmpty.rawValue, default: 0] += 1
            }
        }
        try ImportRunRecord(id: UUID().uuidString, source: format.rawValue, fileName: fileName, fileSHA256: fileSHA256,
                            ranAt: now, report: report).insert(db)
        return report
    }

    /// An existing exercise by name (case-insensitive, not archived), also trying Strong's
    /// "Bench Press (Barbell)" as "Barbell Bench Press"; otherwise a new custom exercise.
    static func exercise(named name: String, in db: Database, now: Date, report: inout ImportReport) throws -> String {
        var candidates = [name]
        if let open = name.lastIndex(of: "("), name.hasSuffix(")") {
            let base = name[..<open].trimmingCharacters(in: .whitespaces)
            let kind = name[name.index(after: open)..<name.index(before: name.endIndex)]
            candidates.append("\(kind) \(base)")
        }
        for candidate in candidates {
            if let id = try String.fetchOne(db, sql: """
                SELECT id FROM exercise WHERE isArchived = 0 AND lower(trim(name)) = lower(?) ORDER BY source = 'library' LIMIT 1
                """, arguments: [candidate]) { return id }
        }
        let lower = name.lowercased()
        let equipment: Equipment = lower.contains("barbell") ? .barbell : lower.contains("dumbbell") ? .dumbbell
            : lower.contains("cable") ? .cable : lower.contains("smith") ? .smith : lower.contains("kettlebell") ? .kettlebell
            : lower.contains("machine") ? .machine : .other
        let created = try ExerciseWrites.createCustom(db, draft: ExerciseDraft(name: name, equipment: equipment), now: now)
        report.inserted["exercise", default: 0] += 1
        report.unmappedExercises.append(name)
        return created.id
    }
}

private extension Int {
    var nonNegative: Int? { self >= 0 ? self : nil }
}
