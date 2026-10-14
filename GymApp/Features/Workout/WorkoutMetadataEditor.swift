import SwiftUI
import GRDB

/// Save each edit in an atomic draft first, then write it in order to the database.
struct WorkoutMetadataEditor: View {
    let db: AppDatabase
    let title: String
    @State var draft: MetadataDraft
    let refreshed: () async -> Void
    @State private var pending: Task<Void, Never>?
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if draft.kind == .set {
                    Section("Effort") {
                        Picker("Reps left in the tank", selection: $draft.reserve) {
                            Text("Not recorded").tag(nil as Int?)
                            Text("Max rep · 0 left").tag(0 as Int?)
                            ForEach(1...3, id: \.self) { n in Text("MR −\(n) · \(n) left").tag(n as Int?) }
                        }
                        Text("Actual reps and set type determine the training figures. Max rep doesn't mark a failed rep.").font(.caption)
                    }
                    Section("Annotations") {
                        ForEach(SetAnnotation.allCases, id: \.self) { tag in
                            Toggle(tag.label, isOn: Binding(get: { draft.annotations.contains(tag) }, set: { value in
                                draft.annotations.removeAll { $0 == tag }
                                if value { draft.annotations.append(tag) }
                            }))
                        }
                    }
                }
                Section("Note") { TextEditor(text: $draft.note).frame(minHeight: 140) }
                Section {
                    Text(error ?? (saving ? "Saving…" : "Saved locally"))
                        .font(.caption).foregroundStyle(error == nil ? Color.secondary : Theme.warning)
                    if error != nil { Button("Retry save") { save() } }
                }
            }
            .themedList()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { Task { await pending?.value; if error == nil { dismiss() } } }
            } }
            .onChange(of: draft) { save() }
        }
        .interactiveDismissDisabled(saving || error != nil)
    }
    private func save() {
        let value = draft
        do { try value.persist() } catch { self.error = "Draft not saved: \(error.localizedDescription)"; return }
        let previous = pending
        saving = true
        pending = Task {
            await previous?.value
            do {
                try await db.writer.write { try value.apply($0) }
                try value.clearIfCurrent()
                if draft == value { error = nil; saving = false }
                await refreshed()
            } catch {
                if draft == value { self.error = "Edit kept as a recovery draft: \(error.localizedDescription)"; saving = false }
            }
        }
    }
}

nonisolated extension WorkoutSetRecord {
    var metadataText: String {
        var parts = annotations.map(\.label)
        if let repsInReserve { parts.append(repsInReserve == 0 ? "Max rep" : "MR −\(repsInReserve)") }
        if let note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}
