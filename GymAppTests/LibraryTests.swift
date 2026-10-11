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
