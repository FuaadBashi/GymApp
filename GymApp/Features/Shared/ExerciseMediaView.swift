import SwiftUI
import AVKit

struct ExerciseMediaView: View {
    let exercise: ExerciseRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playback = ExerciseMediaPlayback()

    var body: some View {
        if let asset = ExerciseMedia.asset(for: exercise), let still = asset.still, let video = asset.video {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if playback.isPlaying, let player = playback.player {
                        VideoPlayer(player: player)
                    } else if let image = UIImage(contentsOfFile: still.path) {
                        Image(uiImage: image).resizable().scaledToFit()
                        Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Demonstration of " + exercise.name)
                .onTapGesture { playback.isPlaying ? playback.stop() : playback.play(video) }
                .onHover { hovering in
                    playback.hover(hovering, video: video, reduceMotion: reduceMotion)
                }
                Button(playback.isPlaying ? "Stop demonstration" : "Play demonstration") { playback.isPlaying ? playback.stop() : playback.play(video) }
                    .font(.caption.weight(.semibold))
                HStack {
                    Text("Video/still: " + asset.author).font(.caption2)
                    Link("Source", destination: asset.source)
                    Link("CC BY 3.0", destination: asset.license)
                }.font(.caption2).foregroundStyle(.secondary)
                Text("Converted to MP4; still extracted from video. Available offline.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .onDisappear { playback.stop() }
            .onChange(of: reduceMotion) { playback.motionPreferenceChanged(reduceMotion) }
            .onChange(of: exercise.id) { playback.reset() }
        } else {
            Label("Exact demonstration not available yet", systemImage: "photo")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
