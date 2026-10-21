import SwiftUI

/// Decision #34, refined in card 9.1; values from design/tokens.json via Tokens (card R.2): a near-black base with three surface levels; colour
/// belongs to data and meaning. Volt marks progress and all-time bests, gold 1/6/12-month
/// bests, orange warnings, red errors. Text stays in the system greys. Views use these
/// tokens, never literal colours.
enum Theme {
    // Surfaces, darkest first.
    static let background = Tokens.background
    static let card = Tokens.surface1
    static let row = Tokens.surface2
    static let raised = Tokens.surface3
    static let separator = Tokens.separator
    /// Body-map regions: not trained, and no muscle at all.
    static let idle = Tokens.idle
    static let inert = Tokens.inert

    // Meaning.
    static let accent = Tokens.accent       // volt
    static let onAccent = Tokens.onAccent
    static let gold = Tokens.gold
    static let warning = Tokens.warning
    static let danger = Tokens.danger
    static let note = Tokens.note

    // Body regions and program days.
    static let upper = Tokens.upper
    static let lower = Tokens.lower
    static let core = Tokens.core
    static let cardio = Tokens.cardio
    static let dayPalette: [Color] = [accent, upper, lower, core, cardio,
                                      Tokens.dayTeal, gold, Tokens.dayMint]
    static let neutral = Tokens.neutral

    /// Competition plate colours (25 red, 20 blue, 15 yellow, 10 green), so the calculator
    /// looks like the bar in the gym.
    static func plate(_ value: Double, unit: WeightUnit) -> Color {
        switch (unit, value) {
        case (.kg, 25...), (.lb, 45...): Tokens.plateRed
        case (.kg, 20...), (.lb, 35...): Tokens.plateBlue
        case (.kg, 15...), (.lb, 25...): Tokens.plateYellow
        case (.kg, 10...), (.lb, 10...): Tokens.plateGreen
        default: Tokens.plateGrey
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
            .background(Theme.accent.opacity(isEnabled ? 1 : 0.35), in: .rect(cornerRadius: Tokens.Radius.card))
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
            .background(Theme.row, in: .rect(cornerRadius: Tokens.Radius.card))
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
                .padding(.horizontal, Tokens.Space.m)
                .padding(.vertical, Tokens.Space.s)
                .foregroundStyle(isSelected ? Theme.onAccent : .primary)
                .background(isSelected ? Theme.accent : Theme.row, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Card 9.2: figures roll digit by digit when they change, unless Reduce Motion is on.
struct RollingNumber<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: value)
    }
}

extension View {
    func rollingNumber<V: Equatable>(_ value: V) -> some View { modifier(RollingNumber(value: value)) }
}

/// Card 9.4: a chart sweeps in from the left the first time it appears, unless Reduce Motion
/// is on.
struct DrawIn: ViewModifier {
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: (drawn || reduceMotion) ? geo.size.width : 0)
                }
            }
            .onAppear {
                guard !drawn else { return }
                if reduceMotion { drawn = true } else { withAnimation(.easeOut(duration: 0.7)) { drawn = true } }
            }
    }
}

extension View {
    func drawIn() -> some View { modifier(DrawIn()) }
}

extension View {
    /// Lists and forms on the app's near-black base rather than the system's pure black.
    func themedList() -> some View { scrollContentBackground(.hidden).background(Theme.background) }
}
