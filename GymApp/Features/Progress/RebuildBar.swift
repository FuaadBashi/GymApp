import SwiftUI

/// Rulebook §15: how much of a lift's peak is back, as one line and a bar.
struct RebuildBar: View {
    let rebuild: TrainingMath.Rebuild
    var title: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title ?? "Rebuilding").font(.subheadline.weight(title == nil ? .semibold : .regular))
                Spacer()
                Text("\(Int((rebuild.share * 100).rounded()))% of \(Load.format((rebuild.peak * 10).rounded() / 10)) kg")
                    .font(Theme.number(.subheadline, weight: .semibold))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.row)
                    Capsule().fill(Theme.accent).frame(width: max(6, g.size.width * min(1, rebuild.share)))
                }
            }
            .frame(height: 8)
            Text("Now \(Load.format((rebuild.current * 10).rounded() / 10)) kg · peak \(rebuild.peakDate.formatted(.dateTime.month(.abbreviated).year()))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
