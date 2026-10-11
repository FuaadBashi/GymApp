import SwiftUI
import AVKit

struct ExerciseMediaView: View {
    let exercise: ExerciseRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = false
    @State private var player: AVPlayer?

    var body: some View {
        if let asset = ExerciseMedia.asset(for: exercise), let still = asset.still, let video = asset.video {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if playing, let player {
                        VideoPlayer(player: player)
                    } else if let image = UIImage(contentsOfFile: still.path) {
                        Image(uiImage: image).resizable().scaledToFit()
                        Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Demonstration of " + exercise.name)
                .onTapGesture { playing ? stop() : play(video) }
                .onHover { hovering in
                    guard !reduceMotion else { return }
                    if hovering { play(video) } else { stop() }
                }
                Button(playing ? "Stop demonstration" : "Play demonstration") { playing ? stop() : play(video) }
                    .font(.caption.weight(.semibold))
                HStack {
                    Text("Video/still: " + asset.author).font(.caption2)
                    Link("Source", destination: asset.source)
                    Link("CC BY 3.0", destination: asset.license)
                }.font(.caption2).foregroundStyle(.secondary)
                Text("Converted to MP4; still extracted from video. Available offline.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .onDisappear { stop() }
        } else {
            Label("Exact demonstration not available yet", systemImage: "photo")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func play(_ url: URL) {
        if player == nil { player = AVPlayer(url: url); player?.isMuted = true }
        player?.seek(to: .zero)
        player?.play()
        playing = true
    }
    private func stop() { player?.pause(); player?.seek(to: .zero); playing = false }
}
