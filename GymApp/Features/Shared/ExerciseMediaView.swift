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
        } else if case .pictures(let asset, let note) = Demonstration.resolve(exercise) {
            PoseLoopView(asset: asset, note: note, exerciseName: exercise.name)
        } else {
            Label("No demonstration for this exercise yet", systemImage: "photo")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Card 10.3: two poses, rest and effort, held 1.2 s each with a 0.4 s crossfade, on a light
/// plate so line drawings read on the dark app. Under Reduce Motion it stays still with a
/// toggle between the poses.
struct PoseLoopView: View {
    let asset: DemoAsset
    let note: String?
    let exerciseName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pose = 0
    @State private var images: [UIImage] = []   // decoded once, not on every pose change

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.white   // the drawings and photos have white backgrounds
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image).resizable().scaledToFit().padding(10)
                        .opacity(index == pose % max(images.count, 1) ? 1 : 0)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement()
            .accessibilityLabel("Demonstration of \(exerciseName), \(pose % 2 == 0 ? "start" : "end") position")
            .task(id: asset.files + [reduceMotion ? "still" : "moving"]) {
                images = asset.urls.compactMap { UIImage(contentsOfFile: $0.path) }
                guard images.count > 1, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(.easeInOut(duration: 0.4)) { pose += 1 }
                }
            }
            if reduceMotion, images.count > 1 {
                Picker("Position", selection: Binding(get: { pose % 2 }, set: { pose = $0 })) {
                    Text("Start").tag(0)
                    Text("End").tag(1)
                }
                .pickerStyle(.segmented)
            }
            if let note {
                Text("Shows: \(note)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text((asset.kind == "photo" ? "Photo: " : "Illustration: ") + asset.author)
                if let source = URL(string: asset.source) { Link("Source", destination: source) }
                if let licence = URL(string: asset.licenseURL) { Link(asset.license, destination: licence) }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
