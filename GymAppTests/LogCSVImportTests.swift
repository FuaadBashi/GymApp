import Foundation
import GRDB
import Testing
@testable import GymApp

/// CORE_JOBS item 5: Strong and Hevy workout CSVs.
struct LogCSVImportTests {
    let utc = TimeZone(identifier: "UTC")!

    static let strong = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
    2024-03-01 18:00:00,Push,1h 5m,Bench Press (Barbell),W,40,10,0,0,,"Felt good, slept well",
    2024-03-01 18:00:00,Push,1h 5m,Bench Press (Barbell),1,80,8,0,0,,"Felt good, slept well",8
    2024-03-01 18:00:00,Push,1h 5m,Bench Press (Barbell),2,80,0,0,0,,"Felt good, slept well",
    2024-03-01 18:00:00,Push,1h 5m,Cable Fly,1,15,12,0,0,slow,"Felt good, slept well",
    2024-03-03 09:30:00,Legs,45m,Squat (Barbell),1,100,5,0,0,,,

    """

    static let hevy = """
    "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_miles","duration_seconds","rpe"
    "Upper","15 Jul 2026, 09:52","15 Jul 2026, 10:40","","Lat Pulldown (Cable)","","","0","warmup","50","12","","",""
    "Upper","15 Jul 2026, 09:52","15 Jul 2026, 10:40","","Lat Pulldown (Cable)","","","1","normal","120","10","","","9"
    "Upper","15 Jul 2026, 09:52","15 Jul 2026, 10:40","","Lat Pulldown (Cable)","","","2","dropset","90","8","","",""

    """

    private func database() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try TestData.exercise(db, id: "lib-bench", name: "Barbell Bench Press", source: .library)
        }
        return db
    }

    @Test func strongRowsBecomeWorkoutsWithTheirTypesAndNotes() throws {
        let (format, rows) = try LogCSVImporter.parse(Data(Self.strong.utf8), timeZone: utc)
        #expect(format == .strong && rows.count == 5)
        #expect(rows[0].type == .warmUp && rows[0].workoutNote == "Felt good, slept well")
        #expect(rows[1].rpe == 8)
        let db = try database()
        let report = try db.writer.write { try LogCSVImporter.run(format, rows, in: $0, now: .now, fileName: "s.csv", fileSHA256: "") }
        #expect(report.inserted["workout"] == 2)
        #expect(report.inserted["workoutSet"] == 4)
        #expect(report.skipped[SkipReason.setZeroReps.rawValue] == 1)
        try db.reader.read { db in
            // "Bench Press (Barbell)" found the library's "Barbell Bench Press"; the others are new.
            #expect(try WorkoutExerciseRecord.filter(Column("exerciseId") == "lib-bench").fetchCount(db) == 1)
            #expect(try ExerciseRecord.filter(Column("source") == "custom").fetchCount(db) == 2)
            let push = try #require(try WorkoutRecord.filter(Column("title") == "Push").fetchOne(db))
            #expect(push.endedAt!.timeIntervalSince(push.startedAt) == 3900)
            #expect(push.externalId?.hasPrefix("strong:") == true && push.source == .app)
        }
    }

    @Test func hevyPoundsStayPoundsAndSetTypesMap() throws {
        let (format, rows) = try LogCSVImporter.parse(Data(Self.hevy.utf8), timeZone: utc)
        #expect(format == .hevy)
        #expect(rows.map(\.type) == [.warmUp, .working, .drop])
        #expect(rows.allSatisfy { $0.unit == .lb } && rows[1].load == 120 && rows[1].rpe == 9)
        let db = try database()
        try db.writer.write { _ = try LogCSVImporter.run(format, rows, in: $0, now: .now, fileName: "h.csv", fileSHA256: "") }
        let w = try #require(try db.reader.read { try WorkoutRecord.fetchOne($0) })
        #expect(w.endedAt!.timeIntervalSince(w.startedAt) == 48 * 60)
        #expect(try db.reader.read { try Int.fetchOne($0, sql: "SELECT loadHundredths FROM workoutSet WHERE type = 'working'") } == 12000)
    }

    @Test func importingTwiceAddsNothing() throws {
        let (format, rows) = try LogCSVImporter.parse(Data(Self.strong.utf8), timeZone: utc)
        let db = try database()
        try db.writer.write { _ = try LogCSVImporter.run(format, rows, in: $0, now: .now, fileName: "s.csv", fileSHA256: "") }
        let again = try db.writer.write { try LogCSVImporter.run(format, rows, in: $0, now: .now, fileName: "s.csv", fileSHA256: "") }
        #expect(again.inserted["workout"] == nil && again.alreadyPresent["workout"] == 2)
        #expect(try db.reader.read { try WorkoutSetRecord.fetchCount($0) } == 4)
    }

    /// GymApp's own export reads back as the same sets, and onto itself as already present.
    @Test func gymAppExportRoundTrips() throws {
        let source = try AppDatabase.inMemory()
        try source.writer.write { db in
            try TestData.exercise(db, id: "row", name: "Seated Row")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("row", [(52.5, 10), (55, 8)])])
        }
        let csv = try source.reader.read { try CSVExport.csv($0, calendar: { var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c }()) }
        let (format, rows) = try LogCSVImporter.parse(Data(csv.utf8), timeZone: utc)
        #expect(format == .strong)
        let onto = try source.writer.write { try LogCSVImporter.run(format, rows, in: $0, now: .now, fileName: "x.csv", fileSHA256: "") }
        #expect(onto.alreadyPresent["workout"] == 1 && onto.inserted["workout"] == nil)

        let fresh = try AppDatabase.inMemory()
        try fresh.writer.write { _ = try LogCSVImporter.run(format, rows, in: $0, now: .now, fileName: "x.csv", fileSHA256: "") }
        let sets = try fresh.reader.read { try WorkoutSetRecord.order(Column("position")).fetchAll($0) }
        #expect(sets.map(\.loadHundredths) == [5250, 5500] && sets.map(\.reps) == [10, 8])
    }

    @Test func otherFilesAreRefusedClearly() throws {
        #expect(throws: LogCSVImportError.unrecognised) { try LogCSVImporter.parse(Data("a,b,c\n1,2,3\n".utf8)) }
        let badDate = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\nyesterday,W,1h,Bench,1,50,5\n"
        #expect(throws: LogCSVImportError.badRow(2, "no readable date")) { try LogCSVImporter.parse(Data(badDate.utf8)) }
    }

    @Test func durationsAndDatesParse() {
        #expect(LogCSVImporter.duration("1h 5m") == 3900)
        #expect(LogCSVImporter.duration("45m") == 2700)
        #expect(LogCSVImporter.duration("soon") == nil)
        #expect(LogCSVImporter.date("2024-03-01 18:00:00", utc) != nil)
        #expect(LogCSVImporter.date("15 Jul 2026, 09:52", utc) != nil)
    }

    /// Review of phase 10: a Strong file with a bad row reports that row, not a JEFIT error.
    @Test func aBrokenStrongFileIsNotHandedToTheJEFITImporter() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".csv")
        try Data("Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\nyesterday,W,1h,Bench,1,50,5\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: LogCSVImportError.badRow(2, "no readable date")) {
            try await ImportService.importFile(at: url, into: try AppDatabase.inMemory())
        }
    }

    @Test func strongSetNotesStayOnTheirSets() throws {
        let (format, rows) = try LogCSVImporter.parse(Data(Self.strong.utf8), timeZone: utc)
        let db = try database()
        try db.writer.write { _ = try LogCSVImporter.run(format, rows, in: $0, now: .now, fileName: "s.csv", fileSHA256: "") }
        #expect(try db.reader.read { try String.fetchAll($0, sql: "SELECT note FROM workoutSet WHERE note IS NOT NULL") } == ["slow"])
    }
}
