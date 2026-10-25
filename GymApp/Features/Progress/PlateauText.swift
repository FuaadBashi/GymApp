import Foundation

/// Rulebook §8's explanation, in its fixed form.
enum PlateauText {
    static func line(_ p: TrainingMath.Plateau, loadMode: LoadMode) -> String {
        let reps = loadMode == .repsOnly || loadMode == .bodyweightPlus
        func v(_ x: Double) -> String { reps ? "\(Int(x)) reps" : "\(Load.format((x * 10).rounded() / 10)) kg est. 1RM" }
        return "Best in the last 3 weeks (\(p.recentSessions) sessions): \(v(p.recentBest)). Best in the 3 weeks before: \(v(p.earlierBest))."
    }
}
