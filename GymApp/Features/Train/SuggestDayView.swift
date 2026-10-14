import GRDB
import SwiftUI

/// Proposes one exercise per movement slot from your history; you keep, swap or drop each.
struct SuggestDayView: View {
    let db: AppDatabase
    let day: ProgramDayRecord
    @State private var suggestions: [Suggestion] = []
    @State private var included: Set<String> = []  // slot names
    @State private var loaded = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var selectedIds: [String] {
        suggestions.filter { included.contains($0.id) }.compactMap { $0.exercise?.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if loaded && suggestions.isEmpty {
                    Text("Custom days have no movement slots. Add exercises from the library instead.")
                        .foregroundStyle(.secondary)
                }
                ForEach($suggestions) { $suggestion in
                    row($suggestion)
                }
            }
            .themedList()
            .navigationTitle("Suggest \(day.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Add selected (\(selectedIds.count))") { add() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedIds.isEmpty)
                    .padding()
                    .background(.bar)
            }
            .alert("Couldn't add", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .task { await load() }
        }
    }

    private func row(_ suggestion: Binding<Suggestion>) -> some View {
        let s = suggestion.wrappedValue
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.slot.name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                if let exercise = s.exercise {
                    Text(exercise.name).font(.body.weight(.medium))
                    Text(s.reason).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(s.reason).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !s.alternatives.isEmpty {
                Menu {
                    ForEach(s.alternatives) { alt in
                        Button(alt.name) { swap(suggestion, to: alt) }
                    }
                } label: {
                    Text("Swap").font(.subheadline)
                }
            }
            if s.exercise != nil {
                Toggle("Include", isOn: Binding(
                    get: { included.contains(s.id) },
                    set: { if $0 { included.insert(s.id) } else { included.remove(s.id) } }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 2)
    }

    /// The swapped-out exercise joins the alternatives so the choice can be undone.
    private func swap(_ suggestion: Binding<Suggestion>, to alt: ExerciseRecord) {
        var s = suggestion.wrappedValue
        guard let current = s.exercise else { return }
        s.alternatives.removeAll { $0.id == alt.id }
        s.alternatives.insert(current, at: 0)
        s.exercise = alt
        s.reason = "Swapped in"
        suggestion.wrappedValue = s
        included.insert(s.id)
    }

    private func load() async {
        guard !loaded else { return }
        let dayId = day.id
        suggestions = (try? await db.reader.read { try DaySuggester.suggest($0, dayId: dayId, now: .now) }) ?? []
        included = Set(suggestions.filter { $0.exercise != nil }.map(\.id))
        loaded = true
    }

    private func add() {
        let ids = selectedIds, dayId = day.id
        Task {
            do {
                try await db.writer.write { db in
                    try ProgramWrites.addExercises(db, dayId: dayId, exerciseIds: ids, settings: try AppSettings.load(db))
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
