import Foundation
import Testing
@testable import GymApp

/// Card 10.3: video first, then pictures, then nothing.
struct DemonstrationTests {
    private func exercise(_ id: String, _ equipment: Equipment, libraryId: String? = nil) -> ExerciseRecord {
        ExerciseRecord(id: id, name: id, equipment: equipment, loadMode: .total, primaryMuscles: [.chest], secondaryMuscles: [],
                       force: nil, mechanic: nil, category: .strength, bodyRegion: .upper, movementPattern: nil, instructions: [],
                       source: .jefit, libraryId: libraryId, stickyNote: nil, defaultRestSeconds: 60, preferredUnit: .kg,
                       isFavorite: false, isArchived: false, createdAt: TestData.day(0))
    }

    @Test func aVideoWinsOverPictures() {
        guard case .video = Demonstration.resolve(exercise("jefit:1:2", .barbell)) else { Issue.record("expected the bench video"); return }
    }

    @Test func picturesFollowTheHandCheckedMap() throws {
        guard case .pictures(let asset, let note) = Demonstration.resolve(exercise("jefit:1:86", .cable)) else {
            Issue.record("expected pictures for the wide-grip pulldown"); return
        }
        #expect(asset.urls.count == 2)
        #expect(asset.license == "CC BY-SA 4.0" && asset.author == "Everkinetic")
        #expect(note == nil)
        guard case .pictures(_, let close) = Demonstration.resolve(exercise("jefit:1:1261", .machine)) else {
            Issue.record("expected pictures for the assisted dip"); return
        }
        #expect(close == "unassisted dip shown")
    }

    @Test func everyMappedAssetIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "demos", withExtension: "json"))
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let assets = try #require(manifest?["assets"] as? [String: [String: Any]])
        for (key, asset) in assets {
            for file in asset["files"] as? [String] ?? [] {
                let name = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
                #expect(Bundle.main.url(forResource: name, withExtension: ext) != nil, "\(key): \(file) missing")
            }
        }
        #expect((manifest?["map"] as? [String: Any])?.count == 138)
    }

    @Test func anUnmappedExerciseHasNone() {
        guard case .none = Demonstration.resolve(exercise("jefit:0:999", .other)) else { Issue.record("expected none"); return }
    }
}
