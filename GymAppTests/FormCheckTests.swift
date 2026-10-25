import Foundation
import GRDB
import Testing
@testable import GymApp

@Suite struct FormCheckTests {
    /// Hands moving up and down `reps` times at 8 frames a second, 2 s a rep, with a little noise.
    func samples(reps: Int, depths: [Double]? = nil, drift: Double = 0, missingEvery: Int = 0) -> [PoseSample] {
        var out: [PoseSample] = []
        let perRep = 16
        for i in 0..<(reps * perRep + 1) {
            let rep = min(i / perRep, reps - 1)
            let depth = depths?[rep] ?? 0.30
            let phase = Double(i % perRep) / Double(perRep)
            let y = 0.70 - depth * (1 - cos(2 * .pi * phase)) / 2 + (i % 2 == 0 ? 0.004 : -0.004)
            let x = 0.50 + drift * sin(2 * .pi * phase)
            let missing = missingEvery > 0 && i % missingEvery == 0 && i > 0
            out.append(PoseSample(time: Double(i) / 8, hands: missing ? nil : CGPoint(x: x, y: y)))
        }
        return out
    }

    @Test func countsRepsDespiteNoiseAndMissedFrames() {
        #expect(FormAnalysis.analyse(samples(reps: 5)).reps == 5)
        #expect(FormAnalysis.analyse(samples(reps: 8, missingEvery: 7)).reps == 8)
        #expect(FormAnalysis.analyse(samples(reps: 1)).reps == 1)
    }

    @Test func standingStillIsNoReps() {
        let still = (0..<40).map { PoseSample(time: Double($0) / 8, hands: CGPoint(x: 0.5, y: 0.6 + ($0 % 2 == 0 ? 0.005 : -0.005))) }
        #expect(FormAnalysis.analyse(still).reps == 0)
        let nobody = (0..<40).map { PoseSample(time: Double($0) / 8, hands: nil) }
        let r = FormAnalysis.analyse(nobody)
        #expect(r.reps == 0 && r.framesWithPerson == 0 && r.frames == 40)
    }

    @Test func shortRepsShowAsAShareOfTheDeepest() {
        let r = FormAnalysis.analyse(samples(reps: 4, depths: [0.30, 0.30, 0.30, 0.18]))
        #expect(r.reps == 4)
        #expect(r.ranges.count == 4)
        #expect(abs(r.ranges[0] - 1) < 0.08)
        #expect(abs(r.ranges[3] - 0.6) < 0.1, "the last rep went 60% as deep")
    }

    @Test func sidewaysDriftIsAShareOfTheVerticalTravel() {
        #expect(FormAnalysis.analyse(samples(reps: 3)).drift < 0.05)
        let r = FormAnalysis.analyse(samples(reps: 3, drift: 0.03))
        #expect(abs(r.drift - 0.2) < 0.05, "6% sideways over 30% vertical")
        #expect(r.path.count <= 240 && r.path.allSatisfy { $0.count == 2 })
    }

    // MARK: Storage

    @Test func clipsAttachReplaceAndGoWithTheirSet() async throws {
        let db = try AppDatabase.inMemory()
        let folder = FileManager.default.temporaryDirectory.appending(path: "clips-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("video".utf8).write(to: source)
        let setId = try await db.writer.write { db -> String in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.base, exercises: [("bench", [(kg: 60, reps: 5)])])
            return try String.fetchOne(db, sql: "SELECT id FROM workoutSet")!
        }

        let first = try await ClipStore.attach(source, toSet: setId, db: db, folder: folder)
        let second = try await ClipStore.attach(source, toSet: setId, db: db, folder: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [second.fileName], "replacing removes the old file")
        #expect(first.id != second.id)

        try await ClipStore.saveAnalysis(FormAnalysis.analyse(samples(reps: 5)), clipId: second.id, db: db)
        let stored = try await db.reader.read { try SetClipRecord.fetchOne($0, key: second.id) }
        #expect(stored?.result?.reps == 5)

        try await db.writer.write { try $0.execute(sql: "DELETE FROM workoutSet WHERE id = ?", arguments: [setId]) }
        #expect(try await db.reader.read { try SetClipRecord.fetchCount($0) } == 0, "the row goes with its set")
        await ClipStore.removeOrphans(db: db, folder: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty, "and the file is cleaned on launch")
    }
}
