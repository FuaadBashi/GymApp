import Foundation

enum ProtoEquipment: String, Codable {
    case barbell, dumbbell, cable, machine, assisted, other

    /// One stepper tap, in kg. JEFIT history shows dumbbells moving in 2 kg steps.
    var stepKg: Double { self == .dumbbell ? 2 : 2.5 }

    var loadMode: LoadMode {
        switch self {
        case .dumbbell: .perHand
        case .assisted: .bodyweightPlus
        default: .total
        }
    }

    var label: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell · per hand"
        case .cable: "Cable"
        case .machine: "Machine"
        case .assisted: "Assisted · logged as −assistance"
        case .other: "Other"
        }
    }
}

struct HistoryEntry: Codable, Hashable {
    var date: Date
    var dayId: String?
    var sets: [PastSet]
}

struct ExerciseNote: Codable, Hashable {
    var date: String
    var text: String
}

struct PlannedExercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var equipment: ProtoEquipment
    var restSeconds: Int
    var targetSets: Int
    var note: ExerciseNote?
    var history: [HistoryEntry]
}

struct RoutineDay: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var exercises: [PlannedExercise]
}

/// Generated from a JEFIT export by tools/make_prototype_seed.py. Prototype only: the real
/// app imports the CSV itself (docs/JEFIT_EXPORT.md).
struct Seed: Codable {
    var source: String
    var bodyWeightKg: Double
    var bodyWeightDate: String
    var days: [RoutineDay]

    static func loadBundled() throws -> Seed {
        guard let url = Bundle.main.url(forResource: "PrototypeSeed", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "PrototypeSeed.json is missing. Run tools/make_prototype_seed.py, then rebuild."
            ])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Seed.self, from: Data(contentsOf: url))
    }
}
