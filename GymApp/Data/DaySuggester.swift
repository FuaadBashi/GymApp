import Foundation
import GRDB

nonisolated struct Slot: Equatable {
    let name: String
    let patterns: [MovementPattern]
}

nonisolated struct Suggestion: Identifiable, Equatable {
    let slot: Slot
    var exercise: ExerciseRecord?
    var alternatives: [ExerciseRecord]  // next 5 candidates, for swapping
    var reason: String
    var id: String { slot.name }
}

/// Fills a day from your own history, one exercise per movement slot (decision #21).
nonisolated enum DaySuggester {
    static func slots(for focus: DayFocus) -> [Slot] {
        let lower = [
            Slot(name: "Squat", patterns: [.squat]),
            Slot(name: "Hinge", patterns: [.hinge]),
            Slot(name: "Leg extension", patterns: [.kneeExtension]),
            Slot(name: "Leg curl", patterns: [.kneeFlexion]),
            Slot(name: "Single leg or glutes", patterns: [.lunge, .hipThrust]),
            Slot(name: "Calves", patterns: [.calfRaise]),
        ]
        switch focus {
        case .fullBody:
            return [
                Slot(name: "Squat", patterns: [.squat]),
                Slot(name: "Press", patterns: [.horizontalPush, .inclinePush]),
                Slot(name: "Vertical pull", patterns: [.verticalPull]),
                Slot(name: "Hinge or leg curl", patterns: [.hinge, .kneeFlexion]),
                Slot(name: "Row", patterns: [.horizontalPull]),
                Slot(name: "Overhead press", patterns: [.verticalPush]),
                Slot(name: "Leg extension", patterns: [.kneeExtension]),
                Slot(name: "Biceps", patterns: [.bicepsCurl]),
                Slot(name: "Triceps", patterns: [.tricepsExtension, .dip]),
            ]
        case .upper:
            return [
                Slot(name: "Press", patterns: [.horizontalPush, .inclinePush]),
                Slot(name: "Row", patterns: [.horizontalPull]),
                Slot(name: "Overhead press", patterns: [.verticalPush]),
                Slot(name: "Vertical pull", patterns: [.verticalPull]),
                Slot(name: "Side delts", patterns: [.lateralRaise]),
                Slot(name: "Biceps", patterns: [.bicepsCurl]),
                Slot(name: "Triceps", patterns: [.tricepsExtension, .dip]),
            ]
        case .lower:
            return lower
        case .push:
            return [
                Slot(name: "Flat press", patterns: [.horizontalPush]),
                Slot(name: "Incline press", patterns: [.inclinePush]),
                Slot(name: "Overhead press", patterns: [.verticalPush]),
                Slot(name: "Side delts", patterns: [.lateralRaise]),
                Slot(name: "Chest fly", patterns: [.chestFly]),
                Slot(name: "Triceps", patterns: [.tricepsExtension, .dip]),
            ]
        case .pull:
            return [
                Slot(name: "Vertical pull", patterns: [.verticalPull]),
                Slot(name: "Row", patterns: [.horizontalPull]),
                Slot(name: "Rear delts", patterns: [.rearDelt]),
                Slot(name: "Biceps", patterns: [.bicepsCurl]),
                Slot(name: "Traps or pullover", patterns: [.shrug, .pullover]),
            ]
        case .legs:
            return lower + [Slot(name: "Abs", patterns: [.coreFlexion])]
        case .custom:
            return []
        }
    }

    private struct Candidate {
        var exercise: ExerciseRecord
        var lastDoneAt: Date
        var sessionsThisYear: Int
        var inOtherDay: Bool
    }

    static func suggest(_ db: Database, dayId: String, now: Date) throws -> [Suggestion] {
        guard let day = try ProgramDayRecord.fetchOne(db, key: dayId) else { return [] }
        let inThisDay = Set(try String.fetchAll(db, sql: "SELECT exerciseId FROM dayExercise WHERE dayId = ?", arguments: [dayId]))
        let inOtherDays = Set(try String.fetchAll(db, sql: """
            SELECT de.exerciseId FROM dayExercise de JOIN programDay d ON d.id = de.dayId
            WHERE d.programId = ? AND d.id != ?
            """, arguments: [day.programId, dayId]))
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let rows = try Row.fetchAll(db, sql: """
            SELECT e.*, MAX(w.startedAt) AS lastDoneAt,
                   COUNT(DISTINCT CASE WHEN w.startedAt >= ? AND w.startedAt <= ? THEN w.id END) AS sessionsThisYear
            FROM exercise e
            JOIN workoutExercise we ON we.exerciseId = e.id
            JOIN workout w ON w.id = we.workoutId
            WHERE w.endedAt IS NOT NULL AND e.isArchived = 0 AND e.movementPattern IS NOT NULL
            GROUP BY e.id
            """, arguments: [yearAgo, now])
        let candidates = try rows.map { row in
            let exercise = try ExerciseRecord(row: row)
            return Candidate(exercise: exercise, lastDoneAt: row["lastDoneAt"], sessionsThisYear: row["sessionsThisYear"],
                             inOtherDay: inOtherDays.contains(exercise.id))
        }.filter { !inThisDay.contains($0.exercise.id) }

        var chosen = Set<String>()
        return slots(for: day.focus).map { slot in
            let ranked = candidates
                .filter { c in c.exercise.movementPattern.map(slot.patterns.contains) ?? false && !chosen.contains(c.exercise.id) }
                .sorted { a, b in
                    if a.inOtherDay != b.inOtherDay { return !a.inOtherDay }
                    if a.lastDoneAt != b.lastDoneAt { return a.lastDoneAt > b.lastDoneAt }
                    if a.sessionsThisYear != b.sessionsThisYear { return a.sessionsThisYear > b.sessionsThisYear }
                    return a.exercise.name.localizedCaseInsensitiveCompare(b.exercise.name) == .orderedAscending
                }
            guard let top = ranked.first else {
                return Suggestion(slot: slot, exercise: nil, alternatives: [], reason: "Nothing in your history for this movement.")
            }
            chosen.insert(top.exercise.id)
            return Suggestion(slot: slot, exercise: top.exercise, alternatives: ranked.dropFirst().prefix(5).map(\.exercise),
                              reason: reason(for: top))
        }
    }

    private static func reason(for c: Candidate) -> String {
        let date = c.lastDoneAt.formatted(.dateTime.day().month(.abbreviated))
        if !c.inOtherDay { return "Not in your other days · last done \(date)" }
        return "Last done \(date) · \(c.sessionsThisYear) session\(c.sessionsThisYear == 1 ? "" : "s") this year"
    }
}
