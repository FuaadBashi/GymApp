import Foundation

// Raw values are what the database and both bundled JSON files store: cases may be added,
// never renamed.

nonisolated enum Muscle: String, Codable, CaseIterable {
    case abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes,
         hamstrings, lats, lowerBack, middleBack, neck, quadriceps, shoulders, traps, triceps

    /// Decision #22.
    var region: BodyRegion {
        switch self {
        case .chest, .shoulders, .lats, .middleBack, .traps, .biceps, .triceps, .forearms, .neck: .upper
        case .quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors, .lowerBack: .lower
        case .abdominals: .core
        }
    }

    var displayName: String {
        switch self {
        case .lowerBack: "Lower back"
        case .middleBack: "Middle back"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

nonisolated enum Equipment: String, Codable, CaseIterable {
    case barbell, ezBar, dumbbell, kettlebell, cable, machine, smith, plate, band, bodyweight, other

    /// One stepper tap, in kg. JEFIT history shows dumbbells moving in 2 kg steps.
    var stepKg: Double {
        switch self {
        case .barbell, .ezBar, .smith, .machine, .cable, .plate: 2.5
        case .dumbbell: 2
        case .kettlebell: 4
        case .band, .bodyweight, .other: 1
        }
    }
}

/// Rulebook §2: what a logged number means.
nonisolated enum LoadMode: String, Codable, CaseIterable {
    case total, perHand, perSide, bodyweightPlus, repsOnly

    var volumeMultiplier: Double {
        switch self {
        case .perHand, .perSide: 2
        default: 1
        }
    }

    var label: String {
        switch self {
        case .total: "Total"
        case .perHand: "Per hand"
        case .perSide: "Per side"
        case .bodyweightPlus: "Added (− = assisted)"
        case .repsOnly: "Reps only"
        }
    }
}

nonisolated enum Force: String, Codable, CaseIterable { case push, pull, `static` }

nonisolated enum Mechanic: String, Codable, CaseIterable { case compound, isolation }

nonisolated enum ExerciseCategory: String, Codable, CaseIterable {
    case strength, stretching, plyometrics, powerlifting, olympicWeightlifting, strongman, cardio
}

nonisolated enum BodyRegion: String, Codable, CaseIterable {
    case upper, lower, core, fullBody, cardio
}

nonisolated enum MovementPattern: String, Codable, CaseIterable {
    case horizontalPush, inclinePush, verticalPush, horizontalPull, verticalPull,
         squat, hinge, lunge, kneeExtension, kneeFlexion, hipThrust, hipAbduction, calfRaise,
         chestFly, lateralRaise, frontRaise, rearDelt, shrug, pullover,
         bicepsCurl, tricepsExtension, dip,
         coreFlexion, coreStability, backExtension, neck, grip, carry, cardio, other
}

nonisolated enum ExerciseSource: String, Codable, CaseIterable { case library, jefit, custom }

nonisolated enum RecordSource: String, Codable, CaseIterable { case app, jefit }

nonisolated enum Split: String, Codable, CaseIterable {
    case fullBody, upperLower4, upperLower6, pushPullLegs3, pushPullLegs6, custom
}

nonisolated enum DayFocus: String, Codable, CaseIterable {
    case fullBody, upper, lower, push, pull, legs, custom
}
