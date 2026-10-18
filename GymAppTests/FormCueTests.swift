import Foundation
import GRDB
import Testing
@testable import GymApp

struct FormCueTests {
    let db = try! AppDatabase.inMemory()

    private func bench(_ instructions: [String] = [
        "Lie back on a flat bench. Grip the bar slightly wider than shoulder width.",
        "Lower the bar slowly to the middle of your chest. Breathe in as you go.",
        "Press it back up.",
    ]) throws {
        try db.writer.write { db in
            var e = try TestData.exercise(db, id: "bench")
            e.instructions = instructions
            try e.update(db)
        }
    }

    @Test func seedingTakesSetupAndMovementSentences() throws {
        try bench()
        let cues = try db.writer.write { db in
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            return try FormCues.cues(db, exerciseId: "bench")
        }
        #expect(cues.map(\.kind) == [.setup, .movement])
        #expect(cues.map(\.text) == ["Lie back on a flat bench.", "Lower the bar slowly to the middle of your chest."])
        #expect(cues.allSatisfy { $0.source == .library && !$0.showOnOpen })
    }

    @Test func seedingIsIdempotent() throws {
        try bench()
        let count = try db.writer.write { db in
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            return try FormCues.cues(db, exerciseId: "bench").count
        }
        #expect(count == 2)
    }

    @Test func ownerCuesSurviveReseeding() throws {
        try bench()
        let cues = try db.writer.write { db in
            try FormCues.add(db, exerciseId: "bench", kind: .mistake, text: "  Don't bounce off the chest ")
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            return try FormCues.cues(db, exerciseId: "bench")
        }
        #expect(cues.count == 3)
        #expect(cues[0].text == "Don't bounce off the chest" && cues[0].source == .owner)
        #expect(cues.map(\.position) == [0, 1, 2])
    }

    @Test func aDeletedLibraryCueStaysDeleted() throws {
        try bench()
        let left = try db.writer.write { db in
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            for cue in try FormCues.cues(db, exerciseId: "bench") { try FormCues.delete(db, id: cue.id) }
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            return try FormCues.cues(db, exerciseId: "bench")
        }
        #expect(left.isEmpty)
    }

    @Test func noInstructionsSeedsNothingAndInventsNoMistakes() throws {
        try bench([])
        let cues = try db.writer.write { db in
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            return try FormCues.cues(db, exerciseId: "bench")
        }
        #expect(cues.isEmpty)
        #expect(FormCues.seedCues(["One step only"]).map(\.0) == [.setup])
        #expect(!FormCues.seedCues(["A. B.", "C. D.", "E."]).contains { $0.0 == .mistake })
    }

    @Test func firstSentenceHandlesEdges() {
        #expect(FormCues.firstSentence("   ") == nil)
        #expect(FormCues.firstSentence("No full stop") == "No full stop.")
        #expect(FormCues.firstSentence("Stand tall. Then lift.") == "Stand tall.")
        #expect(FormCues.firstSentence("Hold 3.5 kg plates.") == "Hold 3.5 kg plates.")
    }

    @Test func onlyChosenCuesShowOnOpen() throws {
        try bench()
        let shown = try db.writer.write { db in
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            let cues = try FormCues.cues(db, exerciseId: "bench")
            try FormCues.update(db, id: cues[1].id, kind: .movement, text: "Bar to mid-chest", showOnOpen: true)
            return try FormCues.shownOnOpen(db, exerciseId: "bench")
        }
        #expect(shown.map(\.text) == ["Bar to mid-chest"])
    }

    @Test func reorderingRenumbersPositions() throws {
        try bench()
        let texts = try db.writer.write { db in
            try FormCues.seedIfNeeded(db, exerciseId: "bench")
            let added = try FormCues.add(db, exerciseId: "bench", kind: .mistake, text: "Elbows flared")
            try FormCues.reorder(db, exerciseId: "bench", ids: [added.id])
            return try FormCues.cues(db, exerciseId: "bench").map(\.text)
        }
        #expect(texts == ["Elbows flared", "Lie back on a flat bench.", "Lower the bar slowly to the middle of your chest."])
    }

    @Test func blankCueTextIsRejected() throws {
        try bench()
        #expect(throws: (any Error).self) {
            try db.writer.write { try FormCues.add($0, exerciseId: "bench", kind: .setup, text: "   ") }
        }
    }
}
