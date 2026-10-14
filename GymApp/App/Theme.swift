import SwiftUI

/// Decision #34, refined in card 9.1: a near-black base with three surface levels; colour
/// belongs to data and meaning. Volt marks progress and all-time bests, gold 1/6/12-month
/// bests, orange warnings, red errors. Text stays in the system greys. Views use these
/// tokens, never literal colours.
enum Theme {
    // Surfaces, darkest first.
    static let background = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let card = Color(red: 0.090, green: 0.090, blue: 0.102)       // surface 1
    static let row = Color(red: 0.137, green: 0.137, blue: 0.153)        // surface 2
    static let raised = Color(red: 0.192, green: 0.192, blue: 0.212)     // surface 3
    static let separator = Color.white.opacity(0.08)
    /// Body-map regions: not trained, and no muscle at all.
    static let idle = Color(white: 0.26)
    static let inert = Color(white: 0.19)

    // Meaning.
    static let accent = Color(red: 0.78, green: 0.95, blue: 0.26)       // volt
    static let onAccent = Color.black
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.22)
    static let warning = Color(red: 1.0, green: 0.60, blue: 0.27)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let note = Color(red: 0.98, green: 0.83, blue: 0.38)

    // Body regions and program days.
    static let upper = Color(red: 0.45, green: 0.66, blue: 1.0)
    static let lower = Color(red: 1.0, green: 0.62, blue: 0.35)
    static let core = Color(red: 0.75, green: 0.55, blue: 1.0)
    static let cardio = Color(red: 1.0, green: 0.45, blue: 0.70)
    static let dayPalette: [Color] = [accent, upper, lower, core, cardio,
                                      Color(red: 0.35, green: 0.85, blue: 0.85), gold, Color(red: 0.55, green: 0.95, blue: 0.75)]
    static let neutral = Color(white: 0.55)

    /// Competition plate colours (25 red, 20 blue, 15 yellow, 10 green), so the calculator
    /// looks like the bar in the gym.
    static func plate(_ value: Double, unit: WeightUnit) -> Color {
        switch (unit, value) {
        case (.kg, 25...), (.lb, 45...): Color(red: 0.86, green: 0.2, blue: 0.2)
        case (.kg, 20...), (.lb, 35...): Color(red: 0.2, green: 0.4, blue: 0.9)
        case (.kg, 15...), (.lb, 25...): Color(red: 0.95, green: 0.82, blue: 0.2)
        case (.kg, 10...), (.lb, 10...): Color(red: 0.2, green: 0.7, blue: 0.35)
        default: Color(white: 0.6)
        }
    }

    /// Card 9.1: the one style for figures: rounded, with fixed-width digits so changing
    /// numbers don't jitter.
    static func number(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }

    static func color(for region: BodyRegion) -> Color {
        switch region {
        case .upper: upper
        case .lower: lower
        case .core: core
        case .fullBody: accent
        case .cardio: cardio
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
