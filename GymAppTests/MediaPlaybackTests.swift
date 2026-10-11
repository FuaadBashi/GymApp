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
            ("jefit:1:61", .bodyweight, "hanging-leg-raise"), ("lib:Hanging_Leg_Raise", .bodyweight, "hanging-leg-raise")
        ]
        for (id, equipment, name) in mappings {
            sample.id = id; sample.equipment = equipment
            let asset = try #require(ExerciseMedia.asset(for: sample))
            #expect(asset.name == name)
            #expect(try Data(contentsOf: #require(asset.still)).count > 1000)
            #expect(try Data(contentsOf: #require(asset.video)).count > 1000)
            #expect(asset.still?.isFileURL == true && asset.video?.isFileURL == true)
        }
        for id in ["lib:Barbell_Shoulder_Press", "jefit:1:10", "jefit:1:755", "lib:Romanian_Deadlift", "lib:Reverse_Grip_Bent-Over_Rows", "jefit:1:1262"] {
            sample.id = id
            #expect(ExerciseMedia.asset(for: sample) == nil)
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
