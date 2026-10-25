import Foundation

/// The formulas from docs/TRAINING_RULEBOOK.md. Every figure on screen comes from here, so
/// a summary and a chart can never disagree about what "volume" means.
nonisolated enum TrainingMath {
    /// §4: Epley. A single rep is the load itself.
    static func e1RM(kg: Double, reps: Int) -> Double {
        reps <= 1 ? kg : kg * (1 + Double(reps) / 30)
    }

    /// §15: a lift that has fallen below its peak, and how much of it is back.
    struct Rebuild: Equatable {
        var peak: Double
        var peakDate: Date
        var current: Double
        var share: Double { current / peak }
    }

    static let rebuildWindowDays: Double = 28

    /// §15: the all-time best e1RM against the best of the last 28 days. Nil when the lift was
    /// not trained in those 28 days, or is at 95% of its peak or more (nothing to rebuild).
    static func rebuild(_ history: [(date: Date, e1RM: Double)], now: Date) -> Rebuild? {
        guard let peak = history.max(by: { $0.e1RM < $1.e1RM }) else { return nil }
        let since = now.addingTimeInterval(-rebuildWindowDays * 86_400)
        guard let current = history.filter({ $0.date >= since && $0.date <= now }).map(\.e1RM).max(),
              current < 0.95 * peak.e1RM else { return nil }
        return Rebuild(peak: peak.e1RM, peakDate: peak.date, current: current)
    }

    /// §6a: how far back "recent best" looks when judging a set's effort.
    static let effortWindowDays: Double = 56

    /// §6a: how much a completed set counts as a hard set, from 0 to 1. Labels win: a deload or
    /// injury set counts 0, an effort label (max rep or 1–3 in reserve) counts 1. Otherwise
    /// the set's e1RM against the exercise's best in the window: 85% or more counts 1, 60% or
    /// less counts 0, and it slides in between. No reference (new lift, body weight) counts 1.
    static func effort(type: SetType, repsInReserve: Int?, annotations: [SetAnnotation], e1RM: Double?, reference: Double?) -> Double {
        guard type != .warmUp, type != .drop else { return 0 }
        if annotations.contains(.deload) || annotations.contains(.injury) { return 0 }
        if repsInReserve != nil { return 1 }
        guard let e1RM, let reference, reference > 0 else { return 1 }
        return min(1, max(0, (e1RM / reference - 0.60) / 0.25))
    }

    /// §4: shown only for 1–12 reps, where the estimate means something. Body-weight loads
    /// have no honest 1RM.
    static func displayableE1RM(kg: Double, reps: Int, loadMode: LoadMode) -> Double? {
        guard loadMode != .bodyweightPlus, loadMode != .repsOnly,
              kg > 0, (1...12).contains(reps) else { return nil }
        return e1RM(kg: kg, reps: reps)
    }

    /// §2: without a body weight there is no honest number for a body-weight load, so the
    /// set drops out of volume rather than counting as zero kilos.
    static func calculationKg(_ kg: Double, loadMode: LoadMode, bodyWeightKg: Double?) -> Double? {
        switch loadMode {
        case .total, .perHand, .perSide: return kg
        case .bodyweightPlus:
            guard let bodyWeightKg else { return nil }
            return max(bodyWeightKg + kg, 0)
        case .repsOnly: return nil
        }
    }

    /// §6: Σ load × reps × multiplier, warm-ups excluded (§3). Drop segments count.
    static func volumeKg(_ sets: [PastSet], loadMode: LoadMode, bodyWeightKg: Double?) -> Double {
        sets.reduce(0) { total, set in
            guard set.type != .warmUp,
                  let load = calculationKg(set.kg, loadMode: loadMode, bodyWeightKg: bodyWeightKg)
            else { return total }
            return total + load * Double(set.reps) * loadMode.volumeMultiplier
        }
    }

    struct Bests: Equatable {
        var heaviestKg: Double?
        var bestE1RM: Double?
    }

    /// §5: working and failed sets only. Only a drop set's first segment can set a record,
    /// and it is logged as working or failed, so `.drop` rows are skipped.
    static func bests(_ sets: [PastSet], loadMode: LoadMode) -> Bests {
        guard loadMode != .bodyweightPlus, loadMode != .repsOnly else { return Bests() }
        let counted = sets.filter { $0.type != .warmUp && $0.type != .drop && $0.reps > 0 && $0.kg > 0 }
        return Bests(
            heaviestKg: counted.map(\.kg).max(),
            bestE1RM: counted.compactMap { displayableE1RM(kg: $0.kg, reps: $0.reps, loadMode: loadMode) }.max()
        )
    }

    // MARK: §5a Time-window bests

    /// §5a: what a set's estimated 1RM beat.
    enum BestStatus: Equatable {
        case allTime(beat: Double)
        case window(months: Int, beat: Double)
        case none
    }

    static let bestWindows: [(months: Int, days: Int)] = [(12, 365), (6, 182), (1, 30)]
    static let breakDays = 30

    /// §5a: the all-time best first; else, only after a break of `breakDays` or more since the
    /// all-time best was set, the longest of the 12, 6 and 1-month windows whose best is below
    /// the all-time best and is beaten. Ties are not bests (0.01 kg), and a first-ever set has
    /// nothing to beat. `history` holds earlier estimated 1RMs with their dates.
    static func bestStatus(e1RM: Double, history: [(date: Date, e1RM: Double)], at date: Date) -> BestStatus {
        guard let allTime = history.filter({ $0.date <= date }).map(\.e1RM).max() else { return .none }
        if e1RM - allTime > 0.01 { return .allTime(beat: allTime) }
        for window in eligibleWindows(history: history, at: date) where e1RM - window.best > 0.01 {
            return .window(months: window.months, beat: window.best)
        }
        return .none
    }

    /// §5a: the windows a set could earn, longest first: empty unless training broke off for
    /// `breakDays` since the all-time best was last reached, and only windows whose best is
    /// below the all-time best.
    static func eligibleWindows(history: [(date: Date, e1RM: Double)], at date: Date) -> [(months: Int, best: Double)] {
        let earlier = history.filter { $0.date <= date }.sorted { $0.date < $1.date }
        guard let allTime = earlier.map(\.e1RM).max(),
              let bestDate = earlier.last(where: { allTime - $0.e1RM <= 0.01 })?.date else { return [] }
        let since = earlier.map(\.date).filter { $0 >= bestDate } + [date]
        let gapSeconds = Double(breakDays) * 86_400
        guard zip(since, since.dropFirst()).contains(where: { $1.timeIntervalSince($0) >= gapSeconds }) else { return [] }
        return bestWindows.compactMap { window in
            let from = date.addingTimeInterval(-Double(window.days) * 86_400)
            guard let best = earlier.filter({ $0.date >= from }).map(\.e1RM).max(), allTime - best > 0.01 else { return nil }
            return (window.months, best)
        }
    }

    // MARK: Card 7.3 Beat my best

    /// The load step an exercise moves in: the most common positive gap between the distinct
    /// loads used (smaller wins a tie), else 2.5 kg.
    static func step(loads: [Double]) -> Double {
        let distinct = Set(loads.filter { $0 > 0 }.map { ($0 * 100).rounded() / 100 }).sorted()
        var counts: [Double: Int] = [:]
        for (a, b) in zip(distinct, distinct.dropFirst()) { counts[((b - a) * 100).rounded() / 100, default: 0] += 1 }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? 2.5
    }

    /// For each rep count, the lightest multiple of `step` whose estimated 1RM beats `best`
    /// by more than 0.01 kg (§4, §5a).
    static func beatTable(best: Double, reps: ClosedRange<Int>, step: Double) -> [(reps: Int, kg: Double)] {
        reps.map { r in
            var kg = (best / (r <= 1 ? 1 : 1 + Double(r) / 30) / step).rounded(.up) * step
            if e1RM(kg: kg, reps: r) - best <= 0.01 { kg += step }
            return (r, (kg * 100).rounded() / 100)
        }
    }

    // MARK: Card 7.7 Warm-ups

    /// Rulebook §3a: warm-up sets before `workingKg`, in the working set's unit. Strength ramp:
    /// the bar × 10 (only from 30 kg / 65 lb up), 50% × 5, 70% × 3, 85% × 1. Short ramp:
    /// 50% × 8, 80% × 3. Loads round to the nearest `step`; a load not above the one before,
    /// not below the working load's step, or not above zero is dropped.
    static func warmUpRamp(workingKg: Double, strength: Bool, step: Double, bar: Double, unit: WeightUnit = .kg) -> [(kg: Double, reps: Int)] {
        let percents: [(Double, Int)] = strength ? [(0.5, 5), (0.7, 3), (0.85, 1)] : [(0.5, 8), (0.8, 3)]
        var out: [(kg: Double, reps: Int)] = []
        if strength, bar > 0, workingKg >= (unit == .kg ? 30 : 65) { out.append((bar, 10)) }
        for (p, reps) in percents {
            let kg = ((workingKg * p / step).rounded() * step * 100).rounded() / 100
            guard kg > 0, (kg < workingKg), (kg > (out.last?.kg ?? 0)), !(strength && kg <= bar) else { continue }
            out.append((kg, reps))
        }
        return out
    }
}
