import SwiftUI

struct DayItemEditor: View {
    @State var item: DayExerciseRecord
    let exerciseName: String
    let save: (DayExerciseRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Sets: \(item.targetSets)", value: $item.targetSets, in: 1...10)
                    Stepper("Reps from \(item.repMin)", value: Binding(
                        get: { item.repMin },
                        set: { item.repMin = $0; item.repMax = max(item.repMax, $0) }
                    ), in: 1...50)
                    Stepper("Reps to \(item.repMax)", value: Binding(
                        get: { item.repMax },
                        set: { item.repMax = $0; item.repMin = min(item.repMin, $0) }
                    ), in: 1...50)
                    Picker("Rest", selection: $item.restSeconds) {
                        ForEach(Array(stride(from: 0, through: 300, by: 15)), id: \.self) { Text(RestFormat.clock($0)).tag($0) }
                    }
                }
                Section("Note") {
                    TextField("Cue, seat setting…", text: Binding(get: { item.note ?? "" }, set: { item.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(item); dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
