import Foundation
import GRDB
import Testing
@testable import GymApp

struct CSVExportTests {
    let db = try! AppDatabase.inMemory()
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Splits RFC 4180 text into rows of fields.
    private func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\r\n" || c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else if c == "\r" { continue }
            else { field.append(c) }
        }
        return rows
    }

    @Test func theHeaderStartsWithStrongsColumns() throws {
        let rows = parse(try db.reader.read { try CSVExport.csv($0, calendar: utc) })
        #expect(rows.count == 1)
        #expect(Array(rows[0].prefix(12)) == ["Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight", "Reps",
                                              "Distance", "Seconds", "Notes", "Workout Notes", "RPE"])
        #expect(rows[0].count == CSVExport.header.count)
    }

    @Test func rowsCoverSetTypesLoadModesAndQuoting() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench", name: "Bench, flat")
            try TestData.exercise(db, id: "pullup", name: "Assisted pull-up", loadMode: .bodyweightPlus)
            try TestData.exercise(db, id: "plank", name: "Push-up", loadMode: .repsOnly)
            let w = try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5),
                                                 exercises: [("bench", [(20, 10), (62.5, 8), (40, 6)]), ("pullup", [(-45, 6)]), ("plank", [(0, 20)])])
            try db.execute(sql: "UPDATE workoutSet SET type = 'warmUp' WHERE loadHundredths = 2000")
            try db.execute(sql: "UPDATE workoutSet SET type = 'drop', note = 'grip \"slipped\", ok' WHERE loadHundredths = 4000")
            try db.execute(sql: "UPDATE workoutSet SET loadHundredths = NULL WHERE reps = 20")
            try WorkoutWrites.setNoteAndEffort(db, workoutId: w.id, note: "Good day", effort: 8)
            _ = try WorkoutWrites.start(db, dayId: nil, settings: AppSettings(), now: TestData.day(6))   // unfinished: excluded
        }
        let rows = parse(try db.reader.read { try CSVExport.csv($0, calendar: utc) }).dropFirst()
        #expect(rows.count == 5)
        let col = { (name: String) in CSVExport.header.firstIndex(of: name)! }
        let bench = rows.filter { $0[col("Exercise Name")] == "Bench, flat" }
        #expect(bench.map { $0[col("Set Order")] } == ["W", "1", "D"])
        #expect(bench.map { $0[col("Weight")] } == ["20", "62.5", "40"])
        #expect(bench[2][col("Notes")] == "grip \"slipped\", ok")
        #expect(bench[0][col("Workout Notes")] == "Good day" && bench[0][col("Effort")] == "8")
        #expect(bench[0][col("Duration")] == "1h 0m")
        let expectedDate = TestData.day(5).formatted(Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            timeZone: utc.timeZone, calendar: utc))
        #expect(bench[0][col("Date")] == expectedDate)
        #expect(bench[0][col("Date")].wholeMatch(of: /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/) != nil)
        let pull = try #require(rows.first { $0[col("Exercise Name")] == "Assisted pull-up" })
        #expect(pull[col("Weight")] == "-45" && pull[col("Load Mode")] == "bodyweightPlus")
        let pushup = try #require(rows.first { $0[col("Exercise Name")] == "Push-up" })
        #expect(pushup[col("Weight")] == "" && pushup[col("Reps")] == "20")
        #expect(rows.allSatisfy { $0.count == CSVExport.header.count })
    }

    @Test func theFileIsWrittenAsUTF8WithoutABOM() throws {
        let url = try db.reader.read { try CSVExport.write($0, now: TestData.day(3)) }
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent == "GymApp-sets-\(DayString.from(TestData.day(3))).csv")
        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(4)) == Array("Date".utf8))
    }

    @Test func decimalsUseADotWhateverTheLocale() {
        #expect(CSVExport.decimal(6250) == "62.5")
        #expect(CSVExport.decimal(125) == "1.25")
        #expect(CSVExport.decimal(-4500) == "-45")
        #expect(CSVExport.decimal(5) == "0.05")
    }

    @Test(.enabled(if: Fixtures.hasRealExport))
    func everyImportedSetIsExported() async throws {
        try await db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        _ = try await ImportService.importJEFIT(fileAt: Fixtures.realExport, into: db)
        let text = try await db.reader.read { try CSVExport.csv($0) }
        let rows = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count - 1
        #expect(rows == 7751)
    }
}
