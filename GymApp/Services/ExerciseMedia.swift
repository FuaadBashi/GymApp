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
    private struct Clip {
        let source: String
        let author: String
        let license: String
    }
    private static let fitnessScape = "https://creativecommons.org/licenses/by/3.0/"
    private static let goulart = "https://creativecommons.org/licenses/by-sa/4.0/"
    private static func commons(_ title: String) -> Clip {
        Clip(source: "https://commons.wikimedia.org/wiki/File:" + title + "_-_exercise_demonstration_video.webm",
             author: "FitnessScape", license: fitnessScape)
    }
    private static func wger(_ id: Int) -> Clip {
        Clip(source: "https://wger.de/en/exercise/\(id)/view-base", author: "Goulart", license: goulart)
    }

    /// Every bundled clip, checked frame by frame against the movement (PROVENANCE.md).
    private static let clips: [String: Clip] = [
        "barbell-bench": commons("Bench_press"), "barbell-squat": commons("Squat"), "barbell-deadlift": commons("Deadlift"),
        "barbell-row": commons("Bent-over_row"), "barbell-incline": commons("Incline_press"),
        "barbell-shoulder": commons("Shoulder_press"), "pull-up": commons("Pull-ups"), "hanging-leg-raise": commons("Leg_raises"),
        "leg-curl-lying": wger(365), "dumbbell-lateral-raise": wger(348), "dumbbell-bench": wger(75),
        "dumbbell-shoulder-press": wger(567), "assisted-pull-up": wger(477), "leg-press-seated": wger(371),
        "machine-shoulder-press": wger(543), "face-pull": wger(222), "cable-seated-row": wger(512),
        "dumbbell-romanian-deadlift": wger(507), "alternating-hammer-curl": wger(272), "incline-dumbbell-press": wger(537),
        "hip-adduction": wger(12), "barbell-shrug": wger(570), "one-arm-cable-curl": wger(95),
        "overhead-rope-extension": wger(659), "dip": wger(194), "dumbbell-curl": wger(92),
        "one-arm-preacher-curl": wger(584), "leg-press-wide": wger(374),
    ]

    /// Exercise id → clip and the equipment the clip shows. Explicit mappings only: a
    /// different variant or equipment gets no substitute.
    private static let mapping: [String: (clip: String, equipment: Equipment)] = [
        "jefit:1:2": ("barbell-bench", .barbell), "lib:Barbell_Bench_Press_-_Medium_Grip": ("barbell-bench", .barbell),
        "jefit:1:12": ("barbell-squat", .barbell), "lib:Barbell_Squat": ("barbell-squat", .barbell),
        "jefit:1:93": ("barbell-deadlift", .barbell), "lib:Barbell_Deadlift": ("barbell-deadlift", .barbell),
        "jefit:1:3": ("barbell-row", .barbell), "lib:Bent_Over_Barbell_Row": ("barbell-row", .barbell),
        "jefit:1:8": ("barbell-incline", .barbell), "lib:Barbell_Incline_Bench_Press_-_Medium_Grip": ("barbell-incline", .barbell),
        "jefit:1:453": ("barbell-shoulder", .barbell), "lib:Standing_Military_Press": ("barbell-shoulder", .barbell),
        "jefit:1:83": ("pull-up", .bodyweight), "lib:Pullups": ("pull-up", .bodyweight),
        "jefit:1:61": ("hanging-leg-raise", .bodyweight), "lib:Hanging_Leg_Raise": ("hanging-leg-raise", .bodyweight),
        "jefit:1:160": ("leg-curl-lying", .machine), "lib:Lying_Leg_Curls": ("leg-curl-lying", .machine),
        "jefit:1:32": ("dumbbell-lateral-raise", .dumbbell), "lib:Side_Lateral_Raise": ("dumbbell-lateral-raise", .dumbbell),
        "jefit:1:26": ("dumbbell-bench", .dumbbell), "lib:Dumbbell_Bench_Press": ("dumbbell-bench", .dumbbell),
        "jefit:1:48": ("dumbbell-shoulder-press", .dumbbell), "lib:Dumbbell_Shoulder_Press": ("dumbbell-shoulder-press", .dumbbell),
        "jefit:1:1262": ("assisted-pull-up", .machine),
        "jefit:1:132": ("leg-press-seated", .machine),
        "jefit:1:46": ("machine-shoulder-press", .machine), "lib:Machine_Shoulder_Military_Press": ("machine-shoulder-press", .machine),
        "jefit:1:874": ("face-pull", .cable), "lib:Face_Pull": ("face-pull", .cable),
        "jefit:1:21": ("cable-seated-row", .cable), "lib:Seated_Cable_Rows": ("cable-seated-row", .cable),
        "jefit:0:1": ("dumbbell-romanian-deadlift", .dumbbell),
        "jefit:1:114": ("alternating-hammer-curl", .dumbbell), "lib:Alternate_Hammer_Curl": ("alternating-hammer-curl", .dumbbell),
        "jefit:1:31": ("incline-dumbbell-press", .dumbbell), "lib:Incline_Dumbbell_Press": ("incline-dumbbell-press", .dumbbell),
        "lib:Thigh_Adductor": ("hip-adduction", .machine),
        "lib:Barbell_Shrug": ("barbell-shrug", .barbell),
        "lib:Standing_One-Arm_Cable_Curl": ("one-arm-cable-curl", .cable),
        "jefit:1:155": ("overhead-rope-extension", .cable), "lib:Cable_Rope_Overhead_Triceps_Extension": ("overhead-rope-extension", .cable),
        "jefit:1:24": ("dip", .bodyweight), "lib:Parallel_Bar_Dip": ("dip", .other),
        "lib:Dumbbell_Bicep_Curl": ("dumbbell-curl", .dumbbell),
        "jefit:1:109": ("one-arm-preacher-curl", .dumbbell), "lib:One_Arm_Dumbbell_Preacher_Curl": ("one-arm-preacher-curl", .dumbbell),
        "jefit:1:1309": ("leg-press-wide", .machine),
    ]

    /// The exercise's own mapping, else its library link's: links are hand-checked to be the
    /// same movement, so a custom exercise linked to a library entry shares its clip. Either
    /// way the exercise's equipment must match what the clip shows.
    static func asset(for exercise: ExerciseRecord) -> ExerciseMediaAsset? {
        let entry = mapping[exercise.id] ?? exercise.libraryId.flatMap { mapping[$0] }
        guard let entry, entry.equipment == exercise.equipment, let clip = clips[entry.clip],
              let source = URL(string: clip.source), let license = URL(string: clip.license) else { return nil }
        return ExerciseMediaAsset(name: entry.clip, source: source, author: clip.author, license: license)
    }
}
