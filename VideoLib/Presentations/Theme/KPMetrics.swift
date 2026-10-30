import SwiftUI

/// Sizes in two tiers: regular for big windows and external displays, compact for a laptop-sized window (a MacBook
/// Air or Pro 14 full screen is about 1470×956 / 1512×982 pt), where TV-sized type and controls feel oversized and
/// the first row of posters falls below the fold. Each value is set per tier, not scaled, so rings, radii and decode
/// sizes stay exact. The shell and the player window each set it from their own size (`kpMetricsFromWindow()`).
struct KPMetrics: Equatable, Sendable {
    var compact: Bool

    // Type
    /// A banner's title; a long one (over 28 characters) gets `displayLong`.
    var display: CGFloat
    var displayLong: CGFloat
    /// A screen's own title («Каталог», «Комментарии»).
    var pageTitle: CGFloat
    /// A row's or a section's heading.
    var section: CGFloat
    var sectionCount: CGFloat
    /// Body text: a banner's description, facts.
    var body: CGFloat
    var facts: CGFloat
    var kicker: CGFloat
    var original: CGFloat

    // Banner
    var heroHome: CGFloat
    var heroDetails: CGFloat
    var heroColumn: CGFloat
    var heroBottom: CGFloat
    var heroSpacing: CGFloat

    // Rows and cards
    var card: CGFloat
    var cardGap: CGFloat
    var captionHeight: CGFloat
    var cardTitle: CGFloat
    var cardSubtitle: CGFloat
    var rowArrow: CGFloat
    /// Between a heading and what it heads.
    var stackGap: CGFloat
    /// Between the sections of a screen.
    var sectionGap: CGFloat
    var screenBottom: CGFloat

    // Controls
    /// A capsule or round button's height («Смотреть», «В закладки», the banner's icons).
    var control: CGFloat
    var controlFont: CGFloat
    var controlPadding: CGFloat
    /// The small capsule («Войти», «Фильтры»).
    var controlSmall: CGFloat
    /// The top bar's round buttons and its back button.
    var topBarControl: CGFloat
    var tabFont: CGFloat
    var pillFont: CGFloat
    var pillPaddingH: CGFloat
    var pillPaddingV: CGFloat

    // Title page
    var episodeTile: CGSize
    var episodeNumber: CGFloat
    var personPhoto: CGFloat
    var personColumn: CGFloat

    // Player
    var playerMain: CGFloat
    var playerSkip: CGFloat
    var playerTransport: CGFloat
    var playerTitle: CGFloat
    var playerSubtitle: CGFloat

    static let regular = KPMetrics(
        compact: false,
        display: 46, displayLong: 36, pageTitle: 30, section: 20, sectionCount: 14, body: 15, facts: 14, kicker: 12, original: 15,
        heroHome: 620, heroDetails: 660, heroColumn: 660, heroBottom: 36, heroSpacing: 14,
        card: 168, cardGap: 16, captionHeight: 51, cardTitle: 13.5, cardSubtitle: 12, rowArrow: 36, stackGap: 12, sectionGap: 36, screenBottom: 44,
        control: 38, controlFont: 14, controlPadding: 20, controlSmall: 30, topBarControl: 28, tabFont: 13.5, pillFont: 13, pillPaddingH: 14, pillPaddingV: 7,
        episodeTile: CGSize(width: 176, height: 99), episodeNumber: 34, personPhoto: 84, personColumn: 100,
        playerMain: 76, playerSkip: 52, playerTransport: 38, playerTitle: 28, playerSubtitle: 14
    )

    static let compact = KPMetrics(
        compact: true,
        display: 40, displayLong: 32, pageTitle: 26, section: 18, sectionCount: 13, body: 14, facts: 13, kicker: 11, original: 14,
        heroHome: 540, heroDetails: 590, heroColumn: 640, heroBottom: 28, heroSpacing: 12,
        card: 148, cardGap: 14, captionHeight: 49, cardTitle: 13, cardSubtitle: 11.5, rowArrow: 32, stackGap: 10, sectionGap: 28, screenBottom: 36,
        control: 32, controlFont: 13, controlPadding: 16, controlSmall: 28, topBarControl: 28, tabFont: 13, pillFont: 13, pillPaddingH: 12, pillPaddingV: 6,
        episodeTile: CGSize(width: 160, height: 90), episodeNumber: 30, personPhoto: 72, personColumn: 88,
        playerMain: 64, playerSkip: 44, playerTransport: 34, playerTitle: 24, playerSubtitle: 13
    )

    /// Compact below 1600 pt wide or 960 pt tall (the window's size, not the screen's).
    static func `for`(_ size: CGSize) -> KPMetrics {
        size.width < 1600 || size.height < 960 ? .compact : .regular
    }
}

extension EnvironmentValues {
    @Entry var kpMetrics = KPMetrics.regular
}

extension View {
    /// Sets the tier from this view's size (a window's root); it changes only when a threshold is crossed.
    func kpMetricsFromWindow() -> some View {
        modifier(KPMetricsFromWindow())
    }
}

private struct KPMetricsFromWindow: ViewModifier {
    @State private var metrics = KPMetrics.regular

    func body(content: Content) -> some View {
        content
            .environment(\.kpMetrics, metrics)
            .onGeometryChange(for: KPMetrics.self) { KPMetrics.for($0.size) } action: { metrics = $0 }
    }
}
