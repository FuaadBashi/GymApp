import GRDB
import SwiftUI

/// The plates per side for the selected set's load.
struct PlateCalculatorView: View {
    let set: WorkoutSetRecord?
    let equipment: Equipment
    @Environment(ActiveWorkoutModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var available: [Double]?

    private var unit: WeightUnit { self.set?.unit ?? .kg }
    private var target: Double { Double(set?.loadHundredths ?? 0) / 100 }
    private var bar: Double { PlateMath.bar(for: equipment, unit: unit) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("\(Load.format(target)) \(unit.rawValue)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                if let available, let result = PlateMath.plates(target: target, bar: bar, available: available) {
                    plates(result.perSide)
                    Text(bar == 0 ? "No bar" : "Bar \(Load.format(bar)) \(unit.rawValue)").foregroundStyle(.secondary)
                    if result.perSide.isEmpty {
                        Text("Just the bar.").foregroundStyle(.secondary)
                    } else {
                        Text("Per side: " + result.perSide.map(Load.format).joined(separator: " + "))
                            .font(.headline)
                    }
                    if result.shortBy > 0 {
                        Text("Closest: \(Load.format(result.achieved)) \(unit.rawValue) (\(Load.format(result.shortBy)) \(unit.rawValue) short)")
                            .foregroundStyle(.orange)
                    }
                } else if available != nil {
                    Text("Less than the bar (\(Load.format(bar)) \(unit.rawValue)).").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            .navigationTitle("Plates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .task {
            let unit = unit
            let settings = (try? await model.db.reader.read { try AppSettings.load($0) }) ?? AppSettings()
            available = AppSettings.plates(unit == .kg ? settings.platesKg : settings.platesLb)
        }
    }

    private func plates(_ perSide: [Double]) -> some View {
        let biggest = (available ?? []).max() ?? 25
        return HStack(spacing: 3) {
            Capsule().fill(Color.gray).frame(width: 36, height: 10)
            ForEach(Array(perSide.enumerated()), id: \.offset) { _, plate in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color(plate))
                    .frame(width: 16, height: 40 + 100 * plate / biggest)
                    .overlay(Text(Load.format(plate)).font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(-90)).fixedSize())
            }
            Capsule().fill(Color.gray).frame(width: 20, height: 10)
        }
        .frame(height: 150)
    }

    private func color(_ plate: Double) -> Color {
        switch (unit, plate) {
        case (.kg, 25...), (.lb, 45...): .red
        case (.kg, 20...), (.lb, 35...): .blue
        case (.kg, 15...), (.lb, 25...): .yellow
        case (.kg, 10...), (.lb, 10...): .green
        default: Color(white: 0.6)
        }
    }
}
