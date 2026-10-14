import GRDB
import SwiftUI

/// Creates a custom exercise, or edits one of yours. `template` pre-fills a new exercise from
/// an existing one ("Duplicate as my exercise").
struct ExerciseEditorView: View {
    let db: AppDatabase
    let editing: ExerciseRecord?
    var template: ExerciseRecord? = nil
    var onCreate: ((ExerciseRecord) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExerciseDraft()
    @State private var loadModeLocked = false
    @State private var nameError: String?
    @State private var otherError: String?
    @State private var loaded = false

    private static let loadModeHelp: [LoadMode: String] = [
        .total: "The number on the bar, stack or machine.",
        .perHand: "One dumbbell's weight; volume counts both hands.",
        .perSide: "One side's weight; reps are per side.",
        .bodyweightPlus: "Weight added to your body weight; assistance is negative.",
        .repsOnly: "No weight, just reps.",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .onChange(of: draft.name) { nameError = nil }
                } footer: {
                    if let nameError { Text(nameError).foregroundStyle(Theme.danger) }
                }
                Section {
                    Picker("Equipment", selection: $draft.equipment) {
                        ForEach(Equipment.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Load mode", selection: $draft.loadMode) {
                        ForEach(LoadMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .disabled(loadModeLocked)
                } footer: {
                    Text(loadModeLocked
                         ? "Load mode can't change once an exercise has history. Create a new exercise instead."
                         : Self.loadModeHelp[draft.loadMode] ?? "")
                }
                Section {
                    NavigationLink {
                        MusclePicker(title: "Primary muscles", selection: $draft.primaryMuscles)
                    } label: {
                        LabeledContent("Primary", value: summary(draft.primaryMuscles))
                    }
                    NavigationLink {
                        MusclePicker(title: "Secondary muscles", selection: $draft.secondaryMuscles)
                    } label: {
                        LabeledContent("Secondary", value: summary(draft.secondaryMuscles))
                    }
                    LabeledContent("Body region", value: draft.bodyRegion.displayName)
                    Picker("Movement", selection: $draft.movementPattern) {
                        Text("None").tag(MovementPattern?.none)
                        ForEach(MovementPattern.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                    }
                }
                Section {
                    Picker("Default rest", selection: $draft.defaultRestSeconds) {
                        ForEach(Array(stride(from: 30, through: 300, by: 15)), id: \.self) { Text(RestFormat.clock($0)).tag($0) }
                    }
                    Picker("Unit", selection: $draft.preferredUnit) {
                        Text("kg").tag(WeightUnit.kg)
                        Text("lb").tag(WeightUnit.lb)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .themedList()
            .navigationTitle(editing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } } }
            }
            .alert("Couldn't save", isPresented: Binding(get: { otherError != nil }, set: { if !$0 { otherError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(otherError ?? "")
            }
            .task { await load() }
        }
    }

    private func summary(_ muscles: [Muscle]) -> String {
        muscles.isEmpty ? "None" : muscles.map(\.displayName).joined(separator: ", ")
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        let settings = (try? await db.reader.read { try AppSettings.load($0) }) ?? AppSettings()
        if let source = editing ?? template {
            draft = ExerciseDraft(name: editing == nil ? "" : source.name, equipment: source.equipment, loadMode: source.loadMode,
                                  primaryMuscles: source.primaryMuscles, secondaryMuscles: source.secondaryMuscles,
                                  movementPattern: source.movementPattern, defaultRestSeconds: source.defaultRestSeconds,
                                  preferredUnit: source.preferredUnit)
            if editing == nil { draft.name = source.name + " (mine)" }
        } else {
            draft.defaultRestSeconds = settings.defaultRestSeconds
            draft.preferredUnit = settings.weightUnit
        }
        if let editing {
            loadModeLocked = (try? await db.reader.read { try ExerciseWrites.hasHistory($0, exerciseId: editing.id) }) ?? true
        }
    }

    private func save() async {
        let draft = draft
        do {
            if var exercise = editing {
                exercise.name = draft.name
                exercise.equipment = draft.equipment
                exercise.loadMode = draft.loadMode
                exercise.primaryMuscles = draft.primaryMuscles
                exercise.secondaryMuscles = draft.secondaryMuscles
                exercise.movementPattern = draft.movementPattern
                exercise.defaultRestSeconds = draft.defaultRestSeconds
                exercise.preferredUnit = draft.preferredUnit
                let updated = exercise
                try await db.writer.write { try ExerciseWrites.update($0, exercise: updated) }
            } else {
                let created = try await db.writer.write { try ExerciseWrites.createCustom($0, draft: draft, now: .now) }
                onCreate?(created)
            }
            dismiss()
        } catch ExerciseError.duplicateName {
            nameError = "You already have an exercise called \(draft.name.trimmingCharacters(in: .whitespaces))."
        } catch ExerciseError.emptyName {
            nameError = "Give the exercise a name."
        } catch {
            otherError = error.localizedDescription
        }
    }
}

private struct MusclePicker: View {
    let title: String
    @Binding var selection: [Muscle]

    var body: some View {
        List(Muscle.allCases, id: \.self) { muscle in
            Button {
                if let i = selection.firstIndex(of: muscle) { selection.remove(at: i) } else { selection.append(muscle) }
            } label: {
                HStack {
                    Text(muscle.displayName).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(muscle) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
            }
        }
        .navigationTitle(title)
    }
}
