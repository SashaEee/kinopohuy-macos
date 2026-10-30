import CoreText
import SwiftUI

/// КиноПохуй's look, shared with the TV app: near-black, Inter, white text at a few opacity tiers, a white
/// capsule for the main action, a white ring on the poster under the pointer. The logo's orange is for the logo
/// and the playback progress only.
enum KP {
    static let bg = Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255)
    static let fg = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let fg80 = fg.opacity(0.8)
    static let fg70 = fg.opacity(0.7)
    static let fg55 = fg.opacity(0.55)
    static let fg38 = fg.opacity(0.38)
    static let ink = Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255)
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255)
    static let surfaceHigh = Color(red: 38 / 255, green: 38 / 255, blue: 42 / 255)
    static let line = Color.white.opacity(0.08)
    static let chip = Color.white.opacity(0.1)
    static let chipStrong = Color.white.opacity(0.2)
    static let good = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let bad = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let sun = Color(red: 1, green: 0.55, blue: 0.05)
    static let sunGradient = LinearGradient(
        colors: [Color(red: 1, green: 0.42, blue: 0), Color(red: 1, green: 0.8, blue: 0.12)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Space between the window's edges and the content.
    static let gutter: CGFloat = 48
    static let topBarHeight: CGFloat = 52
    static let posterRadius: CGFloat = 8
    /// The pixel size a card's picture is decoded at (a 168-pt card at 2×, 2:3), whatever the card's width in the
    /// current size tier: a title's page asks for the same size to show the card's picture at once, from memory.
    static let cardWidth: CGFloat = 168
    static func cardPosterPixels() -> CGSize { CGSize(width: cardWidth * 2, height: cardWidth * 3) }

    /// Inter at a given weight (its variable file's named instances); the system font if it didn't load.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard fontsRegistered else { return .system(size: size, weight: weight) }
        return .custom(interName(weight), size: size)
    }

    private static func interName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight: "InterVariable-ExtraLight"
        case .thin: "InterVariable-Thin"
        case .light: "InterVariable-Light"
        case .medium: "InterVariable-Medium"
        case .semibold: "InterVariable-SemiBold"
        case .bold: "InterVariable-Bold"
        case .heavy: "InterVariable-ExtraBold"
        case .black: "InterVariable-Black"
        default: "InterVariable"
        }
    }

    nonisolated(unsafe) private static var fontsRegistered = false

    /// Once at launch, before anything is drawn.
    static func registerFonts(in bundle: Bundle = .main) {
        guard !fontsRegistered, let url = bundle.url(forResource: "InterVariable", withExtension: "ttf") else { return }
        fontsRegistered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

// MARK: - Buttons

/// The main action: a white capsule with dark text («Смотреть»). Its height is the size tier's control height;
/// `size` 13 or less asks for the small capsule.
struct KPPrimaryButtonStyle: ButtonStyle {
    var size: CGFloat = 15

    @Environment(\.kpMetrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        let small = size <= 13
        return KPHoverable { hover in
            configuration.label
                .font(KP.font(small ? 12.5 : metrics.controlFont, .semibold))
                .foregroundStyle(KP.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false) // the capsule grows with its label, never truncates it
                .padding(.horizontal, small ? 12 : metrics.controlPadding)
                .frame(height: small ? metrics.controlSmall : metrics.control)
                .background(Capsule().fill(hover ? Color.white : KP.fg))
                .shadow(color: .white.opacity(hover ? 0.2 : 0), radius: 16)
                .scaleEffect(configuration.isPressed ? 0.96 : hover ? 1.03 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.62), value: hover)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

/// A sheet's action, a fixed-width capsule: the main one white, the rest a chip; faded while it can't be used.
struct KPSheetButtonStyle: ButtonStyle {
    var primary = false
    var enabled = true
    var width: CGFloat = 240

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let on = enabled && isEnabled
        return KPHoverable { hover in
            configuration.label
                .font(KP.font(14, .semibold))
                .foregroundStyle(primary ? KP.ink : KP.fg)
                .lineLimit(1)
                .frame(width: width, height: 34)
                .background(Capsule().fill(primary ? (hover && on ? Color.white : KP.fg) : (hover && on ? KP.chipStrong : KP.chip)))
                .contentShape(Capsule())
                .opacity(on ? 1 : 0.38)
                .scaleEffect(configuration.isPressed && on ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.2), value: on)
        }
    }
}

extension View {
    /// A text field's well in a sheet.
    func kpField() -> some View {
        background(KP.chip.opacity(0.55), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(KP.line, in: .rect(cornerRadius: 12, style: .continuous).stroke(lineWidth: 1))
    }
}

/// Everything else next to it: a translucent capsule («Подробнее», «В закладки»); `size` 13 or less is the small one.
struct KPSecondaryButtonStyle: ButtonStyle {
    var size: CGFloat = 15

    @Environment(\.kpMetrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        let small = size <= 13
        return KPHoverable { hover in
            configuration.label
                .font(KP.font(small ? 12.5 : metrics.controlFont, .semibold))
                .foregroundStyle(KP.fg)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, small ? 12 : metrics.controlPadding)
                .frame(height: small ? metrics.controlSmall : metrics.control)
                .background(Capsule().fill(hover ? KP.chipStrong : KP.chip))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : hover ? 1.03 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.62), value: hover)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

/// A round icon button (the row arrows, the player's controls).
struct KPIconButtonStyle: ButtonStyle {
    /// nil: the size tier's control height (next to capsules); a fixed value for the top bar, rows and sheets.
    var diameter: CGFloat? = nil
    var filled = true

    @Environment(\.kpMetrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        let diameter = diameter ?? metrics.control
        return KPHoverable { hover in
            configuration.label
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(hover ? KP.fg : KP.fg80)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(filled ? (hover ? KP.chipStrong : KP.chip) : (hover ? KP.chip : .clear)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.9 : hover && filled ? 1.06 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.62), value: hover)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

/// A choice in a row of choices (voice-over, season, episode, quality): the chosen one is white.
struct KPPill: View {
    let title: String
    /// A quieter second part after the title (a voice-over's popularity «42%», «с рекламой»).
    var detail: String? = nil
    var selected = false
    var dimmed = false
    var progress: Double? = nil
    let action: () -> Void

    @State private var hover = false
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: title)
                    .font(KP.font(metrics.pillFont, selected ? .semibold : .medium))
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(KP.font(metrics.pillFont - 1.5, .medium).monospacedDigit())
                        .opacity(0.55)
                }
            }
                .lineLimit(1)
                .foregroundStyle(selected ? KP.ink : dimmed ? KP.fg38 : KP.fg)
                .padding(.horizontal, metrics.pillPaddingH)
                .padding(.vertical, metrics.pillPaddingV)
                .background {
                    Capsule().fill(selected ? KP.fg : hover ? KP.chipStrong : KP.chip)
                }
                .overlay(alignment: .bottom) {
                    if let progress, progress > 0, !selected {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(KP.sun)
                                .frame(width: max(4, proxy.size.width * min(1, progress)), height: 3)
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 12)
                        .offset(y: -3)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
    }
}

/// Hover state for button styles (a ButtonStyle can't hold @State itself).
struct KPHoverable<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hover = false

    var body: some View {
        content(hover).onHover { hover = $0 }
    }
}

// MARK: - Small pieces

/// A small rounded label over a poster or in a line of facts («IMDb 7.8», «16+», «Сериал»).
struct KPBadge: View {
    let text: String
    var color: Color = .black.opacity(0.62)
    var foreground: Color = KP.fg

    var body: some View {
        Text(verbatim: text)
            .font(KP.font(11, .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color))
    }
}

/// A rating in the facts line: the source's name dim, the number bright.
struct KPRatingChip: View {
    let source: String
    let value: String

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: source).foregroundStyle(KP.fg55)
            Text(verbatim: value).foregroundStyle(KP.fg)
        }
        .font(KP.font(metrics.facts - 0.5, .semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KP.chip))
    }
}

/// «Кино» white, «Похуй» in the sun's gradient, the sun before them.
struct KPLogo: View {
    var height: CGFloat = 26
    var sun: Image?

    var body: some View {
        HStack(spacing: height * 0.28) {
            if let sun {
                sun
                    .resizable()
                    .interpolation(.high)
                    .frame(width: height * 1.35, height: height * 1.35)
                    .padding(-height * 0.12)
            }
            HStack(spacing: 0) {
                Text(verbatim: "Кино").foregroundStyle(KP.fg)
                Text(verbatim: "Похуй").foregroundStyle(KP.sunGradient)
            }
            .font(KP.font(height * 0.86, .heavy))
            .tracking(-height * 0.02)
        }
    }
}

/// The section heading over a row or a grid.
struct KPSectionTitle: View {
    let title: String
    var count: Int? = nil

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: title)
                .font(KP.font(metrics.section, .bold))
                .foregroundStyle(KP.fg)
            if let count {
                Text(verbatim: "\(count)")
                    .font(KP.font(metrics.sectionCount, .medium))
                    .foregroundStyle(KP.fg38)
            }
        }
    }
}

extension View {
    /// The app's background behind a screen.
    func kpScreenBackground() -> some View {
        background(KP.bg.ignoresSafeArea())
    }

    /// A screen under the top bar: no system toolbar or back button (they live in the top bar and in the screen's
    /// own header), the dark scheme, the app's background.
    func kpScreenChrome() -> some View {
        // Not .toolbar(.hidden, for: .windowToolbar): that takes the window's close/minimise buttons with it.
        toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .navigationBarBackButtonHidden()
            .environment(\.colorScheme, .dark)
            .background(KP.bg)
    }
}

