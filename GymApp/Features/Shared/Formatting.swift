import SwiftUI

extension Equipment {
    var displayName: String {
        switch self {
        case .barbell: "Barbell"
        case .ezBar: "EZ bar"
        case .dumbbell: "Dumbbell"
        case .kettlebell: "Kettlebell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .smith: "Smith machine"
        case .plate: "Plate"
        case .band: "Band"
        case .bodyweight: "Bodyweight"
        case .other: "Other"
        }
    }
}

extension MovementPattern {
    /// "horizontalPush" → "Horizontal push".
    var displayName: String {
        let spaced = rawValue.replacing(/([A-Z])/) { " " + $0.output.1.lowercased() }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

extension BodyRegion {
    var displayName: String {
        switch self {
        case .upper: "Upper"
        case .lower: "Lower"
        case .core: "Core"
        case .fullBody: "Full body"
        case .cardio: "Cardio"
        }
    }
}

extension DayFocus {
    var displayName: String {
        switch self {
        case .fullBody: "Full body"
        case .upper: "Upper"
        case .lower: "Lower"
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .custom: "Custom"
        }
    }
}

/// How a logged set reads everywhere in the app, by load mode (rulebook §2).
nonisolated enum SetFormat {
    static func short(_ set: WorkoutSetRecord, loadMode: LoadMode) -> String {
        let load = Load.format(Double(set.loadHundredths ?? 0) / 100)
        let prefix = set.type == .warmUp ? "W " : ""
        switch loadMode {
        case .repsOnly: return "\(prefix)×\(set.reps)"
        case .bodyweightPlus:
            let added = set.loadHundredths ?? 0
            return added == 0 ? "\(prefix)BW×\(set.reps)" : "\(prefix)BW\(added < 0 ? "−" : "+")\(Load.format(Double(abs(added)) / 100))×\(set.reps)"
        default: return "\(prefix)\(load)×\(set.reps)"
        }
    }

    static func line(_ sets: [WorkoutSetRecord], loadMode: LoadMode) -> String {
        sets.map { short($0, loadMode: loadMode) }.joined(separator: " · ")
    }

    static func kg(_ set: WorkoutSetRecord) -> Double {
        let value = Double(set.loadHundredths ?? 0) / 100
        return set.unit == .kg ? value : value * WeightUnit.kgPerLb
    }

    /// The set that best represents a session: highest estimated 1RM, or most reps when the
    /// load mode has no 1RM.
    static func best(_ sets: [WorkoutSetRecord], loadMode: LoadMode) -> WorkoutSetRecord? {
        let working = sets.filter { $0.type != .warmUp }
        if loadMode == .repsOnly || loadMode == .bodyweightPlus { return working.max { $0.reps < $1.reps } }
        return working.max { TrainingMath.e1RM(kg: kg($0), reps: $0.reps) < TrainingMath.e1RM(kg: kg($1), reps: $1.reps) }
    }

    static func pastSets(_ sets: [WorkoutSetRecord]) -> [PastSet] {
        sets.map { PastSet(kg: kg($0), reps: $0.reps, type: $0.type) }
    }
}

struct MuscleTags: View {
    let muscles: [Muscle]
    var dimmed = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(muscles, id: \.self) { muscle in
                let color = Theme.color(for: muscle.region)
                Text(muscle.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(color)
                    .background(color.opacity(0.2), in: Capsule())
                    .opacity(dimmed ? 0.6 : 1)
            }
        }
    }
}
