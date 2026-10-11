import Foundation
import AVFoundation
import Observation

@MainActor @Observable final class ExerciseMediaPlayback {
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    private(set) var automaticallyPlaying = false
    private var video: URL?

    func play(_ url: URL, automatically: Bool = false) {
        if video != url { player?.pause(); player = AVPlayer(url: url); video = url }
        player?.isMuted = true
        player?.seek(to: .zero)
        player?.play()
        isPlaying = true
        automaticallyPlaying = automatically
    }
    func stop() {
        player?.pause(); player?.seek(to: .zero)
        isPlaying = false; automaticallyPlaying = false
    }
    func hover(_ hovering: Bool, video: URL, reduceMotion: Bool) {
        if hovering && !reduceMotion { play(video, automatically: true) }
        else if automaticallyPlaying { stop() }
    }
    func motionPreferenceChanged(_ reduceMotion: Bool) {
        if reduceMotion && automaticallyPlaying { stop() }
    }
    func reset() { stop(); player = nil; video = nil }
}

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
        case "jefit:1:93", "lib:Barbell_Deadlift":
            return asset("barbell-deadlift", title: "Deadlift", equipment: .barbell, exercise: exercise)
        case "jefit:1:3", "lib:Bent_Over_Barbell_Row":
            return asset("barbell-row", title: "Bent-over_row", equipment: .barbell, exercise: exercise)
        case "jefit:1:8", "lib:Barbell_Incline_Bench_Press_-_Medium_Grip":
            return asset("barbell-incline", title: "Incline_press", equipment: .barbell, exercise: exercise)
        case "jefit:1:453", "lib:Standing_Military_Press":
            return asset("barbell-shoulder", title: "Shoulder_press", equipment: .barbell, exercise: exercise)
        case "jefit:1:83", "lib:Pullups":
            return asset("pull-up", title: "Pull-ups", equipment: .bodyweight, exercise: exercise)
        case "jefit:1:61", "lib:Hanging_Leg_Raise":
            return asset("hanging-leg-raise", title: "Leg_raises", equipment: .bodyweight, exercise: exercise)
        default: return nil
        }
    }
    private static func asset(_ name: String, title: String, equipment: Equipment, exercise: ExerciseRecord) -> ExerciseMediaAsset? {
        guard exercise.equipment == equipment else { return nil }
        return .init(name: name, source: URL(string: "https://commons.wikimedia.org/wiki/File:" + title + "_-_exercise_demonstration_video.webm")!,
                     author: "FitnessScape", license: URL(string: "https://creativecommons.org/licenses/by/3.0/")!)
    }
}
