import GRDB
import SwiftUI

/// Card 10.5: the exercise's chosen form cues under its name. A tap dismisses it for this
/// workout; "Hide for this exercise" stops it showing in later workouts too.
struct CueStrip: View {
    @Environment(ActiveWorkoutModel.self) private var model
    let exerciseId: String
    @State private var cues: [FormCueRecord] = []

    var body: some View {
        Group {
            if !cues.isEmpty && !model.dismissedCues.contains(exerciseId) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb").foregroundStyle(Theme.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(cues) { Text($0.text).font(.subheadline) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Button("Dismiss for this workout", systemImage: "xmark") { model.dismissedCues.insert(exerciseId) }
                        Button("Hide for this exercise", systemImage: "eye.slash") { Task { await hide() } }
                    } label: {
                        Image(systemName: "xmark").font(.caption.bold()).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Dismiss cues")
                }
                .padding(10)
                .background(Theme.row, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
                .onTapGesture { model.dismissedCues.insert(exerciseId) }
            }
        }
        .task(id: exerciseId) {
            let id = exerciseId
            cues = (try? await model.db.reader.read { try FormCues.shownOnOpen($0, exerciseId: id) }) ?? []
        }
    }

    private func hide() async {
        let id = exerciseId
        try? await model.db.writer.write { db in
            for cue in try FormCues.shownOnOpen(db, exerciseId: id) {
                try FormCues.update(db, id: cue.id, kind: cue.kind, text: cue.text, showOnOpen: false)
            }
        }
        cues = []
    }
}
