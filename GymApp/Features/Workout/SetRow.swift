import GRDB
import SwiftUI

/// One set in an expanded card: label, previous, load, reps and the log tick.
struct SetRow: View {
    let set: WorkoutSetRecord
    let label: String
    let previous: WorkoutSetRecord?
    let loadMode: LoadMode
    let isSelected: Bool
    var best: TrainingMath.BestStatus? = nil
    let onSelect: () -> Void
    let onToggle: () -> Void

    private var done: Bool { self.set.completedAt != nil }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(set.type == .warmUp || set.type == .drop ? Theme.note : .primary)
                    .overlay(alignment: .topTrailing) {
                        if let best { BestBadge(status: best).offset(x: 12, y: -6) }
                    }
                if set.type == .failed {
                    Text("F").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 3).background(Theme.danger, in: .rect(cornerRadius: 3))
                }
            }
            .frame(width: SetColumns.set, alignment: .leading)

            HStack(spacing: 6) {
                Text(previous.map { SetFormat.short($0, loadMode: loadMode) } ?? "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if done && !isSelected {
                    // Card 7.4: logged sets say they can be edited; tapping the row opens the editor.
                    Image(systemName: "pencil").font(.caption2).foregroundStyle(.tertiary)
                        .accessibilityLabel("Edit")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if loadMode != .repsOnly {
                Text(SetColumns.load(set, loadMode: loadMode))
                    .frame(width: SetColumns.load, alignment: .trailing)
            }
            Text("\(set.reps)")
                .frame(width: SetColumns.reps, alignment: .trailing)

            comparison.frame(width: 14)

            Button(action: onToggle) {
                Image(systemName: done ? "checkmark" : "")
                    .font(.subheadline.bold())
                    .symbolEffect(.bounce, options: .nonRepeating, value: done)
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 32, height: 32)
                    .background(done ? Theme.accent : Color.clear, in: Circle())
                    .overlay(Circle().strokeBorder(done ? Color.clear : Color.secondary, lineWidth: 1.5))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Unlog set" : "Log set")
        }
        .font(.body.weight(.semibold).monospacedDigit())
        .foregroundStyle(done ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(isSelected ? Theme.row : Color.clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder private var comparison: some View {
        if done, let previous, let order = SetComparison.compare(set, previous, loadMode: loadMode) {
            switch order {
            case .orderedDescending: Image(systemName: "arrow.up").foregroundStyle(Theme.accent)
            case .orderedAscending: Image(systemName: "arrow.down").foregroundStyle(Theme.warning)
            case .orderedSame: Text("=").foregroundStyle(.secondary)
            }
        } else {
            Color.clear
        }
    }
}

/// Shared widths, so the column header lines up with the rows.
enum SetColumns {
    static let set: CGFloat = 34
    static let load: CGFloat = 64
    static let reps: CGFloat = 40

    static func load(_ set: WorkoutSetRecord, loadMode: LoadMode) -> String {
        let value = Load.format(Double(set.loadHundredths ?? 0) / 100)
        if loadMode == .bodyweightPlus, let h = set.loadHundredths, h > 0 { return "+" + value }
        return value
    }

    static func loadHeader(unit: WeightUnit, loadMode: LoadMode) -> String {
        loadMode == .bodyweightPlus ? "+\(unit.rawValue.uppercased())" : unit.rawValue.uppercased()
    }
}

/// ↑/↓/= against the previous session's set at the same position (rulebook §6).
nonisolated enum SetComparison {
    static func compare(_ set: WorkoutSetRecord, _ previous: WorkoutSetRecord, loadMode: LoadMode) -> ComparisonResult? {
        func order(_ a: Double, _ b: Double) -> ComparisonResult {
            abs(a - b) < 0.01 ? .orderedSame : (a > b ? .orderedDescending : .orderedAscending)
        }
        switch loadMode {
        case .repsOnly: return order(Double(set.reps), Double(previous.reps))
        case .bodyweightPlus: return order(SetFormat.kg(set), SetFormat.kg(previous))
        default:
            return order(TrainingMath.e1RM(kg: SetFormat.kg(set), reps: set.reps),
                         TrainingMath.e1RM(kg: SetFormat.kg(previous), reps: previous.reps))
        }
    }

    /// W for warm-up, D for drop, otherwise the working-set number; warm-ups and drops don't count.
    static func labels(_ sets: [WorkoutSetRecord]) -> [String] {
        var n = 0
        return sets.map { set in
            switch set.type {
            case .warmUp: return "W"
            case .drop: return "D"
            case .working, .failed:
                n += 1
                return "\(n)"
            }
        }
    }
}
