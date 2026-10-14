import Foundation

/// Card 7.8: when an exercise's estimated 1RM might reach a goal, from its own history only.
/// Strength gains slow over time, so the curve is saturating: e1RM = a − b·e^(−t/c), fitted
/// by least squares (a grid over c, linear in a and b). The range comes from the residual
/// spread. Population averages are deliberately not used (ANALYTICS_RESEARCH.md §6).
nonisolated enum Projection {
    static let minimumSessions = 6
    static let minimumDays = 56.0

    struct Fit: Equatable {
        var a: Double, b: Double, c: Double     // ceiling, gap at t = 0, time constant in days
        var spread: Double                       // residual standard deviation, kg
        var start: Date
        func value(at date: Date) -> Double { a - b * exp(-date.timeIntervalSince(start) / 86_400 / c) }
        /// The date the curve reaches `kg`, or nil if it never does.
        func date(reaching kg: Double) -> Date? {
            guard b > 0, kg < a else { return nil }
            let ratio = (a - kg) / b
            guard ratio > 0 else { return nil }
            let days = -c * log(ratio)
            return start.addingTimeInterval(max(0, days) * 86_400)
        }
    }

    enum Outcome: Equatable {
        case notEnoughData
        case reached
        case unreachable(ceiling: Double)
        case projected(date: Date, earliest: Date, latest: Date?)
    }

    /// Fits the points (date, best e1RM per session). Nil under the data minimum or when the
    /// curve isn't rising.
    static func fit(_ points: [(date: Date, value: Double)]) -> Fit? {
        let sorted = points.sorted { $0.date < $1.date }
        guard sorted.count >= minimumSessions, let first = sorted.first, let last = sorted.last,
              last.date.timeIntervalSince(first.date) / 86_400 >= minimumDays else { return nil }
        let t = sorted.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let y = sorted.map(\.value)
        /// For a fixed c, y = a − b·x with x = e^(−t/c) is ordinary least squares in (a, b).
        func solve(_ c: Double) -> Fit? {
            let x = t.map { exp(-$0 / c) }
            let n = Double(x.count), sx = x.reduce(0, +), sy = y.reduce(0, +)
            let sxx = x.reduce(0) { $0 + $1 * $1 }, sxy = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
            let denominator = n * sxx - sx * sx
            guard abs(denominator) > 1e-12 else { return nil }
            let b = -(n * sxy - sx * sy) / denominator
            let a = (sy + b * sx) / n
            guard b > 0 else { return nil }
            let error = zip(x, y).reduce(0) { $0 + pow($1.1 - (a - b * $1.0), 2) }
            return Fit(a: a, b: b, c: c, spread: (error / max(n - 3, 1)).squareRoot(), start: first.date)
        }
        func error(_ f: Fit) -> Double { f.spread }
        // A coarse grid over c, then a fine one around the best.
        var best: Fit?
        var c = 15.0
        while c <= 3000 {
            if let f = solve(c), error(f) < best.map(error) ?? .infinity { best = f }
            c *= 1.08
        }
        if let coarse = best {
            var fine = coarse.c / 1.08
            while fine <= coarse.c * 1.08 {
                if let f = solve(fine), error(f) < best.map(error) ?? .infinity { best = f }
                fine *= 1.002
            }
        }
        return best
    }

    static func outcome(goal: Double, points: [(date: Date, value: Double)], now: Date = .now) -> Outcome {
        if let current = points.map(\.value).max(), current >= goal { return .reached }
        guard let fit = fit(points) else { return .notEnoughData }
        guard let date = fit.date(reaching: goal) else { return .unreachable(ceiling: fit.a) }
        let earliest = fit.date(reaching: goal - fit.spread) ?? date
        let latest = fit.date(reaching: goal + fit.spread)
        return .projected(date: max(date, now), earliest: max(earliest, now), latest: latest.map { max($0, now) })
    }
}

/// Card 7.8: gym-lifter strength standards bundled from FitnessVolt (CC BY 4.0). Percentiles
/// are estimated 1RM in kg by sex and bodyweight class.
nonisolated struct StrengthStandards: Decodable {
    struct WeightClass: Decodable { var upperKg: Double?; var sample: Int; var percentiles: [String: Double] }
    struct Lift: Decodable {
        var label: String
        var match: [[String]]
        var exclude: [String]
        var sexes: [String: [WeightClass]]
    }
    var attribution: String
    var url: String
    var lifts: [String: Lift]

    static let bundled: StrengthStandards? = Bundle.main.url(forResource: "strength-standards", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(StrengthStandards.self, from: $0) }

    /// The standard lift an exercise is, by its name words, for barbell exercises only.
    func lift(for exercise: ExerciseRecord) -> String? {
        guard exercise.equipment == .barbell else { return nil }
        let words = exercise.name.lowercased()
        return lifts.first { _, lift in
            lift.match.contains { group in group.allSatisfy { words.contains($0) } } && !lift.exclude.contains { words.contains($0) }
        }?.key
    }

    /// Where an estimated 1RM sits among gym lifters of that sex and bodyweight class: the
    /// percentile, interpolated between the published ones and clamped to 1–99.
    func percentile(lift: String, sex: String, bodyWeightKg: Double, e1RM: Double) -> Double? {
        guard let classes = lifts[lift]?.sexes[sex], !classes.isEmpty else { return nil }
        let wc = classes.first { ($0.upperKg ?? .infinity) >= bodyWeightKg } ?? classes[classes.count - 1]
        let points = wc.percentiles.compactMap { key, value in Double(key).map { ($0, value) } }.sorted { $0.0 < $1.0 }
        guard let low = points.first, let high = points.last else { return nil }
        if e1RM <= low.1 { return max(1, low.0 * e1RM / low.1) }
        if e1RM >= high.1 { return 99 }
        for (a, b) in zip(points, points.dropFirst()) where e1RM <= b.1 {
            return a.0 + (b.0 - a.0) * (e1RM - a.1) / (b.1 - a.1)
        }
        return 99
    }

    /// Plain-language bands over the percentile.
    static func tier(_ percentile: Double) -> String {
        switch percentile {
        case ..<10: "Beginner"
        case ..<25: "Novice"
        case ..<50: "Intermediate"
        case ..<75: "Proficient"
        case ..<90: "Advanced"
        case ..<99: "Elite"
        default: "Top 1%"
        }
    }
}
