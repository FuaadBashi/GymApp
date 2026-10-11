import Foundation

nonisolated struct ExerciseMediaAsset: Sendable {
    let name: String
    let source: URL
    let author: String
    let license: URL
    var still: URL? { Bundle.main.url(forResource: name, withExtension: "jpg") }
    var video: URL? { Bundle.main.url(forResource: name, withExtension: "mp4") }
}
nonisolated enum ExerciseMedia {
    static func asset(for exercise: ExerciseRecord) -> ExerciseMediaAsset? {
        // Explicit mappings only. A custom exercise or a different variant gets no substitute.
        let id = exercise.id
        switch id {
        case "jefit:1:2", "lib:Barbell_Bench_Press_-_Medium_Grip":
            guard exercise.equipment == .barbell else { return nil }
            return .init(name: "barbell-bench", source: URL(string: "https://commons.wikimedia.org/wiki/File:Bench_press_-_exercise_demonstration_video.webm")!,
                         author: "FitnessScape", license: URL(string: "https://creativecommons.org/licenses/by/3.0/")!)
        case "jefit:1:12", "lib:Barbell_Squat":
            guard exercise.equipment == .barbell else { return nil }
            return .init(name: "barbell-squat", source: URL(string: "https://commons.wikimedia.org/wiki/File:Squat_-_exercise_demonstration_video.webm")!,
                         author: "FitnessScape", license: URL(string: "https://creativecommons.org/licenses/by/3.0/")!)
        default: return nil
        }
    }
}
