import AVFoundation
import Foundation
import GRDB
import Testing
@testable import GymApp

@MainActor struct MediaPlaybackTests {
    @Test func everyCuratedExerciseHasReadableOfflineStillsAndVideos() throws {
        let db = try AppDatabase.inMemory()
        var sample = try db.writer.write { try TestData.exercise($0, id: "sample", name: "Sample") }
        let mappings: [(String, Equipment, String)] = [
            ("jefit:1:2", .barbell, "barbell-bench"), ("jefit:1:12", .barbell, "barbell-squat"),
            ("jefit:1:93", .barbell, "barbell-deadlift"), ("lib:Barbell_Deadlift", .barbell, "barbell-deadlift"),
            ("jefit:1:3", .barbell, "barbell-row"), ("lib:Bent_Over_Barbell_Row", .barbell, "barbell-row"),
            ("jefit:1:8", .barbell, "barbell-incline"), ("lib:Barbell_Incline_Bench_Press_-_Medium_Grip", .barbell, "barbell-incline"),
            ("jefit:1:453", .barbell, "barbell-shoulder"),
            ("lib:Standing_Military_Press", .barbell, "barbell-shoulder"),
            ("jefit:1:83", .bodyweight, "pull-up"), ("lib:Pullups", .bodyweight, "pull-up"),
            ("jefit:1:61", .bodyweight, "hanging-leg-raise"), ("lib:Hanging_Leg_Raise", .bodyweight, "hanging-leg-raise"),
            ("jefit:1:160", .machine, "leg-curl-lying"), ("jefit:1:32", .dumbbell, "dumbbell-lateral-raise"),
            ("jefit:1:26", .dumbbell, "dumbbell-bench"), ("jefit:1:48", .dumbbell, "dumbbell-shoulder-press"),
            ("jefit:1:1262", .machine, "assisted-pull-up"), ("jefit:1:132", .machine, "leg-press-seated"),
            ("jefit:1:46", .machine, "machine-shoulder-press"), ("jefit:1:874", .cable, "face-pull"),
            ("jefit:1:21", .cable, "cable-seated-row"), ("jefit:0:1", .dumbbell, "dumbbell-romanian-deadlift"),
            ("jefit:1:114", .dumbbell, "alternating-hammer-curl"), ("jefit:1:31", .dumbbell, "incline-dumbbell-press"),
            ("lib:Thigh_Adductor", .machine, "hip-adduction"), ("lib:Barbell_Shrug", .barbell, "barbell-shrug"),
            ("lib:Standing_One-Arm_Cable_Curl", .cable, "one-arm-cable-curl"), ("jefit:1:155", .cable, "overhead-rope-extension"),
            ("jefit:1:24", .bodyweight, "dip"), ("lib:Dumbbell_Bicep_Curl", .dumbbell, "dumbbell-curl"),
            ("jefit:1:109", .dumbbell, "one-arm-preacher-curl"), ("jefit:1:1309", .machine, "leg-press-wide"),
        ]
        for (id, equipment, name) in mappings {
            sample.id = id; sample.equipment = equipment
            let asset = try #require(ExerciseMedia.asset(for: sample))
            #expect(asset.name == name)
            #expect(try Data(contentsOf: #require(asset.still)).count > 1000)
            #expect(try Data(contentsOf: #require(asset.video)).count > 1000)
            #expect(asset.still?.isFileURL == true && asset.video?.isFileURL == true)
        }
        for id in ["lib:Barbell_Shoulder_Press", "jefit:1:10", "jefit:1:755", "lib:Romanian_Deadlift", "lib:Reverse_Grip_Bent-Over_Rows", "jefit:1:116", "jefit:1:161", "jefit:1:257"] {
            sample.id = id
            #expect(ExerciseMedia.asset(for: sample) == nil)
        }
    }
    @Test func aLinkedExerciseSharesItsLibraryClipOnlyWithMatchingEquipment() throws {
        let db = try AppDatabase.inMemory()
        var custom = try db.writer.write { try TestData.exercise($0, id: "custom-adduction", name: "Machine Hip Adduction") }
        custom.libraryId = "lib:Thigh_Adductor"
        custom.equipment = .machine
        #expect(ExerciseMedia.asset(for: custom)?.name == "hip-adduction")
        #expect(ExerciseMedia.asset(for: custom)?.author == "Goulart")
        custom.equipment = .cable
        #expect(ExerciseMedia.asset(for: custom) == nil)
        custom.libraryId = nil; custom.equipment = .machine
        #expect(ExerciseMedia.asset(for: custom) == nil)
    }
    @Test func everyClipInTheManifestIsBundledAndCredited() throws {
        let url = try #require(Bundle.main.url(forResource: "manifest", withExtension: "json"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(manifest.count == 28)
        for entry in manifest {
            let name = try #require(entry["name"] as? String)
            #expect(Bundle.main.url(forResource: name, withExtension: "mp4") != nil, "\(name)")
            #expect(Bundle.main.url(forResource: name, withExtension: "jpg") != nil, "\(name)")
            #expect((entry["sha256"] as? String)?.count == 64, "\(name)")
        }
    }
    @Test func hoverStopsOnExitAndReduceMotionStopsAutomaticPlayback() throws {
        let video = try #require(Bundle.main.url(forResource: "barbell-deadlift", withExtension: "mp4"))
        let playback = ExerciseMediaPlayback()
        playback.hover(true, video: video, reduceMotion: false)
        #expect(playback.isPlaying && playback.automaticallyPlaying)
        playback.hover(false, video: video, reduceMotion: false)
        #expect(!playback.isPlaying)
        playback.hover(true, video: video, reduceMotion: true)
        #expect(!playback.isPlaying)
        playback.hover(true, video: video, reduceMotion: false)
        playback.motionPreferenceChanged(true)
        #expect(!playback.isPlaying)
        // An explicit play remains available with Reduce Motion enabled.
        playback.play(video)
        playback.motionPreferenceChanged(true)
        #expect(playback.isPlaying && !playback.automaticallyPlaying)
        playback.reset()
        #expect(playback.player == nil && !playback.isPlaying)
    }
    @Test func changingTheExerciseReplacesThePlayingAsset() throws {
        let first = try #require(Bundle.main.url(forResource: "barbell-deadlift", withExtension: "mp4"))
        let next = try #require(Bundle.main.url(forResource: "pull-up", withExtension: "mp4"))
        let playback = ExerciseMediaPlayback()
        playback.play(first); playback.play(next)
        #expect((playback.player?.currentItem?.asset as? AVURLAsset)?.url == next)
        playback.stop()
    }
}
