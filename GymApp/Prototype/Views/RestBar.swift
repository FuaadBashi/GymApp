import SwiftUI

/// The countdown is recomputed from an absolute end time on every tick, never decremented,
/// so time spent locked or in another app is already accounted for (rulebook §9).
struct RestBar: View {
    let endsAt: Date
    let duration: TimeInterval
    let adjust: (TimeInterval) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            let fraction = duration > 0 ? min(1, remaining / duration) : 0
            HStack {
                Button("−15s") { adjust(-15) }
                    .font(.headline)
                    .frame(minWidth: 60, minHeight: 44)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.clock(remaining))
                        .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                    Text("Rest").font(.headline)
                }
                Spacer()
                Button("+15s") { adjust(15) }
                    .font(.headline)
                    .frame(minWidth: 60, minHeight: 44)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Theme.accent.opacity(0.45)
                        Theme.accent.frame(width: geo.size.width * fraction)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer")
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
