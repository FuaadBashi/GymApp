import SwiftUI

/// Front and back figures, each region shaded by hard sets for its muscles.
/// Artwork: react-body-highlighter (MIT), see Resources/BodyMap/BODY_MAP_PROVENANCE.md.
nonisolated struct BodyMap: Decodable, Sendable {
    struct Region: Decodable, Sendable {
        let name: String
        let muscles: [String]
        let polygons: [[[Double]]]
    }
    let viewBox: [Double]
    let figures: [String: [Region]]

    static let bundled: BodyMap? = {
        guard let url = Bundle.main.url(forResource: "body_map", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BodyMap.self, from: data)
    }()

    /// Every muscle the map can shade.
    var coveredMuscles: Set<Muscle> {
        Set(figures.values.flatMap { $0 }.flatMap(\.muscles).compactMap(Muscle.init(rawValue:)))
    }
}

/// Rulebook §6 bands for hard sets per muscle per week.
enum SetBand: CaseIterable {
    case none, low, building, target, high

    init(_ sets: Double) {
        switch sets {
        case ..<0.5: self = .none
        case ..<6: self = .low
        case ..<10: self = .building
        case ...20: self = .target
        default: self = .high
        }
    }

    var color: Color {
        switch self {
        case .none: Color(white: 0.28)
        case .low: Theme.accent.opacity(0.3)
        case .building: Theme.accent.opacity(0.6)
        case .target: Theme.accent
        case .high: .orange
        }
    }

    var label: String {
        switch self {
        case .none: "0"
        case .low: "1–5"
        case .building: "6–9"
        case .target: "10–20"
        case .high: "20+"
        }
    }
}

/// Card 6.5: recency-weighted hard sets of the last 72 hours.
enum RecoveryBand: CaseIterable {
    case fresh, recovering, worked

    init(_ sets: Double) {
        switch sets {
        case ..<0.5: self = .fresh
        case ..<3: self = .recovering
        default: self = .worked
        }
    }

    var color: Color {
        switch self {
        case .fresh: Color(white: 0.28)
        case .recovering: Color.orange.opacity(0.5)
        case .worked: .orange
        }
    }

    var label: String {
        switch self {
        case .fresh: "Fresh"
        case .recovering: "Recovering"
        case .worked: "Worked"
        }
    }
}

struct BodyMapView: View {
    let sets: [Muscle: Double]
    var color: (Double) -> Color = { SetBand($0).color }

    var body: some View {
        if let map = BodyMap.bundled {
            HStack(spacing: 12) {
                figure(map, "front", "Front")
                figure(map, "back", "Back")
            }
        }
    }

    private func figure(_ map: BodyMap, _ key: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let scale = min(size.width / map.viewBox[0], size.height / map.viewBox[1])
                let dx = (size.width - map.viewBox[0] * scale) / 2
                for region in map.figures[key] ?? [] {
                    let total = region.muscles.compactMap(Muscle.init(rawValue:)).map { sets[$0] ?? 0 }.max() ?? 0
                    let fill = region.muscles.isEmpty ? Color(white: 0.2) : color(total)
                    for polygon in region.polygons where polygon.count > 2 {
                        var path = Path()
                        path.move(to: CGPoint(x: dx + polygon[0][0] * scale, y: polygon[0][1] * scale))
                        for p in polygon.dropFirst() { path.addLine(to: CGPoint(x: dx + p[0] * scale, y: p[1] * scale)) }
                        path.closeSubpath()
                        context.fill(path, with: .color(fill))
                    }
                }
            }
            .aspectRatio(map.viewBox[0] / map.viewBox[1], contentMode: .fit)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(title) body map")
    }
}
