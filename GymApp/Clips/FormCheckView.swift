import AVKit
import GRDB
import PhotosUI
import SwiftUI

/// A picked video, copied out of the picker's temporary file before that file goes away.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

extension View {
    /// Presents the video picker for `setId`, attaches the clip and analyses it on the phone.
    func clipAttacher(setId: Binding<String?>, db: AppDatabase, onAttached: @escaping () -> Void = {}) -> some View {
        modifier(ClipAttacher(setId: setId, db: db, onAttached: onAttached))
    }
}

private struct ClipAttacher: ViewModifier {
    @Binding var setId: String?
    let db: AppDatabase
    let onAttached: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: Binding(get: { setId != nil }, set: { if !$0 && item == nil { setId = nil } }),
                          selection: $item, matching: .videos)
            .onChange(of: item) { _, picked in
                guard let picked, let target = setId else { return }
                item = nil
                setId = nil
                Task {
                    do {
                        guard let movie = try await picked.loadTransferable(type: PickedMovie.self) else { return }
                        let clip = try await ClipStore.attach(movie.url, toSet: target, db: db)
                        try? FileManager.default.removeItem(at: movie.url)
                        onAttached()
                        await FormCheck.analyse(clip, db: db)
                    } catch {
                        self.error = "The clip could not be attached: \(error.localizedDescription)"
                    }
                }
            }
            .alert("Clip not attached", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
}

nonisolated enum FormCheck {
    static func analyse(_ clip: SetClipRecord, db: AppDatabase) async {
        let url = ClipStore.url(clip)
        guard let samples = try? await Task.detached(priority: .utility, operation: { try await PoseExtractor.samples(from: url) }).value
        else { return }
        try? await ClipStore.saveAnalysis(FormAnalysis.analyse(samples), clipId: clip.id, db: db)
    }
}

/// The clip, the hands' path drawn over it, and what the analysis found.
struct FormCheckView: View {
    let db: AppDatabase
    let clipId: String
    let loggedReps: Int
    @Environment(\.dismiss) private var dismiss
    @State private var clip: SetClipRecord?
    @State private var player: AVPlayer?
    @State private var aspect: CGFloat = 9 / 16
    @State private var confirmingRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                if let player {
                    VideoPlayer(player: player)
                        .overlay { if let r = clip?.result { pathOverlay(r) } }
                        .aspectRatio(aspect, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: Tokens.Radius.card))
                }
                if let r = clip?.result { findings(r) }
                else if clip != nil {
                    Label("Finding your reps and bar path…", systemImage: "hourglass").foregroundStyle(.secondary)
                }
                Text("Measured on this phone from your wrists, which stand in for the bar. Clips stay on this phone and are not synced.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Form check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Analyse again", systemImage: "arrow.clockwise") {
                        guard let clip else { return }
                        Task { await FormCheck.analyse(clip, db: db) }
                    }
                    Button("Remove clip", systemImage: "trash", role: .destructive) { confirmingRemove = true }
                }
            }
        }
        .confirmationDialog("Remove this clip?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove clip", role: .destructive) {
                guard let clip else { return }
                Task { try? await ClipStore.remove(clip, db: db); dismiss() }
            }
        } message: { Text("The video is deleted from the app. The set itself is kept.") }
        .task {
            let id = clipId
            do {
                for try await value in ValueObservation.tracking({ try SetClipRecord.fetchOne($0, key: id) }).values(in: db.reader) {
                    if player == nil, let value {
                        let url = ClipStore.url(value)
                        player = AVPlayer(url: url)
                        if let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
                           let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                            let shown = size.applying(transform)
                            if shown.height != 0 { aspect = abs(shown.width / shown.height) }
                        }
                    }
                    clip = value
                }
            } catch {
                clip = nil
            }
        }
    }

    private func pathOverlay(_ r: FormResult) -> some View {
        Canvas { context, size in
            var path = Path()
            for (i, p) in r.path.enumerated() where p.count == 2 {
                let point = CGPoint(x: p[0] * size.width, y: p[1] * size.height)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(Theme.accent), lineWidth: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func findings(_ r: FormResult) -> some View {
        if r.framesWithPerson == 0 {
            Label("No person was found in this clip. Film from the side, with your whole body in view.",
                  systemImage: "person.fill.questionmark").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                HStack {
                    Text("Reps seen").font(.subheadline)
                    Spacer()
                    Text("\(r.reps)").font(.title3.bold().monospacedDigit())
                    if loggedReps > 0 && r.reps != loggedReps {
                        Text("logged \(loggedReps)").font(.caption).foregroundStyle(Theme.note)
                    }
                }
                HStack {
                    Text("Sideways drift").font(.subheadline)
                    Spacer()
                    Text("\(Int((r.drift * 100).rounded()))% of the travel").font(.subheadline.monospacedDigit())
                }
                if !r.ranges.isEmpty {
                    Text("Range of motion per rep, against your deepest rep").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(r.ranges.enumerated()), id: \.offset) { i, range in
                        HStack(spacing: Tokens.Space.s) {
                            Text("\(i + 1)").font(.caption.monospacedDigit()).frame(width: 18, alignment: .leading)
                            GeometryReader { g in
                                Capsule().fill(range < 0.85 ? Theme.note : Theme.accent)
                                    .frame(width: max(4, g.size.width * range))
                            }
                            .frame(height: 8)
                            Text("\(Int((range * 100).rounded()))%").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Person found in \(r.framesWithPerson) of \(r.frames) frames.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
