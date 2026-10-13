import Foundation
import GRDB
import Testing
@testable import GymApp

struct LibraryTests {
    @Test func bothBundledFilesDecode() throws {
        #expect(try BundledExercises.library().count == 876)
        #expect(try BundledExercises.jefitMap().count == 199)
    }

    @Test func seedingInsertsTheLibraryOnce() throws {
        let db = try AppDatabase.inMemory()
        let first = try db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        let second = try db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        #expect(first == 876)
        #expect(second == 0)
        #expect(try db.reader.read { try ExerciseRecord.fetchCount($0) } == 876)
    }

    @Test func barbellSquatReadsBackClassified() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { _ = try LibrarySeeder.seed(in: $0, now: .now) }
        let squat = try #require(try db.reader.read { try ExerciseRecord.fetchOne($0, key: "lib:Barbell_Squat") })
        #expect(squat.equipment == .barbell)
        #expect(squat.loadMode == .total)
        #expect(squat.bodyRegion == .lower)
        #expect(squat.primaryMuscles == [.quadriceps])
        #expect(squat.source == .library)
    }

    @Test func everyMapLibraryIdExistsInTheLibrary() throws {
        let ids = Set(try BundledExercises.library().map(\.id))
        let missing = try BundledExercises.jefitMap().compactMap(\.libraryId).filter { !ids.contains($0) }
        #expect(missing.isEmpty)
    }
}

struct LibraryLinkTests {
    @Test func existingImportsGainNewLinksWithoutOverridingAny() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try LibrarySeeder.seed(in: db, now: .now)
            // As imported before the map knew these links.
            try TestData.exercise(db, id: "jefit:1:2", name: "Barbell Bench Press", source: .jefit)
            try TestData.exercise(db, id: "jefit:1:86", name: "Cable Lat Pulldown (Wide Grip)", libraryId: "lib:Barbell_Squat", source: .jefit)
        }
        let linked = try db.writer.write { try LibrarySeeder.linkImported(in: $0) }
        #expect(linked == 1)
        let bench = try #require(try db.reader.read { try ExerciseRecord.fetchOne($0, key: "jefit:1:2") })
        #expect(bench.libraryId == "lib:Barbell_Bench_Press_-_Medium_Grip")
        #expect(!bench.instructions.isEmpty)
        // An existing link is left alone.
        #expect(try db.reader.read { try ExerciseRecord.fetchOne($0, key: "jefit:1:86") }?.libraryId == "lib:Barbell_Squat")
        // The library twin no longer shows beside it.
        let ids = Set(try db.reader.read { try ExerciseQueries.browse($0, filter: ExerciseFilter(searchText: "bench press")) }.map(\.id))
        #expect(ids.contains("jefit:1:2") && !ids.contains("lib:Barbell_Bench_Press_-_Medium_Grip"))
        // Running again changes nothing.
        #expect(try db.writer.write { try LibrarySeeder.linkImported(in: $0) } == 0)
    }
}
