import SwiftUI

/// Card 7.2: the in-screen banner when a logged set makes a best (rulebook §5a).
struct BestBannerView: View {
    let banner: ActiveWorkoutModel.BestBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.repRecord == nil ? banner.status.symbol : "medal.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(banner.repRecord == nil ? banner.status.color : Theme.gold)
                .symbolEffect(.bounce, options: .nonRepeating, value: banner.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.repRecord?.title ?? banner.status.title).font(.headline)
                Text(banner.repRecord.map { "\(banner.exerciseName) · \($0.detail)" }
                     ?? "\(banner.exerciseName) · est. 1RM \(Load.format((banner.e1RM * 10).rounded() / 10)) kg")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.m)
        .background(Theme.card, in: .rect(cornerRadius: Tokens.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card)
            .strokeBorder((banner.repRecord == nil ? banner.status.color : Theme.gold).opacity(0.6), lineWidth: 1))
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

extension TrainingMath.RepRecord {
    var title: String {
        switch self {
        case .mostReps(let kg, _): "Most reps at \(Load.format(kg)) kg"
        case .heaviest(let reps, _): "Heaviest for \(reps) rep\(reps == 1 ? "" : "s")"
        }
    }
    var detail: String {
        switch self {
        case .mostReps(_, let beat): "beat \(beat) reps"
        case .heaviest(_, let beatKg): "beat \(Load.format(beatKg)) kg"
        }
    }
}
