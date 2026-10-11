import SwiftUI

struct ExerciseDetailView: View {
    @State private var model: ExerciseDetailViewModel
    @State private var section = Section.history
    @State private var editingSticky = false
    @State private var stickyDraft = ""
    @State private var addingNote = false
    @State private var noteDraft = ""
    @State private var editor: EditorMode?

    private enum Section: String, CaseIterable { case history = "History", notes = "Notes", about = "About" }
    private enum EditorMode: Identifiable {
        case edit(ExerciseRecord), duplicate(ExerciseRecord)
        var id: String { switch self { case .edit(let e): "edit" + e.id; case .duplicate(let e): "dup" + e.id } }
    }

    init(db: AppDatabase, exerciseId: String) {
        _model = State(initialValue: ExerciseDetailViewModel(db: db, exerciseId: exerciseId))
    }

    var body: some View {
        ScrollView {
            if let exercise = model.exercise {
                VStack(alignment: .leading, spacing: 18) {
                    header(exercise)
                    stickyNote(exercise)
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    switch section {
                    case .history: history(exercise)
                    case .notes: notesList
                    case .about: about(exercise)
                    }
                }
                .padding()
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let exercise = model.exercise {
                Button(exercise.isFavorite ? "Unfavorite" : "Favorite", systemImage: exercise.isFavorite ? "star.fill" : "star") {
                    model.toggleFavorite()
                }
                Menu("More", systemImage: "ellipsis.circle") {
                    if exercise.source == .library {
                        Button("Duplicate as my exercise", systemImage: "plus.square.on.square") { editor = .duplicate(exercise) }
                    } else {
                        Button("Edit", systemImage: "pencil") { editor = .edit(exercise) }
                    }
                    Button(exercise.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                        model.setArchived(!exercise.isArchived)
                    }
                }
            }
        }
        .sheet(item: $editor, onDismiss: { Task { await model.reload() } }) { mode in
            switch mode {
            case .edit(let e): ExerciseEditorView(db: model.db, editing: e)
            case .duplicate(let e): ExerciseEditorView(db: model.db, editing: nil, template: e)
            }
        }
        .sheet(isPresented: $editingSticky) {
            NoteEditor(title: "Sticky note", text: $stickyDraft) { model.saveStickyNote(stickyDraft) }
        }
        .sheet(isPresented: $addingNote) {
            NoteEditor(title: "New note", text: $noteDraft) { model.addNote(noteDraft) }
        }
        .task { await model.reload() }
    }

    private func header(_ e: ExerciseRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(e.name).font(.title2.bold())
            Text("\(e.equipment.displayName) · \(e.loadMode.label)").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                MuscleTags(muscles: e.primaryMuscles)
                MuscleTags(muscles: e.secondaryMuscles, dimmed: true)
            }
            if e.isArchived {
                Label("Archived", systemImage: "archivebox").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func stickyNote(_ e: ExerciseRecord) -> some View {
        Button {
            stickyDraft = e.stickyNote ?? ""
            editingSticky = true
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "note.text").foregroundStyle(Theme.note)
                Text(e.stickyNote ?? "Add a note you'll see every time")
                    .foregroundStyle(e.stickyNote == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(12)
            .background(Theme.note.opacity(0.12), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func history(_ e: ExerciseRecord) -> some View {
        Text("Charts and records arrive in phase 3.").font(.caption).foregroundStyle(.secondary)
        Text("\(model.sessions.count) sessions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(model.sessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                            .font(.subheadline.weight(.semibold))
                        Text(session.workout.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if let best = bestE1RM(session.sets, e.loadMode) {
                            Text("1RM \(Load.format((best * 10).rounded() / 10))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Text(SetFormat.line(session.sets, loadMode: e.loadMode)).font(.subheadline.monospacedDigit())
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: 12))
            }
        }
    }

    private func bestE1RM(_ sets: [WorkoutSetRecord], _ mode: LoadMode) -> Double? {
        sets.filter { $0.type != .warmUp && $0.type != .drop }
            .compactMap { TrainingMath.displayableE1RM(kg: SetFormat.kg($0), reps: $0.reps, loadMode: mode) }.max()
    }

    @ViewBuilder
    private var notesList: some View {
        Button("Add note", systemImage: "plus") {
            noteDraft = ""
            addingNote = true
        }
        ForEach(model.notes) { note in
            VStack(alignment: .leading, spacing: 4) {
                Text(note.date).font(.caption).foregroundStyle(.secondary)
                Text(note.text).font(.subheadline)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func about(_ e: ExerciseRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Primary", e.primaryMuscles.map(\.displayName).joined(separator: ", "))
            if !e.secondaryMuscles.isEmpty { row("Secondary", e.secondaryMuscles.map(\.displayName).joined(separator: ", ")) }
            if let pattern = e.movementPattern { row("Movement", pattern.displayName) }
            row("Category", e.category.rawValue.capitalized)
            if let library = model.libraryName { row("Library match", library) }
            if !e.instructions.isEmpty {
                Text("Instructions").font(.headline).padding(.top, 6)
                ForEach(Array(e.instructions.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top) {
                        Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(step)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value)
        }
        .font(.subheadline)
    }
}

struct NoteEditor: View {
    let title: String
    @Binding var text: String
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
                }
        }
        .presentationDetents([.medium])
    }
}
