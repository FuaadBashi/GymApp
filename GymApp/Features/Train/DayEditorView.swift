import SwiftUI

struct DayEditorView: View {
    @State private var model: DayEditorViewModel
    @State private var picking = false
    @State private var suggesting = false
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var copyFrom: ProgramDayRecord?

    init(db: AppDatabase, dayId: String) {
        _model = State(initialValue: DayEditorViewModel(db: db, dayId: dayId))
    }

    var body: some View {
        List {
            if let card = model.card {
                Section {
                    HStack {
                        Button { nameDraft = card.detail.day.name; renaming = true } label: {
                            Text(card.detail.day.name).font(.title2.bold()).foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Menu {
                            ForEach(DayFocus.allCases, id: \.self) { focus in
                                Button(focus.displayName) {
                                    let id = model.dayId
                                    model.write { try ProgramWrites.setFocus($0, dayId: id, focus) }
                                }
                            }
                        } label: {
                            Text(card.detail.day.focus.displayName)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, Tokens.Space.s).padding(.vertical, Tokens.Space.xs)
                                .background(Theme.row, in: Capsule())
                        }
                    }
                    Text("\(card.detail.items.count) exercises · est. \(ProgramQueries.estimatedMinutes(for: card.detail)) min")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)

                Section {
                    ForEach(card.detail.items) { item in
                        NavigationLink {
                            ExerciseDetailView(db: model.db, exerciseId: item.exercise.id, plan: (item.dayExercise, card.detail.day.name))
                        } label: { itemRow(item, lastTime: card.lastTime[item.id]) }
                            .contextMenu {
                                // Card 7.6
                                Menu("Superset with…", systemImage: "link") {
                                    ForEach(card.detail.items.filter { $0.id != item.id }) { other in
                                        Button(other.exercise.name) {
                                            let a = item.id, b = other.id
                                            model.write { try ProgramWrites.superset($0, itemId: a, with: b) }
                                        }
                                    }
                                }
                                if item.dayExercise.supersetGroup != nil {
                                    Button("Remove from superset", systemImage: "link.badge.plus") {
                                        let id = item.id
                                        model.write { try ProgramWrites.unsuperset($0, itemId: id) }
                                    }
                                }
                            }
                    }
                    .onMove { from, to in
                        guard let source = from.first else { return }
                        let target = to > source ? to - 1 : to
                        let id = model.dayId
                        model.write { try ProgramWrites.moveItem($0, dayId: id, from: source, to: target) }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { card.detail.items[$0].id }
                        model.write { db in for id in ids { try ProgramWrites.removeItem(db, itemId: id) } }
                    }
                }

                Section {
                    Button("Add exercises") { picking = true }.buttonStyle(PrimaryButtonStyle())
                    if card.detail.day.focus != .custom {
                        Button("Suggest a day") { suggesting = true }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
        }
        .themedList()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Menu("Copy from another day…") {
                        ForEach(model.copySources, id: \.program.id) { source in
                            Section(source.program.name) {
                                ForEach(source.days) { day in
                                    Button(day.name) { copyFrom = day }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $picking, onDismiss: { Task { await model.reload() } }) {
            if let card = model.card { ExercisePickerView(db: model.db, day: card.detail) }
        }
        .sheet(isPresented: $suggesting, onDismiss: { Task { await model.reload() } }) {
            if let card = model.card { SuggestDayView(db: model.db, day: card.detail.day) }
        }
        .alert("Rename day", isPresented: $renaming) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                let id = model.dayId, name = nameDraft
                model.write { try ProgramWrites.renameDay($0, dayId: id, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(copyMessage, isPresented: Binding(get: { copyFrom != nil }, set: { if !$0 { copyFrom = nil } }), titleVisibility: .visible) {
            Button(model.card?.detail.items.isEmpty == false ? "Replace" : "Copy") {
                if let source = copyFrom?.id {
                    let target = model.dayId
                    model.write { try ProgramWrites.copyDay($0, from: source, into: target) }
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.lastError ?? "") }
        .countsUsage("screen.day")
        .task { await model.reload() }
    }

    private var copyMessage: String {
        let count = model.card?.detail.items.count ?? 0
        let name = model.card?.detail.day.name ?? ""
        return count > 0 ? "Replace the \(count) exercises in \(name) with \(copyFrom?.name ?? "")?" : "Copy \(copyFrom?.name ?? "") into \(name)?"
    }

    private func itemRow(_ item: DayItem, lastTime: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.exercise.name).font(.headline)
                if item.dayExercise.supersetGroup != nil {
                    Label("Superset", systemImage: "link").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            Text("\(item.dayExercise.targetSets) × \(item.dayExercise.repMin == item.dayExercise.repMax ? "\(item.dayExercise.repMin)" : "\(item.dayExercise.repMin)–\(item.dayExercise.repMax)") · rest \(RestFormat.clock(item.dayExercise.restSeconds))")
                .font(.subheadline).foregroundStyle(.secondary)
            if let lastTime {
                Text("Last: \(lastTime)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Tokens.Space.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)   // the whole row answers a tap, not only its text
    }
}
