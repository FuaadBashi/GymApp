import Foundation
import GRDB
import Testing
@testable import GymApp

/// Rulebook §13 against the studio's next_target on the owner's real history. Needs
/// data/next_cross_check.json from tools/cross_check_next.py and the backup it names; skips
/// without them (data/ is never committed).
struct NextSetCrossCheckTests {
    struct Expected: Decodable {
        struct Target: Decodable { var kind: String; var weight: Double; var unit: String; var reps: Int; var today: String }
        var backup: String
        var range: [Int]
        var exercises: [String: Target]
    }

    static let data = Fixtures.folder.deletingLastPathComponent().deletingLastPathComponent().appending(path: "data")
    static let expectedURL = data.appending(path: "next_cross_check.json")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: expectedURL.path)))
    func appAndStudioAgreeOnEveryLift() throws {
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: Self.expectedURL))
        // Work on a copy: a WAL-mode file can't be opened read-only without its side files.
        let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite")
        try FileManager.default.copyItem(at: Self.data.appending(path: "backups/\(expected.backup)"), to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let queue = try DatabaseQueue(path: copy.path)
        var compared = 0, skippedComeback = 0
        var mismatches: [String] = []
        try queue.read { db in
            for (id, target) in expected.exercises.sorted(by: { $0.key < $1.key }) {
                guard let exercise = try ExerciseRecord.fetchOne(db, key: id),
                      let today = ISO8601DateFormatter().date(from: target.today) else { continue }
                let sessions = try ExerciseQueries.sessions(db, exerciseId: id)
                let loads = sessions.flatMap(\.sets).compactMap { s in s.loadHundredths.map { Load(hundredths: $0, unit: s.unit).kg } }
                guard let app = NextSet.suggest(sessions: sessions, repRange: expected.range[0]...expected.range[1],
                                                stepKg: TrainingMath.step(loads: loads), loadMode: exercise.loadMode, now: today) else {
                    mismatches.append("\(exercise.name): studio \(target.kind), app none")
                    continue
                }
                if app.kind == .comeback { skippedComeback += 1; continue }
                compared += 1
                let weight = Double(app.loadHundredths) / 100
                if app.kind.rawValue != target.kind || abs(weight - target.weight) > 0.01 || app.reps != target.reps || app.unit.rawValue != target.unit {
                    mismatches.append("\(exercise.name): studio \(target.kind) \(target.weight)\(target.unit) × \(target.reps), app \(app.kind.rawValue) \(weight)\(app.unit.rawValue) × \(app.reps)")
                }
            }
        }
        print("§13 cross-check: \(compared) compared, \(skippedComeback) comebacks skipped, \(mismatches.count) differ")
        for m in mismatches { print("  " + m) }
        #expect(compared > 0)
        #expect(mismatches.isEmpty, "\(mismatches.count) lifts differ; see the test log")
    }
}
