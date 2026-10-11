import Foundation

nonisolated struct ImportReport: Codable, Hashable {
    var inserted: [String: Int] = [:]        // table name → rows inserted
    var alreadyPresent: [String: Int] = [:]  // table name → rows skipped because they exist
    var skipped: [String: Int] = [:]         // SkipReason.rawValue → count
    var unmappedExercises: [String] = []     // "belongSys:eid name" not in the map
}

/// Character for character the reasons tools/reference_import.py reports, so the two can be
/// compared directly.
nonisolated enum SkipReason: String, CaseIterable {
    case exerciseCardio = "exercise: cardio, not supported yet"
    case dayExerciseCardio = "dayExercise: cardio, not supported yet"
    case dayExerciseNeverLogged = "dayExercise: exercise never logged, so not in the exercise map"
    case logCardio = "exercise log: cardio, not supported yet"
    case logMissingFromMap = "exercise log: exercise missing from the map"
    case logNoSetsLeft = "exercise log: no sets left"
    case setZeroReps = "set: zero reps"
    case setRowOrphan = "set row: no matching exercise log"
    case setRowDuplicate = "set row: duplicate set index, later row kept"
    case workoutEmpty = "workout: empty in JEFIT (no exercises logged)"
    case workoutOnlyCardio = "workout: only cardio or empty exercise logs"
    case noteUnattached = "note: not attached to an exercise"
    case noteEmpty = "note: empty"
    case noteExerciseNotImported = "note: exercise not imported"
    case favouriteNotImported = "favourite: exercise not imported"
    case sectionCardioLogs = "section: CARDIO LOGS, not supported yet"
    case sectionCardioExerciseLogs = "section: CARDIO EXERCISE LOGS, not supported yet"
    case sectionRecords = "section: EXERCISE RECORDS, derived instead (rulebook §5)"
}
