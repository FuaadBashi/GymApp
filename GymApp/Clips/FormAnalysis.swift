import Foundation

/// One video frame's body points, in Vision's normalised coordinates (0–1, origin bottom left).
nonisolated struct PoseSample: Equatable, Sendable {
    var time: Double
    /// Midpoint of the wrists: where the hands, and so the bar or handles, are.
    var hands: CGPoint?
}

/// What a clip shows about a set: reps, each rep's range of motion, and the bar path.
nonisolated struct FormResult: Codable, Equatable, Sendable {
    var reps: Int
    /// Each rep's vertical travel as a share of the largest rep's (1 = as deep as the best rep).
    var ranges: [Double]
    /// Sideways movement of the hands over the set, as a share of their vertical travel.
    var drift: Double
    /// The hands' path, top-left origin for drawing, at most 240 points.
    var path: [[Double]]
    var frames: Int
    var framesWithPerson: Int
}

/// shortcut: the wrists stand in for the bar, so lifts where the hands do not travel with the load
/// (leg extension, leg curl, calf raise) are not measured well; per-lift joints would fix that.
nonisolated enum FormAnalysis {
    static func analyse(_ samples: [PoseSample]) -> FormResult {
        let seen = samples.compactMap(\.hands)
        let path = stride(from: 0, to: seen.count, by: max(1, seen.count / 240)).map { [Double(seen[$0].x), 1 - Double(seen[$0].y)] }
        let ys = smooth(seen.map { Double($0.y) })
        let reps = repSegments(ys)
        let travel = reps.map { r in (ys[r].max() ?? 0) - (ys[r].min() ?? 0) }
        let deepest = travel.max() ?? 0
        let xs = seen.map { Double($0.x) }
        let vertical = (ys.max() ?? 0) - (ys.min() ?? 0)
        let sideways = (xs.max() ?? 0) - (xs.min() ?? 0)
        return FormResult(reps: reps.count,
                          ranges: deepest > 0 ? travel.map { $0 / deepest } : [],
                          drift: vertical > 0 ? sideways / vertical : 0,
                          path: path, frames: samples.count, framesWithPerson: seen.count)
    }

    static func smooth(_ v: [Double]) -> [Double] {
        v.indices.map { i in
            let window = v[max(0, i - 1)...min(v.count - 1, i + 1)]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    /// A rep is a trip from the start position past the middle of the movement and back. Bands at
    /// 45% and 55% of the set's travel stop small wobbles from counting; a rep that covers more
    /// than about half the deepest rep's travel counts.
    static func repSegments(_ ys: [Double], minimumTravel: Double = 0.03) -> [Range<Int>] {
        guard ys.count > 2, let lo = ys.min(), let hi = ys.max(), hi - lo >= minimumTravel else { return [] }
        let low = lo + 0.45 * (hi - lo), high = lo + 0.55 * (hi - lo)
        func band(_ y: Double) -> Int? { y <= low ? 0 : y >= high ? 1 : nil }
        guard let first = ys.lazy.compactMap(band).first else { return [] }
        var segments: [Range<Int>] = []
        var start = 0, away = false
        for (i, y) in ys.enumerated() {
            guard let b = band(y) else { continue }
            if b != first { away = true }
            else if away { segments.append(start..<(i + 1)); start = i; away = false }
        }
        return segments
    }
}
