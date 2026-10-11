import Foundation

/// The fields `exercises.json` and `jefit_exercise_map.json` share. Both files are generated
/// by scripts in tools/, so a decode failure means a script and this type drifted apart.
nonisolated protocol ExerciseDefinition {
    var name: String { get }
    var equipment: Equipment { get }
    var loadMode: LoadMode { get }
    var primaryMuscles: [Muscle] { get }
    var secondaryMuscles: [Muscle] { get }
    var force: Force? { get }
    var mechanic: Mechanic? { get }
    var category: ExerciseCategory { get }
    var bodyRegion: BodyRegion { get }
    var movementPattern: MovementPattern? { get }
}

nonisolated struct LibraryEntry: ExerciseDefinition, Decodable, Equatable {
    var id: String
    var name: String
    var equipment: Equipment
    var loadMode: LoadMode
    var primaryMuscles: [Muscle]
    var secondaryMuscles: [Muscle]
    var force: Force?
    var mechanic: Mechanic?
    var category: ExerciseCategory
    var bodyRegion: BodyRegion
    var movementPattern: MovementPattern?
    var instructions: [String]
}

nonisolated enum ImportWeights: String, Decodable { case keep, drop }

nonisolated struct JEFITMapEntry: ExerciseDefinition, Decodable, Equatable {
    var jefitId: String
    var name: String
    var equipment: Equipment
    var loadMode: LoadMode
    var primaryMuscles: [Muscle]
    var secondaryMuscles: [Muscle]
    var force: Force?
    var mechanic: Mechanic?
    var category: ExerciseCategory
    var bodyRegion: BodyRegion
    var movementPattern: MovementPattern?
    var libraryId: String?
    var jefitLogCount: Int
    var importWeights: ImportWeights
    var negateOnImport: Bool
    var skipOnImport: Bool
    var note: String?

    /// The database id of the imported exercise.
    var exerciseId: String { "jefit:\(jefitId)" }
}

nonisolated enum BundledExercises {
    private struct File<Entry: Decodable>: Decodable {
        var source: String
        var exercises: [Entry]
    }

    enum LoadError: LocalizedError {
        case missing(String)
        case undecodable(String, Error)
        var errorDescription: String? {
            switch self {
            case .missing(let name): "\(name).json is missing from the app bundle."
            case .undecodable(let name, let error): "\(name).json could not be read: \(error)"
            }
        }
    }

    static func library(bundle: Bundle = .main) throws -> [LibraryEntry] {
        try load("exercises", bundle: bundle)
    }

    static func jefitMap(bundle: Bundle = .main) throws -> [JEFITMapEntry] {
        try load("jefit_exercise_map", bundle: bundle)
    }

    private static func load<Entry: Decodable>(_ name: String, bundle: Bundle) throws -> [Entry] {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { throw LoadError.missing(name) }
        do {
            return try JSONDecoder().decode(File<Entry>.self, from: Data(contentsOf: url)).exercises
        } catch {
            throw LoadError.undecodable(name, error)
        }
    }
}
