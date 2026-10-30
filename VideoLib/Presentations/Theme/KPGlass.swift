import SwiftUI

// Liquid Glass (macOS 26 and later) for everything that floats: the top bar's capsules, buttons over pictures, the
// player's controls. Before macOS 26, a dark material in the same shape.

extension View {
    func kpGlass(interactive: Bool = false, tint: Color? = nil) -> some View {
        kpGlass(in: Capsule(), interactive: interactive, tint: tint)
    }

    @ViewBuilder
    func kpGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill((tint ?? .black).opacity(0.25))
                }
                .environment(\.colorScheme, .dark)
            }
        }
    }
}

/// Glass shapes inside blend into each other and morph when they appear or move (macOS 26 and later).
struct KPGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// A round glass button (the player's controls). diameter nil: the player's transport size for the window
/// (`metrics.playerTransport`). onPress: told when it's held, e.g. to keep the player's controls up while a menu
/// behind the button is open.
struct KPGlassIconButtonStyle: ButtonStyle {
    var diameter: CGFloat? = nil
    var symbolScale: CGFloat = 0.4
    var onPress: ((Bool) -> Void)? = nil

    @Environment(\.kpMetrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        let diameter = diameter ?? metrics.playerTransport
        return KPHoverable { hover in
            configuration.label
                .font(.system(size: diameter * symbolScale, weight: .semibold))
                .foregroundStyle(KP.fg)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .kpGlass(in: Circle(), interactive: true)
                .scaleEffect(configuration.isPressed ? 0.9 : hover ? 1.06 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.62), value: hover)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { onPress?(configuration.isPressed) }
        }
    }
}

/// A glass capsule with a label («Серии», «Смотреть титры»), as tall as the round ones beside it: its height comes
/// from the window's tier, not from the font, so a row of glass buttons lines up.
struct KPGlassButtonStyle: ButtonStyle {
    /// nil: 13.5, or 13 in a laptop-sized window.
    var size: CGFloat? = nil
    /// nil: the player's transport size.
    var height: CGFloat? = nil
    var onPress: ((Bool) -> Void)? = nil

    @Environment(\.kpMetrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        let size = size ?? (metrics.compact ? 13 : 13.5)
        return KPHoverable { hover in
            configuration.label
                .font(KP.font(size, .semibold))
                .foregroundStyle(KP.fg)
                .lineLimit(1)
                .padding(.horizontal, metrics.compact ? 12 : 14)
                .frame(height: height ?? metrics.playerTransport)
                .contentShape(Capsule())
                .kpGlass(in: Capsule(), interactive: true)
                .scaleEffect(configuration.isPressed ? 0.95 : hover ? 1.03 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.62), value: hover)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { onPress?(configuration.isPressed) }
        }
    }
}
