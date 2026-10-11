import Foundation
import GRDB

nonisolated enum JEFITImportError: LocalizedError, Equatable {
    case libraryNotSeeded
    case missingParent(String)

    var errorDescription: String? {
        switch self {
        case .libraryNotSeeded: "The exercise library must be loaded before importing."
        case .missingParent(let what): "The export refers to something it does not contain: \(what)."
        }
    }
}

/// Turns a JEFIT export into database rows, following docs/specs/00-foundation.md card 0.5.
/// tools/reference_import.py applies the same rules; the tests hold the two to the same numbers.
///
/// Idempotent: every row carries an externalId (exercises a fixed id), and rows that already
/// exist are counted, not written. Run it inside one write transaction so a failure leaves
/// nothing half-imported.
nonisolated enum JEFITImporter {
    static let lbToKg = 0.45359237

    static func run(_ export: JEFITExport, map: [JEFITMapEntry], in db: Database, now: Date,
                    fileName: String = "jefit-export.csv", fileSHA256: String = "") throws -> ImportReport {
        guard try ExerciseRecord.filter(Column("source") == ExerciseSource.library.rawValue).fetchCount(db) > 0 else {
            throw JEFITImportError.libraryNotSeeded
        }
        var run = Run(db: db, export: export, map: map, now: now)
        try run.exercises()
        try run.programs()
        try run.days()
        try run.dayExercises()
        run.setRows()
        try run.workouts()
        try run.notes()
        try run.bodyEntries()
        try run.favourites()
        try run.settings()
        run.wholeSections()

        let record = ImportRunRecord(id: UUID().uuidString, source: "jefit", fileName: fileName,
                                     fileSHA256: fileSHA256, ranAt: now, report: run.report)
        try record.insert(db)
        run.report.inserted["importRun", default: 0] += 1
        return run.report
    }

    private struct Run {
        let db: Database
        let export: JEFITExport
        let mapByKey: [String: JEFITMapEntry]
        let map: [JEFITMapEntry]
        let now: Date
        var report = ImportReport()

        // Built up as the run proceeds.
        var importedExerciseIds: Set<String> = []
        var programIdByRoutine: [String: String] = [:]
        var dayByJefitId: [String: ProgramDayRecord] = [:]
        var itemByJefitId: [String: DayExerciseRecord] = [:]
        var setRowsByLog: [String: [Int: [String: String]]] = [:]

        var setting: [String: String] { export.rows("SETTING", withColumn: "timer").first ?? [:] }
        var weightUnit: WeightUnit { trimmed(setting["mass"]) == "kg" ? .kg : .lb }

        init(db: Database, export: JEFITExport, map: [JEFITMapEntry], now: Date) {
            self.db = db
            self.export = export
            self.map = map
            self.mapByKey = Dictionary(map.map { ($0.jefitId, $0) }, uniquingKeysWith: { first, _ in first })
            self.now = now
        }

        mutating func skip(_ reason: SkipReason, _ count: Int = 1) {
            report.skipped[reason.rawValue, default: 0] += count
        }

        mutating func inserted(_ table: String) { report.inserted[table, default: 0] += 1 }
        mutating func present(_ table: String) { report.alreadyPresent[table, default: 0] += 1 }

        func existing<R: FetchableRecord & TableRecord>(_ type: R.Type) throws -> [String: R] {
            let rows = try R.filter(Column("externalId") != nil).fetchAll(db)
            var byExternal: [String: R] = [:]
            for row in rows {
                if let ext = (row as? any ExternallyIdentified)?.externalId { byExternal[ext] = row }
            }
            return byExternal
        }

        // MARK: 1. Exercises

        mutating func exercises() throws {
            let existingIds = Set(try String.fetchAll(db, sql: "SELECT id FROM exercise"))
            let libraryIds = Set(map.compactMap(\.libraryId))
            var instructions: [String: [String]] = [:]
            for row in try ExerciseRecord.filter(keys: libraryIds).fetchAll(db) {
                instructions[row.id] = row.instructions
            }
            let rest = Int(trimmed(setting["timer"])) ?? 60
            for entry in map {
                if entry.skipOnImport {
                    skip(.exerciseCardio)
                    continue
                }
                importedExerciseIds.insert(entry.exerciseId)
                if existingIds.contains(entry.exerciseId) {
                    present("exercise")
                    continue
                }
                let record = ExerciseRecord(
                    id: entry.exerciseId, name: entry.name, equipment: entry.equipment, loadMode: entry.loadMode,
                    primaryMuscles: entry.primaryMuscles, secondaryMuscles: entry.secondaryMuscles,
                    force: entry.force, mechanic: entry.mechanic, category: entry.category,
                    bodyRegion: entry.bodyRegion, movementPattern: entry.movementPattern,
                    instructions: entry.libraryId.flatMap { instructions[$0] } ?? [], source: .jefit,
                    libraryId: entry.libraryId, stickyNote: nil, defaultRestSeconds: min(max(rest, 0), 900),
                    preferredUnit: weightUnit, isFavorite: false, isArchived: false, createdAt: now)
                try record.insert(db)
                inserted("exercise")
            }
        }

        // MARK: 2–4. Programs, days, day exercises

        mutating func programs() throws {
            let existing = try existing(ProgramRecord.self)
            for row in export.rows("ROUTINES", withColumn: "difficulty") {
                let ext = "jefit:routine:\(row["_id"] ?? "")"
                if let found = existing[ext] {
                    programIdByRoutine[row["_id"] ?? ""] = found.id
                    present("program")
                    continue
                }
                let record = ProgramRecord(id: UUID().uuidString, name: trimmed(row["name"]), split: .custom,
                                           isActive: false, isArchived: true, sessionsPerWeekGoal: 3,
                                           source: .jefit, externalId: ext, createdAt: now)
                try record.insert(db)
                programIdByRoutine[row["_id"] ?? ""] = record.id
                inserted("program")
            }
        }

        mutating func days() throws {
            let existing = try existing(ProgramDayRecord.self)
            let rows = export.rows("ROUTINES", withColumn: "dayIndex")
            let byPackage = Dictionary(grouping: rows) { $0["package"] ?? "" }
            for (package, dayRows) in byPackage {
                let ordered = dayRows.sorted { numberPair($0, "sort_order") < numberPair($1, "sort_order") }
                for (position, row) in ordered.enumerated() {
                    let jefitId = row["_id"] ?? ""
                    let ext = "jefit:day:\(jefitId)"
                    if let found = existing[ext] {
                        dayByJefitId[jefitId] = found
                        present("programDay")
                        continue
                    }
                    guard let programId = programIdByRoutine[package] else {
                        throw JEFITImportError.missingParent("routine \(package) for day \(jefitId)")
                    }
                    let record = ProgramDayRecord(id: UUID().uuidString, programId: programId, name: trimmed(row["name"]),
                                                  focus: .custom, position: position, copiedFromDayId: nil, externalId: ext)
                    try record.insert(db)
                    dayByJefitId[jefitId] = record
                    inserted("programDay")
                }
            }
        }

        mutating func dayExercises() throws {
            let existing = try existing(DayExerciseRecord.self)
            var kept: [[String: String]] = []
            for row in export.rows("ROUTINES", withColumn: "exercisename") {
                guard let entry = mapByKey["\(row["belongSys"] ?? ""):\(row["exercise_id"] ?? "")"] else {
                    skip(.dayExerciseNeverLogged)
                    continue
                }
                if entry.skipOnImport {
                    skip(.dayExerciseCardio)
                    continue
                }
                kept.append(row)
            }
            for (dayJefitId, rows) in Dictionary(grouping: kept, by: { $0["belongplan"] ?? "" }) {
                let ordered = rows.sorted { numberPair($0, "mysort") < numberPair($1, "mysort") }
                for (position, row) in ordered.enumerated() {
                    let jefitId = row["_id"] ?? ""
                    let ext = "jefit:item:\(jefitId)"
                    if let found = existing[ext] {
                        itemByJefitId[jefitId] = found
                        present("dayExercise")
                        continue
                    }
                    guard let day = dayByJefitId[dayJefitId] else {
                        throw JEFITImportError.missingParent("day \(dayJefitId) for item \(jefitId)")
                    }
                    let reps = (row["targetrep"] ?? "").split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
                    let record = DayExerciseRecord(
                        id: UUID().uuidString, dayId: day.id,
                        exerciseId: "jefit:\(row["belongSys"] ?? ""):\(row["exercise_id"] ?? "")",
                        position: position,
                        targetSets: min(max(Int(trimmed(row["setcount"])) ?? 1, 1), 20),
                        repMin: reps.min() ?? 10, repMax: reps.max() ?? 10,
                        restSeconds: min(max(Int(trimmed(row["timer"])) ?? 60, 0), 900),
                        note: nil, externalId: ext)
                    try record.insert(db)
                    itemByJefitId[jefitId] = record
                    inserted("dayExercise")
                }
            }
        }

        // MARK: 5. Set rows

        mutating func setRows() {
            let logIds = Set(export.rows("EXERCISE LOGS", withColumn: "ename").compactMap { $0["_id"] })
            var seen: Set<String> = []
            for row in export.rows("EXERCISE SET LOGS", withColumn: "weight_lbs") {
                let log = row["exercise_log_id"] ?? ""
                let index = Int(trimmed(row["set_index"])) ?? 0
                if !seen.insert("\(log)#\(index)").inserted { skip(.setRowDuplicate) }
                guard logIds.contains(log) else {
                    skip(.setRowOrphan)
                    continue
                }
                setRowsByLog[log, default: [:]][index] = row  // the later row wins
            }
        }

        // MARK: 6. Workouts, workout exercises, sets

        private struct KeptSet { var load: Int?; var reps: Int; var type: SetType; var completedAt: Date }
        private struct KeptLog { var row: [String: String]; var entry: JEFITMapEntry; var item: DayExerciseRecord?; var sets: [KeptSet] }

        mutating func workouts() throws {
            let existingWorkouts = Set(try String.fetchAll(db, sql: "SELECT externalId FROM workout WHERE externalId IS NOT NULL"))
            let logsBySession = Dictionary(grouping: export.rows("EXERCISE LOGS", withColumn: "ename")) { $0["belongsession"] ?? "" }
            let sessions = export.rows("WORKOUT SESSIONS", withColumn: "starttime").enumerated()
                .sorted { (Int(trimmed($0.element["starttime"])) ?? 0, $0.offset) < (Int(trimmed($1.element["starttime"])) ?? 0, $1.offset) }
                .map(\.element)
            var unmapped: Set<String> = []

            for session in sessions {
                let sessionId = session["_id"] ?? ""
                let ext = "jefit:session:\(sessionId)"
                if existingWorkouts.contains(ext) {
                    present("workout")
                    continue
                }
                let start = Date(timeIntervalSince1970: TimeInterval(Int(trimmed(session["starttime"])) ?? 0))
                let logs = (logsBySession[sessionId] ?? []).sorted { (Int(trimmed($0["_id"])) ?? 0) < (Int(trimmed($1["_id"])) ?? 0) }

                var kept: [KeptLog] = []
                for log in logs {
                    let key = "\(log["belongSys"] ?? ""):\(log["eid"] ?? "")"
                    guard let entry = mapByKey[key] else {
                        skip(.logMissingFromMap)
                        let label = "\(key) \(trimmed(log["ename"]))"
                        if unmapped.insert(label).inserted { report.unmappedExercises.append(label) }
                        continue
                    }
                    if entry.skipOnImport {
                        skip(.logCardio)
                        continue
                    }
                    var sets: [KeptSet] = []
                    for raw in rawSets(log: log, sessionStart: start) {
                        guard raw.reps > 0 else {
                            skip(.setZeroReps)
                            continue
                        }
                        let load: Int?
                        if entry.importWeights == .drop {
                            load = entry.loadMode == .repsOnly ? nil : 0
                        } else {
                            let kg = entry.negateOnImport ? -raw.kg : raw.kg
                            // Half-to-even, as Python's round(): the reference must agree to the hundredth.
                            load = Int((kg * 100).rounded(.toNearestOrEven))
                        }
                        sets.append(KeptSet(load: load, reps: raw.reps, type: raw.type, completedAt: raw.completedAt))
                    }
                    guard !sets.isEmpty else {
                        skip(.logNoSetsLeft)
                        continue
                    }
                    kept.append(KeptLog(row: log, entry: entry, item: itemByJefitId[log["day_item_id"] ?? ""], sets: sets))
                }

                guard !kept.isEmpty else {
                    skip(logs.isEmpty ? .workoutEmpty : .workoutOnlyCardio)
                    continue
                }

                // The day most of its logs belong to; ties go to the earliest such log.
                var votes: [String: Int] = [:]
                for log in kept { if let day = log.item?.dayId { votes[day, default: 0] += 1 } }
                let top = votes.values.max()
                let dayId = top.flatMap { top in kept.compactMap(\.item?.dayId).first { votes[$0] == top } }
                let dayName = dayId.flatMap { id in dayByJefitId.values.first { $0.id == id }?.name }

                var end = Date(timeIntervalSince1970: TimeInterval(Int(trimmed(session["endtime"])) ?? 0))
                if end < start { end = start }
                let workout = WorkoutRecord(id: UUID().uuidString, startedAt: start, endedAt: end, programDayId: dayId,
                                            title: dayName ?? "Workout", note: nil, effort: nil, restEndsAt: nil,
                                            restDurationSeconds: nil, source: .jefit, externalId: ext)
                try workout.insert(db)
                inserted("workout")

                for (position, log) in kept.enumerated() {
                    let logId = log.row["_id"] ?? ""
                    let exercise = WorkoutExerciseRecord(
                        id: UUID().uuidString, workoutId: workout.id, exerciseId: log.entry.exerciseId,
                        position: position, dayExerciseId: log.item?.id, targetSets: log.item?.targetSets,
                        repMin: log.item?.repMin, repMax: log.item?.repMax, restSeconds: log.item?.restSeconds ?? 60,
                        note: nil, externalId: "jefit:log:\(logId)")
                    try exercise.insert(db)
                    inserted("workoutExercise")
                    for (n, set) in log.sets.enumerated() {
                        try WorkoutSetRecord(id: UUID().uuidString, workoutExerciseId: exercise.id, position: n,
                                             loadHundredths: set.load, unit: .kg, reps: set.reps, type: set.type,
                                             completedAt: set.completedAt, rpe: nil,
                                             externalId: "jefit:set:\(logId):\(n)").insert(db)
                        inserted("workoutSet")
                    }
                }
            }
        }

        /// Set rows are canonical where they exist (JEFIT_EXPORT.md trap 1); the summary string
        /// is the only record before December 2024.
        private func rawSets(log: [String: String], sessionStart: Date) -> [(kg: Double, reps: Int, type: SetType, completedAt: Date)] {
            if let rows = setRowsByLog[log["_id"] ?? ""] {
                return rows.keys.sorted().map { index in
                    let row = rows[index]!
                    let kg = (Double(trimmed(row["weight_lbs"])) ?? 0) * JEFITImporter.lbToKg
                    let type: SetType = switch trimmed(row["set_type"]) {
                    case "warm-up": .warmUp
                    case "failure": .failed
                    default: .working
                    }
                    let time = Date(timeIntervalSince1970: TimeInterval(Int(trimmed(row["log_time"])) ?? 0))
                    return (kg, Int(trimmed(row["reps"])) ?? 0, type, time)
                }
            }
            return (log["logs"] ?? "").split(separator: ",").map { token in
                let parts = token.split(separator: "x", maxSplits: 1)
                let kg = parts.count == 2 ? Double(parts[0]) ?? 0 : 0
                let reps = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
                return (kg, reps, .working, sessionStart)
            }
        }

        // MARK: 7. Notes

        mutating func notes() throws {
            let existing = Set(try String.fetchAll(db, sql: "SELECT externalId FROM exerciseNote WHERE externalId IS NOT NULL"))
            var newest: [String: (date: String, id: Int, text: String)] = [:]
            for row in export.rows("NOTES", withColumn: "mynote") {
                let eid = trimmed(row["eid"])
                let text = trimmed(row["mynote"])
                let exerciseId = "jefit:\(trimmed(row["belongSys"])):\(eid)"
                if eid.isEmpty || eid == "0" {
                    skip(.noteUnattached)
                } else if text.isEmpty {
                    skip(.noteEmpty)
                } else if !importedExerciseIds.contains(exerciseId) {
                    skip(.noteExerciseNotImported)
                } else {
                    let date = trimmed(row["mydate"])
                    let jefitId = Int(trimmed(row["_id"])) ?? 0
                    if let best = newest[exerciseId], (best.date, best.id) >= (date, jefitId) {} else {
                        newest[exerciseId] = (date, jefitId, text)
                    }
                    let ext = "jefit:note:\(row["_id"] ?? "")"
                    if existing.contains(ext) {
                        present("exerciseNote")
                        continue
                    }
                    try ExerciseNoteRecord(id: UUID().uuidString, exerciseId: exerciseId, date: date, text: text,
                                           source: .jefit, externalId: ext).insert(db)
                    inserted("exerciseNote")
                }
            }
            // Only where empty, so a re-import never overwrites an edited sticky note.
            for (exerciseId, note) in newest {
                try db.execute(sql: "UPDATE exercise SET stickyNote = ? WHERE id = ? AND stickyNote IS NULL",
                               arguments: [note.text, exerciseId])
            }
        }

        // MARK: 8–11. Body, favourites, settings, whole sections

        mutating func bodyEntries() throws {
            let existing = Set(try String.fetchAll(db, sql: "SELECT externalId FROM bodyEntry WHERE externalId IS NOT NULL"))
            let inches = trimmed(setting["length"]) == "inches"
            for row in export.rows("PROFILE", withColumn: "weight") {
                let ext = "jefit:profile:\(row["_id"] ?? "")"
                if existing.contains(ext) {
                    present("bodyEntry")
                    continue
                }
                let weight = Double(trimmed(row["weight"])) ?? 0
                let fat = Double(trimmed(row["fatpercent"])) ?? 0
                var measurements: [String: Double] = [:]
                for column in ["chest", "arms", "waist", "calves", "height", "hips", "thighs", "shoulders", "neck", "forearms"] {
                    guard let value = Double(trimmed(row[column])), value > 0 else { continue }
                    measurements["\(column)Cm"] = inches ? (value * 2.54 * 10).rounded() / 10 : value
                }
                try BodyEntryRecord(id: UUID().uuidString, date: trimmed(row["mydate"]),
                                    weightHundredths: weight > 0 ? Int((weight * 100).rounded(.toNearestOrEven)) : nil,
                                    weightUnit: weightUnit, bodyFatPercent: fat > 0 ? fat : nil,
                                    measurements: measurements, source: .jefit, externalId: ext).insert(db)
                inserted("bodyEntry")
            }
        }

        mutating func favourites() throws {
            let rows = export.rows("FAVORITE EXERCISES", withColumn: "exercise_id")
            let keys = Set(rows.map { "jefit:\(trimmed($0["belongSys"])):\(trimmed($0["exercise_id"]))" })
            for exerciseId in keys {
                if importedExerciseIds.contains(exerciseId) {
                    try db.execute(sql: "UPDATE exercise SET isFavorite = 1 WHERE id = ?", arguments: [exerciseId])
                } else {
                    skip(.favouriteNotImported)
                }
            }
        }

        func settings() throws {
            let values: [String: String] = [
                "defaultRestSeconds": String(Int(trimmed(setting["timer"])) ?? 60),
                "weightUnit": weightUnit.rawValue,
                "weekStartsOn": trimmed(setting["week_start"]) == "7" ? "sunday" : "monday",
                "lastTimeSource": trimmed(setting["lastlogs"]) == "1" ? "sameDay" : "anyWorkout",
            ]
            for (key, value) in values {
                try SettingRecord(key: key, value: value).insert(db, onConflict: .ignore)
            }
        }

        mutating func wholeSections() {
            func count(_ section: String) -> Int { export.sections[section]?.reduce(0) { $0 + $1.rows.count } ?? 0 }
            skip(.sectionCardioLogs, count("CARDIO LOGS"))
            skip(.sectionCardioExerciseLogs, count("CARDIO EXERCISE LOGS"))
            skip(.sectionRecords, count("EXERCISE RECORDS"))
        }

        private func numberPair(_ row: [String: String], _ column: String) -> (Int, Int) {
            (Int(trimmed(row[column])) ?? 0, Int(trimmed(row["_id"])) ?? 0)
        }
    }
}

nonisolated protocol ExternallyIdentified { var externalId: String? { get } }
extension ProgramRecord: ExternallyIdentified {}
extension ProgramDayRecord: ExternallyIdentified {}
extension DayExerciseRecord: ExternallyIdentified {}

nonisolated private func trimmed(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}
