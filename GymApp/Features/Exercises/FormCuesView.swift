import GRDB
import SwiftUI

/// Card 10.4: the exercise's form cues, seeded from the library on first open, editable.
struct FormCuesView: View {
    let db: AppDatabase
    let exerciseId: String
    @State private var cues: [FormCueRecord] = []
    @State private var editing: FormCueRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Form cues").font(.headline)
                Spacer()
                Button("Add cue", systemImage: "plus") {
                    editing = FormCueRecord(id: "", exerciseId: exerciseId, kind: .setup, text: "", position: 0, showOnOpen: false, source: .owner)
                }
                .labelStyle(.iconOnly)
            }
            .padding(.bottom, 6)
            if cues.isEmpty {
                Text("No cues yet. Add the one thing you want to remember for this lift.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(cues) { cue in
                Button { editing = cue } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(cue.kind.rawValue.capitalized).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        Text(cue.text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        if cue.showOnOpen {
                            Image(systemName: "eye").foregroundStyle(Theme.accent).accessibilityLabel("Shows in workouts")
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if cue.id != cues.last?.id { Divider() }
            }
        }
        .sheet(item: $editing) { cue in
            FormCueEditor(cue: cue, isFirst: cue.id == cues.first?.id, isNew: cue.id.isEmpty) { action in
                await apply(action, to: cue)
            }
        }
        .task { await load(seeding: true) }
    }

    enum Action { case save(FormCueRecord.Kind, String, Bool), delete, moveUp }

    private func apply(_ action: Action, to cue: FormCueRecord) async {
        let ids = cues.map(\.id)
        try? await db.writer.write { db in
            switch action {
            case .save(let kind, let text, let show) where cue.id.isEmpty:
                let added = try FormCues.add(db, exerciseId: exerciseId, kind: kind, text: text)
                if show { try FormCues.update(db, id: added.id, kind: kind, text: text, showOnOpen: true) }
            case .save(let kind, let text, let show):
                try FormCues.update(db, id: cue.id, kind: kind, text: text, showOnOpen: show)
            case .delete:
                try FormCues.delete(db, id: cue.id)
            case .moveUp:
                guard let i = ids.firstIndex(of: cue.id), i > 0 else { return }
                var order = ids
                order.swapAt(i, i - 1)
                try FormCues.reorder(db, exerciseId: exerciseId, ids: order)
            }
        }
        await load(seeding: false)
    }

    private func load(seeding: Bool) async {
        let id = exerciseId
        cues = (try? await db.writer.write { db in
            if seeding { try FormCues.seedIfNeeded(db, exerciseId: id) }
            return try FormCues.cues(db, exerciseId: id)
        }) ?? []
    }
}

private struct FormCueEditor: View {
    let cue: FormCueRecord
    let isFirst: Bool
    let isNew: Bool
    let onAction: (FormCuesView.Action) async -> Void
    @State private var kind: FormCueRecord.Kind
    @State private var text: String
    @State private var show: Bool
    @Environment(\.dismiss) private var dismiss

    init(cue: FormCueRecord, isFirst: Bool, isNew: Bool, onAction: @escaping (FormCuesView.Action) async -> Void) {
        self.cue = cue; self.isFirst = isFirst; self.isNew = isNew; self.onAction = onAction
        _kind = State(initialValue: cue.kind)
        _text = State(initialValue: cue.text)
        _show = State(initialValue: cue.showOnOpen)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(FormCueRecord.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                .pickerStyle(.segmented)
                TextField("Cue", text: $text, axis: .vertical).lineLimit(2...5)
                Toggle("Show when this exercise opens in a workout", isOn: $show)
                if !isNew {
                    Section {
                        if !isFirst { Button("Move up") { run(.moveUp) } }
                        Button("Delete cue", role: .destructive) { run(.delete) }
                    }
                }
            }
            .navigationTitle(isNew ? "New cue" : "Edit cue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { run(.save(kind, text, show)) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func run(_ action: FormCuesView.Action) {
        Task { await onAction(action); dismiss() }
    }
}
