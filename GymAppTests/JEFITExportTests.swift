import Foundation
import Testing
@testable import GymApp

struct JEFITExportTests {
    @Test func theMiniFixtureSplitsIntoTheExpectedTables() throws {
        let export = try JEFITExport(data: Data(contentsOf: Fixtures.mini))
        let counts = export.sections.mapValues { $0.map(\.rows.count) }
        #expect(counts == [
            "SETTING": [1], "PROFILE": [1], "ROUTINES": [1, 1, 2], "WORKOUT SESSIONS": [2],
            "EXERCISE LOGS": [5], "EXERCISE SET LOGS": [7], "EXERCISE RECORDS": [1],
            "FAVORITE EXERCISES": [1], "NOTES": [3],
            "CARDIO LOGS": [], "CARDIO EXERCISE LOGS": [], "CUSTOM EXERCISES": [],
        ])
    }

    @Test func quotedFieldsKeepTheirNewlinesAndQuotes() throws {
        let export = try JEFITExport(data: Data(contentsOf: Fixtures.mini))
        #expect(export.rows("ROUTINES", withColumn: "dayIndex").first?["name"] == "Day A\nwith a newline")
        #expect(export.rows("NOTES", withColumn: "mynote").first?["mynote"] == "Seat level 4\nKeep elbows \"tucked\"")
    }

    @Test func rowsAreFoundByAColumnInTheirHeader() throws {
        let export = try JEFITExport(data: Data(contentsOf: Fixtures.mini))
        #expect(export.rows("EXERCISE LOGS", withColumn: "ename").count == 5)
        #expect(export.rows("EXERCISE LOGS", withColumn: "no such column").isEmpty)
    }

    @Test(.enabled(if: Fixtures.hasRealExport))
    func theRealExportHasTheDocumentedRowCounts() throws {
        let export = try JEFITExport(data: Data(contentsOf: Fixtures.realExport))
        let counts = export.sections.mapValues { $0.map(\.rows.count) }
        #expect(counts["PROFILE"] == [66])
        #expect(counts["ROUTINES"] == [2, 32, 198])
        #expect(counts["WORKOUT SESSIONS"] == [492])
        #expect(counts["EXERCISE LOGS"] == [2552])
        #expect(counts["EXERCISE SET LOGS"] == [1934])
        #expect(counts["EXERCISE RECORDS"] == [203])
        #expect(counts["CARDIO LOGS"] == [25])
        #expect(counts["CARDIO EXERCISE LOGS"] == [12])
        #expect(counts["CUSTOM EXERCISES"] == [6])
        #expect(counts["FAVORITE EXERCISES"] == [3])
        #expect(counts["NOTES"] == [247])
    }

    @Test func aPlainCSVIsNotAJEFITExport() {
        #expect(throws: JEFITExportError.notAJEFITExport) { try JEFITExport(data: Data("a,b\n1,2\n".utf8)) }
    }
}
