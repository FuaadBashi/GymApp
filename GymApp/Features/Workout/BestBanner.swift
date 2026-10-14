import SwiftUI

/// Card 7.2: the in-screen banner when a logged set makes a best (rulebook §5a).
struct BestBannerView: View {
    let banner: ActiveWorkoutModel.BestBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.status.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(banner.status.color)
                .symbolEffect(.bounce, options: .nonRepeating, value: banner.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.status.title).font(.headline)
                Text("\(banner.exerciseName) · est. 1RM \(Load.format((banner.e1RM * 10).rounded() / 10)) kg")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(banner.status.color.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
    }
}

/// The small mark a set keeps after its banner goes.
struct BestBadge: View {
    let status: TrainingMath.BestStatus
    var body: some View {
        Image(systemName: status.symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status.color)
            .symbolEffect(.bounce, options: .nonRepeating, value: status)
            .accessibilityLabel(status.title)
    }
}

extension TrainingMath.BestStatus {
    var title: String {
        switch self {
        case .allTime: "New best est. 1RM"
        case .window(let months, _): months == 1 ? "Best in a month" : "Best in \(months) months"
        case .none: ""
        }
    }
    var symbol: String {
        switch self {
        case .allTime: "trophy.fill"
        case .window: "clock.badge.checkmark.fill"
        case .none: "circle"
        }
    }
    var color: Color {
        switch self {
        case .allTime: Theme.accent
        case .window: Theme.gold
        case .none: .secondary
        }
    }
}
