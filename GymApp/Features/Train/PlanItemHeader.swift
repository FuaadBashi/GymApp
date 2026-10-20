import GRDB
import SwiftUI

/// Redesign R.0 prototype (R.3): an exercise opened from a day, with that day's targets edited
/// in place, Swap and Remove. Shown on the exercise page; launch with -prototype to try it.
enum Prototype {
    #if DEBUG
    static let on = ProcessInfo.processInfo.arguments.contains("-prototype")
    #else
    static let on = false
    #endif
}

struct PlanItemHeader: View {
    let db: AppDatabase
    let dayName: String
    @State var item: DayExerciseRecord
    @State private var swapping = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In \(dayName)").font(.caption).foregroundStyle(.secondary)
            Stepper("Sets: \(item.targetSets)", value: $item.targetSets, in: 1...10)
            Stepper("Reps from \(item.repMin)", value: Binding(
                get: { item.repMin }, set: { item.repMin = $0; item.repMax = max(item.repMax, $0) }), in: 1...50)
            Stepper("Reps to \(item.repMax)", value: Binding(
                get: { item.repMax }, set: { item.repMax = $0; item.repMin = min(item.repMin, $0) }), in: 1...50)
            HStack {
                Text("Rest")
                Spacer()
                Picker("Rest", selection: $item.restSeconds) {
                    ForEach(Array(stride(from: 0, through: 300, by: 15)), id: \.self) { Text(RestFormat.clock($0)).tag($0) }
                }
            }
            HStack(spacing: 8) {
                Button("Swap") { swapping = true }.buttonStyle(SecondaryButtonStyle())
                Button("Remove", role: .destructive) {
                    let id = item.id
                    Task { try? await db.writer.write { try ProgramWrites.removeItem($0, itemId: id) }; dismiss() }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .font(.subheadline)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .onChange(of: item) { _, updated in
            Task { try? await db.writer.write { try ProgramWrites.updateItem($0, item: updated) } }
        }
        .sheet(isPresented: $swapping) {
            WorkoutExercisePicker(title: "Swap in \(dayName)") { exerciseId in
                var swapped = item
                swapped.exerciseId = exerciseId
                Task {
                    try? await db.writer.write { try ProgramWrites.updateItem($0, item: swapped) }
                    db.count("tap.planSwap")
                    dismiss()   // back to the day, which shows the new exercise
                }
            }
        }
    }
}
