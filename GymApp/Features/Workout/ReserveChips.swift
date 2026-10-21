import SwiftUI

/// Reps left in the tank in one tap: Max (0), 1, 2, 3. Tapping the chosen chip clears it.
/// The studio's effort-based rules need this on as many sets as possible.
struct ReserveChips: View {
    let reserve: Int?
    var large = false
    let onPick: (Int?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Reps left").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            ForEach(0...3, id: \.self) { n in
                let on = reserve == n
                Button(n == 0 ? "Max" : "\(n)") { onPick(on ? nil : n) }
                    .font((large ? Font.body : .subheadline).weight(.semibold))
                    .frame(minWidth: large ? 56 : 44, minHeight: large ? 40 : 32)
                    .foregroundStyle(on ? Theme.onAccent : .primary)
                    .background(on ? Theme.accent : Theme.row, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityLabel(n == 0 ? "No reps left" : "\(n) reps left")
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: reserve)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // R.9: one row of chips
    }
}
