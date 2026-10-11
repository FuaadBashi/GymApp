import SwiftUI

/// Decision #34: dark, one "volt" accent with black text on it, muscle tags by region.
enum Theme {
    static let accent = Color(red: 0.78, green: 0.95, blue: 0.26)
    static let onAccent = Color.black
    static let background = Color.black
    static let card = Color(white: 0.11)
    static let row = Color(white: 0.16)
    static let note = Color(red: 0.98, green: 0.83, blue: 0.38)
    static let upper = Color(red: 0.45, green: 0.66, blue: 1.0)
    static let lower = Color(red: 1.0, green: 0.62, blue: 0.35)
    static let core = Color(red: 0.75, green: 0.55, blue: 1.0)

    static func color(for region: BodyRegion) -> Color {
        switch region {
        case .upper: upper
        case .lower: lower
        case .core: core
        case .fullBody: accent
        case .cardio: .pink
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accent.opacity(isEnabled ? 1 : 0.35), in: .rect(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.row, in: .rect(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A capsule filter toggle.
struct Chip: View {
    let title: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Theme.onAccent : .primary)
                .background(isSelected ? Theme.accent : Theme.row, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
