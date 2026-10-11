import Foundation
import GRDB
import Testing
@testable import GymApp

struct DataLayerTests {
    let db = try! AppDatabase.inMemory()

    // MARK: Browse

    @Test func theUsersVersionHidesItsLibraryDuplicate() throws {
        try db.writer.write { db in
            try LibrarySeeder.seed(in: db, now: .now)
            try TestData.exercise(db, id: "jefit:1:12", name: "Barbell Squat", libraryId: "lib:Barbell_Squat", source: .jefit)
        }
        let ids = Set(try db.reader.read { try ExerciseQueries.browse($0, filter: ExerciseFilter()) }.map(\.id))
        #expect(!ids.contains("lib:Barbell_Squat"))
        #expect(ids.contains("jefit:1:12"))
    }

    @Test func everySearchTermMustMatch() throws {
        try db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        let names = Set(try db.reader.read { try ExerciseQueries.browse($0, filter: ExerciseFilter(searchText: "incl bench")) }.map(\.exercise.name))
        #expect(names.contains("Barbell Incline Bench Press - Medium Grip"))
        #expect(names.contains("Smith Machine Incline Bench Press"))
        #expect(!names.contains("Barbell Bench Press - Medium Grip"))
    }

    @Test func exercisesWithHistoryComeFirstNewestFirst() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a", name: "A")
            try TestData.exercise(db, id: "b", name: "B")
            try TestData.exercise(db, id: "c", name: "C")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("a", [(50, 8)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5), exercises: [("b", [(50, 8)])])
        }
        let ids = try db.reader.read { try ExerciseQueries.browse($0, filter: ExerciseFilter()) }.map(\.id)
        #expect(ids == ["b", "a", "c"])
    }

    @Test func eachFocusRuleNarrowsThePicker() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "press", region: .upper, force: .push)
            try TestData.exercise(db, id: "row", region: .upper, force: .pull)
            try TestData.exercise(db, id: "squat", region: .lower, force: .push)
            try TestData.exercise(db, id: "crunch", region: .core, force: .pull)
        }
        func ids(_ focus: DayFocus) throws -> Set<String> {
            Set(try db.reader.read { try ExerciseQueries.browse($0, filter: ExerciseFilter(focus: focus)) }.map(\.id))
        }
        #expect(try ids(.upper) == ["press", "row"])
        #expect(try ids(.lower) == ["squat"])
        #expect(try ids(.push) == ["press"])
        #expect(try ids(.pull) == ["row"])
        #expect(try ids(.legs) == ["squat"])
        #expect(try ids(.fullBody) == ["press", "row", "squat", "crunch"])
    }

    // MARK: Rotation and lineage

    @Test func aDayNeverDoneComesNext() throws {
        let (programId, a, b, c) = try threeDays()
        try db.writer.write { db in
            try TestData.finishedWorkout(db, dayId: a, startedAt: TestData.day(3), exercises: [])
            try TestData.finishedWorkout(db, dayId: b, startedAt: TestData.day(5), exercises: [])
        }
        #expect(try db.reader.read { try ProgramQueries.nextDay($0, programId: programId) }?.id == c)
        try db.writer.write { _ = try TestData.finishedWorkout($0, dayId: c, startedAt: TestData.day(6), exercises: []) }
        #expect(try db.reader.read { try ProgramQueries.nextDay($0, programId: programId) }?.id == a)
    }

    @Test func aTieGoesToTheEarlierDay() throws {
        let (programId, a, b, c) = try threeDays()
        try db.writer.write { db in
            for day in [a, b] { try TestData.finishedWorkout(db, dayId: day, startedAt: TestData.day(3), exercises: []) }
            try TestData.finishedWorkout(db, dayId: c, startedAt: TestData.day(4), exercises: [])
        }
        #expect(try db.reader.read { try ProgramQueries.nextDay($0, programId: programId) }?.id == a)
    }

    @Test func aCopiedDayInheritsItsSourcesHistory() throws {
        let (x, y) = try db.writer.write { db -> (String, String) in
            let p = try TestData.program(db)
            let y = try TestData.day(db, programId: p.id, name: "Y", position: 0)
            let x = try TestData.day(db, programId: p.id, name: "X", position: 1)
            try TestData.finishedWorkout(db, dayId: y.id, startedAt: TestData.day(5), exercises: [])
            try ProgramWrites.copyDay(db, from: y.id, into: x.id)
            return (x.id, y.id)
        }
        #expect(try db.reader.read { try ProgramQueries.lineage($0, dayId: x) } == [x, y])
        #expect(try db.reader.read { try ProgramQueries.lastDone($0, dayId: x) } == TestData.day(5))
    }

    // MARK: Programs

    @Test(arguments: [
        (Split.fullBody, ["Full Body 1", "Full Body 2", "Full Body 3"], [DayFocus.fullBody, .fullBody, .fullBody]),
        (.upperLower4, ["Upper A", "Lower A", "Upper B", "Lower B"], [.upper, .lower, .upper, .lower]),
        (.upperLower6, ["Upper A", "Lower A", "Upper B", "Lower B", "Upper C", "Lower C"], [.upper, .lower, .upper, .lower, .upper, .lower]),
        (.pushPullLegs3, ["Push", "Pull", "Legs"], [.push, .pull, .legs]),
        (.pushPullLegs6, ["Push A", "Pull A", "Legs A", "Push B", "Pull B", "Legs B"], [.push, .pull, .legs, .push, .pull, .legs]),
        (.custom, ["Day 1"], [.custom]),
    ])
    func eachSplitCreatesItsDays(split: Split, names: [String], focuses: [DayFocus]) throws {
        let program = try db.writer.write { try ProgramWrites.createProgram($0, name: "P", split: split, fullBodyDays: 3, makeActive: true, now: .now) }
        let days = try db.reader.read { try ProgramQueries.days($0, programId: program.id) }.map(\.day)
        #expect(days.map(\.name) == names)
        #expect(days.map(\.focus) == focuses)
    }

    @Test func onlyOneProgramIsActive() throws {
        let (a, b) = try db.writer.write { db in
            (try ProgramWrites.createProgram(db, name: "A", split: .custom, makeActive: true, now: .now),
             try ProgramWrites.createProgram(db, name: "B", split: .custom, makeActive: false, now: .now))
        }
        try db.writer.write { try ProgramWrites.setActive($0, programId: b.id) }
        let active = try db.reader.read { try ProgramRecord.filter(Column("isActive") == true).fetchAll($0) }
        #expect(active.map(\.id) == [b.id])
        #expect(a.id != b.id)
    }

    @Test func copyingADayCopiesItsItemsInOrder() throws {
        let (source, target) = try db.writer.write { db -> (String, String) in
            for id in ["e1", "e2", "e3"] { try TestData.exercise(db, id: id) }
            let p = try TestData.program(db)
            let source = try TestData.day(db, programId: p.id, name: "S", position: 0, items: ["e1", "e2", "e3"])
            let target = try TestData.day(db, programId: p.id, name: "T", position: 1, items: ["e1"])
            try ProgramWrites.copyDay(db, from: source.id, into: target.id)
            return (source.id, target.id)
        }
        let detail = try #require(try db.reader.read { try ProgramQueries.detail($0, dayId: target) })
        #expect(detail.items.map(\.exercise.id) == ["e1", "e2", "e3"])
        #expect(detail.day.copiedFromDayId == source)
        #expect(throws: ProgramError.copyIntoItself) { try db.writer.write { try ProgramWrites.copyDay($0, from: target, into: target) } }
    }

    // MARK: Custom exercises

    @Test func aDuplicateNameIsRejected() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "x", name: "bench press") }
        #expect(throws: ExerciseError.duplicateName(existingId: "x")) {
            try db.writer.write { try ExerciseWrites.createCustom($0, draft: ExerciseDraft(name: "  Bench Press "), now: .now) }
        }
    }

    @Test func regionIsDerivedFromPrimaryMuscles() throws {
        #expect(ExerciseDraft(primaryMuscles: [.chest, .triceps]).bodyRegion == .upper)
        #expect(ExerciseDraft(primaryMuscles: [.quadriceps, .chest]).bodyRegion == .fullBody)
        #expect(ExerciseDraft(primaryMuscles: []).bodyRegion == .fullBody)
    }

    @Test func loadModeIsLockedOnceThereIsHistory() throws {
        let exercise = try db.writer.write { db in
            let e = try TestData.exercise(db, id: "x")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("x", [(50, 8)])])
            return e
        }
        var changed = exercise
        changed.loadMode = .perHand
        #expect(throws: ExerciseError.loadModeLockedByHistory) { try db.writer.write { try ExerciseWrites.update($0, exercise: changed) } }
    }

    // MARK: Real export

    @Test(.enabled(if: Fixtures.hasRealExport))
    func browsingTheImportedHistoryAgreesWithSQL() async throws {
        try await db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        _ = try await ImportService.importJEFIT(fileAt: Fixtures.realExport, into: db)
        let items = try await db.reader.read { try ExerciseQueries.browse($0, filter: ExerciseFilter(onlyDoneBefore: true, includeNonStrength: true)) }
        let expectedCount = try await db.reader.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT we.exerciseId) FROM workoutExercise we JOIN workout w ON w.id = we.workoutId WHERE w.endedAt IS NOT NULL")
        }
        let newest = try await db.reader.read {
            try String.fetchOne($0, sql: "SELECT we.exerciseId FROM workoutExercise we JOIN workout w ON w.id = we.workoutId WHERE w.endedAt IS NOT NULL ORDER BY w.startedAt DESC, we.position LIMIT 1")
        }
        #expect(items.count == expectedCount)
        #expect(items.first.map { $0.lastDoneAt } != nil)
        let newestDate = items.first?.lastDoneAt
        #expect(items.filter { $0.lastDoneAt == newestDate }.map(\.id).contains(newest ?? ""))
    }

    private func threeDays() throws -> (String, String, String, String) {
        try db.writer.write { db in
            let p = try TestData.program(db)
            let a = try TestData.day(db, programId: p.id, name: "A", position: 0)
            let b = try TestData.day(db, programId: p.id, name: "B", position: 1)
            let c = try TestData.day(db, programId: p.id, name: "C", position: 2)
            return (p.id, a.id, b.id, c.id)
        }
    }
}
