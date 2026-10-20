import SwiftUI

struct ExercisesView: View {
    @State private var model: ExercisesViewModel
    @State private var creating = false

    init(db: AppDatabase) { _model = State(initialValue: ExercisesViewModel(db: db)) }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    ForEach(model.items) { item in
                        NavigationLink(value: item.id) { ExerciseRow(item: item) }
                    }
                } header: {
                    ExerciseFilterBar(filter: $model.filter).textCase(nil)
                }
            }
            .themedList()
            .listStyle(.plain)
            .overlay {
                if model.loaded, model.items.isEmpty {
                    ContentUnavailableView {
                        Label("No exercises match", systemImage: "magnifyingglass")
                    } actions: {
                        Button("Clear filters") { model.filter = ExerciseFilter() }
                    }
                }
            }
            .navigationTitle("Exercises")
            .searchable(text: $model.filter.searchText, prompt: "Search exercises")
            .navigationDestination(for: String.self) { id in
                ExerciseDetailView(db: model.db, exerciseId: id)
            }
            .toolbar {
                Button("New exercise", systemImage: "plus") { creating = true }
            }
            .sheet(isPresented: $creating, onDismiss: { Task { await model.reload() } }) {
                ExerciseEditorView(db: model.db, editing: nil)
            }
            // Debounced: typing in the search field must not query on every keystroke.
            .countsUsage("screen.exercises")
            .task(id: model.filter) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await model.reload()
            }
            .onAppear { Task { await model.reload() } }
        }
    }
}

/// The chips under the search field, shared with the day editor's exercise picker.
struct ExerciseFilterBar: View {
    @Binding var filter: ExerciseFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Done before", isSelected: filter.onlyDoneBefore) { filter.onlyDoneBefore.toggle() }
                Chip(title: "Favorites", isSelected: filter.onlyFavorites) { filter.onlyFavorites.toggle() }
                ForEach([BodyRegion.upper, .lower, .core], id: \.self) { region in
                    Chip(title: region.displayName, isSelected: filter.regions.contains(region)) {
                        filter.regions.formSymmetricDifference([region])
                    }
                }
                Menu {
                    ForEach(Muscle.allCases, id: \.self) { muscle in
                        Button {
                            filter.muscles.formSymmetricDifference([muscle])
                        } label: {
                            if filter.muscles.contains(muscle) { Label(muscle.displayName, systemImage: "checkmark") } else { Text(muscle.displayName) }
                        }
                    }
                } label: {
                    chipLabel("Muscles", count: filter.muscles.count)
                }
                Menu {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        Button {
                            filter.equipment.formSymmetricDifference([equipment])
                        } label: {
                            if filter.equipment.contains(equipment) { Label(equipment.displayName, systemImage: "checkmark") } else { Text(equipment.displayName) }
                        }
                    }
                } label: {
                    chipLabel("Equipment", count: filter.equipment.count)
                }
                Menu {
                    Button("Any") { filter.force = nil }
                    Button("Push") { filter.force = .push }
                    Button("Pull") { filter.force = .pull }
                } label: {
                    chipLabel(filter.force.map { $0.rawValue.capitalized } ?? "Push/Pull", count: filter.force == nil ? 0 : 1, showCount: false)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func chipLabel(_ title: String, count: Int, showCount: Bool = true) -> some View {
        Text(count > 0 && showCount ? "\(title) · \(count)" : title)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(count > 0 ? Theme.onAccent : .primary)
            .background(count > 0 ? Theme.accent : Theme.row, in: Capsule())
    }
}
