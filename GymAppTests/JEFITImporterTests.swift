import Foundation
import GRDB
import Testing
@testable import GymApp

/// The importer is held to the numbers tools/reference_import.py produces from the same file.
struct JEFITImporterTests {
    private func importing(_ url: URL, into db: AppDatabase? = nil) throws -> (AppDatabase, ImportReport) {
        let db = try db ?? AppDatabase.inMemory()
        let export = try JEFITExport(data: Data(contentsOf: url))
        let map = try BundledExercises.jefitMap()
        let report = try db.writer.write { db in
            try LibrarySeeder.seed(in: db, now: .now)
            return try JEFITImporter.run(export, map: map, in: db, now: .now)
        }
        return (db, report)
    }

    private func expected(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func counts(_ db: AppDatabase) throws -> [String: Int] {
        let queries = [
            "exercise": "SELECT COUNT(*) FROM exercise WHERE source = 'jefit'",
            "program": "SELECT COUNT(*) FROM program",
            "programDay": "SELECT COUNT(*) FROM programDay",
            "dayExercise": "SELECT COUNT(*) FROM dayExercise",
            "workout": "SELECT COUNT(*) FROM workout",
            "workoutExercise": "SELECT COUNT(*) FROM workoutExercise",
            "workoutSet": "SELECT COUNT(*) FROM workoutSet",
            "exerciseNote": "SELECT COUNT(*) FROM exerciseNote",
            "bodyEntry": "SELECT COUNT(*) FROM bodyEntry",
            "workoutsLinkedToADay": "SELECT COUNT(*) FROM workout WHERE programDayId IS NOT NULL",
            "exercisesWithStickyNote": "SELECT COUNT(*) FROM exercise WHERE stickyNote IS NOT NULL",
            "favoriteExercises": "SELECT COUNT(*) FROM exercise WHERE isFavorite = 1",
        ]
        return try db.reader.read { db in try queries.mapValues { try Int.fetchOne(db, sql: $0)! } }
    }

    private func nonZero(_ dict: [String: Int]) -> [String: Int] { dict.filter { $0.value != 0 } }

    /// [(loadHundredths, reps, type)] for one exercise in one workout, in order.
    private func sets(_ db: AppDatabase, workoutExternalId: String? = nil, exerciseId: String) throws -> [[AnyHashable?]] {
        try db.reader.read { db in
            var sql = """
                SELECT s.loadHundredths, s.reps, s.type FROM workoutSet s
                JOIN workoutExercise we ON we.id = s.workoutExerciseId
                JOIN workout w ON w.id = we.workoutId
                WHERE we.exerciseId = ?
                """
            var args: [any DatabaseValueConvertible] = [exerciseId]
            if let workoutExternalId { sql += " AND w.externalId = ?"; args.append(workoutExternalId) }
            sql += " ORDER BY w.startedAt, we.position, s.position"
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map {
                [$0["loadHundredths"] as Int?, $0["reps"] as Int, $0["type"] as String]
            }
        }
    }

    // MARK: Mini fixture

    @Test func theMiniFixtureMatchesTheReference() throws {
        let (db, report) = try importing(Fixtures.mini)
        let want = try expected(Fixtures.miniExpected)
        #expect(try counts(db) == want["counts"] as? [String: Int])
        #expect(nonZero(report.skipped) == nonZero(want["skips"] as? [String: Int] ?? [:]))
    }

    @Test func theMiniFixtureImportsTheTrickyRowsCorrectly() throws {
        let (db, _) = try importing(Fixtures.mini)
        #expect(try sets(db, exerciseId: "jefit:1:149") == [[2700, 15, "warmUp"], [4500, 10, "failed"]])
        #expect(try sets(db, exerciseId: "jefit:1:2") == [[4000, 5, "working"], [6000, 3, "working"]])
        #expect(try sets(db, exerciseId: "jefit:1:1262") == [[-4500, 6, "working"]])
        #expect(try sets(db, exerciseId: "jefit:1:690") == [[nil, 7, "working"]])
        let bench = try #require(try db.reader.read { try ExerciseRecord.fetchOne($0, key: "jefit:1:2") })
        #expect(bench.stickyNote == "Newer note")
        #expect(bench.isFavorite)
        let workout = try #require(try db.reader.read { try WorkoutRecord.fetchOne($0) })
        #expect(workout.title == "Day A\nwith a newline")
        let day = try db.reader.read { try ProgramDayRecord.fetchOne($0, key: workout.programDayId ?? "") }
        #expect(day?.externalId == "jefit:day:10")
    }

    @Test func importingTwiceChangesNothing() throws {
        let (db, _) = try importing(Fixtures.mini)
        let before = try counts(db)
        let (_, second) = try importing(Fixtures.mini, into: db)
        #expect(try counts(db) == before)
        #expect(second.alreadyPresent["workout"] == 1)
        #expect(second.inserted.filter { $0.value > 0 }.keys.sorted() == ["importRun"])
    }

    /// The app imports off the main actor; the other tests import on it. This one goes through
    /// ImportService so isolation bugs (a protocol cast that fails off the main actor did once)
    /// show up here rather than on the phone.
    @Test func importingTwiceThroughTheBackgroundServiceChangesNothing() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        _ = try await ImportService.importJEFIT(fileAt: Fixtures.mini, into: db)
        let before = try counts(db)
        let second = try await ImportService.importJEFIT(fileAt: Fixtures.mini, into: db)
        #expect(try counts(db) == before)
        #expect(second.alreadyPresent["program"] == 1)
        #expect(second.alreadyPresent["workout"] == 1)
        #expect(second.inserted.filter { $0.value > 0 }.keys.sorted() == ["importRun"])
    }

    @Test func importingWithoutTheLibraryFails() throws {
        let db = try AppDatabase.inMemory()
        let export = try JEFITExport(data: Data(contentsOf: Fixtures.mini))
        #expect(throws: JEFITImportError.libraryNotSeeded) {
            try db.writer.write { try JEFITImporter.run(export, map: try BundledExercises.jefitMap(), in: $0, now: .now) }
        }
    }

    // MARK: Real export

    @Test(.enabled(if: Fixtures.hasRealExport))
    func theRealExportMatchesTheReference() throws {
        let clock = ContinuousClock()
        var result: (AppDatabase, ImportReport)?
        let elapsed = try clock.measure { result = try importing(Fixtures.realExport) }
        let (db, report) = try #require(result)
        let want = try expected(Fixtures.realExpected)

        #expect(elapsed < .seconds(10))
        #expect(try counts(db) == want["counts"] as? [String: Int])
        #expect(nonZero(report.skipped) == nonZero(want["skips"] as? [String: Int] ?? [:]))
        #expect(report.unmappedExercises.isEmpty)

        for (name, value) in try #require(want["workouts"] as? [String: [String: Any]]) {
            let ext = try #require(value["externalId"] as? String)
            let workout = try #require(try db.reader.read { try WorkoutRecord.filter(Column("externalId") == ext).fetchOne($0) }, "\(name)")
            #expect(Int(workout.startedAt.timeIntervalSince1970) == value["startedAt"] as? Int, "\(name)")
            #expect(Int(workout.endedAt?.timeIntervalSince1970 ?? 0) == value["endedAt"] as? Int, "\(name)")
            let dayExt = try db.reader.read { try ProgramDayRecord.fetchOne($0, key: workout.programDayId ?? "")?.externalId }
            #expect(dayExt == value["programDayExternalId"] as? String, "\(name)")
            let exercises = try db.reader.read {
                try WorkoutExerciseRecord.filter(Column("workoutId") == workout.id).order(Column("position")).fetchAll($0)
            }
            let wantExercises = try #require(value["exercises"] as? [[String: Any]])
            #expect(exercises.map(\.exerciseId) == wantExercises.map { $0["exerciseId"] as? String ?? "" }, "\(name)")
            for wantExercise in wantExercises {
                let id = wantExercise["exerciseId"] as? String ?? ""
                let wantSets = (wantExercise["sets"] as? [[Any]] ?? []).map { row in
                    [row[0] as? Int as AnyHashable?, row[1] as? Int as AnyHashable?, row[2] as? String as AnyHashable?]
                }
                #expect(try sets(db, workoutExternalId: ext, exerciseId: id) == wantSets, "\(name) \(id)")
            }
        }

        for (id, value) in try #require(want["exercises"] as? [String: [String: Any]]) {
            let all = try sets(db, exerciseId: id)
            #expect(all.count == value["sets"] as? Int, "\(id)")
            let loads = all.map { $0[0] as? Int }
            if let heaviest = value["heaviestHundredths"] as? Int, let best = value["bestE1RMKg"] as? Double {
                let pastSets = all.map {
                    PastSet(kg: Double($0[0] as? Int ?? 0) / 100, reps: $0[1] as? Int ?? 0, type: SetType(rawValue: $0[2] as? String ?? "") ?? .working)
                }
                let bests = TrainingMath.bests(pastSets, loadMode: .total)
                #expect(Int(((bests.heaviestKg ?? 0) * 100).rounded()) == heaviest, "\(id)")
                #expect(((bests.bestE1RM ?? 0) * 100).rounded() / 100 == best, "\(id)")
            }
            if value["allLoadsNegative"] as? Bool == true { #expect(loads.allSatisfy { ($0 ?? 0) < 0 }, "\(id)") }
            if value["allLoadsNull"] as? Bool == true { #expect(loads.allSatisfy { $0 == nil }, "\(id)") }
            if value["allLoadsZero"] as? Bool == true { #expect(loads.allSatisfy { $0 == 0 }, "\(id)") }
        }
    }
}
