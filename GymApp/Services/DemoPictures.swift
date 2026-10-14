import Foundation

/// Card 10.1–10.3: the two-pose demonstration pictures in Resources/Demos, built by
/// tools/build_demos.py. `demos.json` credits every asset and maps exercise ids to them.
nonisolated struct DemoAsset: Decodable, Sendable, Equatable {
    var files: [String]
    var kind: String          // "illustration" or "photo"
    var author: String
    var license: String
    var licenseURL: String
    var source: String

    var urls: [URL] {
        files.compactMap { file in
            let name = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
            return Bundle.main.url(forResource: name, withExtension: ext)
        }
    }
}

nonisolated enum DemoPictures {
    struct Entry: Decodable, Sendable, Equatable { var asset: String; var note: String? }
    private struct Manifest: Decodable { var assets: [String: DemoAsset]; var map: [String: Entry] }

    private static let manifest: Manifest? = Bundle.main.url(forResource: "demos", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }

    /// The pictures for an exercise and what they show when it is a close equivalent.
    static func pictures(for exercise: ExerciseRecord) -> (asset: DemoAsset, note: String?)? {
        guard let manifest, let entry = manifest.map[exercise.id], let asset = manifest.assets[entry.asset],
              !asset.urls.isEmpty else { return nil }
        return (asset, entry.note)
    }
}

/// What the demonstration area shows, in order of preference (card 10.3).
nonisolated enum Demonstration {
    case video(ExerciseMediaAsset)
    case pictures(DemoAsset, note: String?)
    case none

    static func resolve(_ exercise: ExerciseRecord) -> Demonstration {
        if let asset = ExerciseMedia.asset(for: exercise), asset.video != nil, asset.still != nil { return .video(asset) }
        if let found = DemoPictures.pictures(for: exercise) { return .pictures(found.asset, note: found.note) }
        return .none
    }
}
