import SwiftUI

// MARK: - Poster card

/// A title's poster (2:3) with its name and facts under it. Under the pointer it grows a little and gets the
/// white ring the TV draws around the focused poster. The caller wraps it in a link or a button.
struct KPPosterCard<Poster: View>: View {
    var title: String?
    var subtitle: String?
    /// Top left: the rating («7.8»), as on the site, coloured as on Kinopoisk.
    var rating: String?
    var ratingColor: Color = .black.opacity(0.62)
    /// Top right: what it is («Сериал»), when the row mixes kinds.
    var kind: String?
    /// Bottom of the poster: what's new or where you are («2 сезон 5 серия»).
    var note: String?
    /// 0…1: watched so far, a bar along the bottom.
    var progress: Double?
    /// nil: the size tier's card width.
    var width: CGFloat?
    /// Height over width: 1.5 for a poster, 0.6 for a collection's wide cover.
    var aspect: CGFloat = 1.5
    /// false: it doesn't grow or ring under the pointer (a card dimmed by «Скрыть» or «Не моё», under its note).
    var interactive = true
    @ViewBuilder var poster: () -> Poster

    @State private var hover = false
    @Environment(\.kpMetrics) private var metrics
    @Environment(\.kpScrollState) private var scrollState

    var body: some View {
        let width = width ?? metrics.card
        VStack(alignment: .leading, spacing: 8) {
            poster()
                .frame(width: width, height: width * aspect)
                .scaleEffect(KPDemo.posterScale, anchor: .top)
                .clipShape(RoundedRectangle(cornerRadius: KP.posterRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let rating {
                        KPBadge(text: rating, color: ratingColor).padding(7)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let kind {
                        KPBadge(text: kind).padding(7)
                    }
                }
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let note {
                            KPBadge(text: note, color: .black.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let progress {
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.25))
                                Capsule().fill(KP.sunGradient)
                                    .frame(width: max(6, (width - 16) * min(1, max(0, progress))))
                            }
                            .frame(height: 4)
                        }
                    }
                    .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: KP.posterRadius + 4, style: .continuous)
                        .strokeBorder(KP.fg, lineWidth: 3)
                        .padding(-5)
                        .opacity(lifted ? 1 : 0)
                }
                // A shadow only under the pointer: a hundred soft shadows make scrolling slow.
                .shadow(color: .black.opacity(lifted ? 0.6 : 0), radius: lifted ? 22 : 0, y: lifted ? 12 : 0)
                .scaleEffect(lifted ? 1.05 : 1, anchor: .bottom)

            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(verbatim: title)
                            .font(KP.font(metrics.cardTitle, .semibold))
                            .foregroundStyle(hover ? KP.fg : KP.fg80)
                            .lineLimit(2)
                    }
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(KP.font(metrics.cardSubtitle))
                            .foregroundStyle(KP.fg38)
                            .lineLimit(1)
                    }
                }
                .frame(width: width, height: metrics.captionHeight, alignment: .topLeading) // every row the same height
            }
        }
        .frame(width: width)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: interactive)
        .contentShape(Rectangle())
        .onHover { inside in
            // Cards gliding under a still pointer while scrolling don't light up (leaving always counts).
            if inside, scrollState?.isScrolling == true { return }
            hover = inside
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: hover)
        .zIndex(hover ? 1 : 0)
    }

    /// Grown, ringed and shadowed: under the pointer, unless it's a card that stays still.
    private var lifted: Bool {
        hover && interactive
    }
}

/// A grey poster-sized block while a row or a grid loads.
struct KPPosterPlaceholder: View {
    var width: CGFloat?
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        let width = width ?? metrics.card
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: KP.posterRadius, style: .continuous)
                .fill(KP.surface)
                .frame(width: width, height: width * 1.5)
            RoundedRectangle(cornerRadius: 4).fill(KP.surface).frame(width: width * 0.7, height: 12)
            RoundedRectangle(cornerRadius: 4).fill(KP.surface).frame(width: width * 0.45, height: 10)
        }
        .phaseAnimator([1.0, 0.55]) { view, opacity in
            view.opacity(opacity)
        } animation: { _ in
            .easeInOut(duration: 0.9)
        }
    }
}

// MARK: - Row

/// A titled row of cards that scrolls sideways: by trackpad, or a page at a time with the arrows that show up
/// under the pointer.
struct KPRow<Item: Identifiable, Card: View>: View where Item.ID: Hashable {
    let title: String
    var count: Int?
    let items: [Item]
    /// nil: the size tier's card width and gap.
    var itemWidth: CGFloat?
    var spacing: CGFloat?
    /// «Все»: the row's full list.
    var seeAll: (() -> Void)?
    /// Cards with a name under the picture (the arrows centre on the picture above it); false for tiles.
    var captioned = true
    /// Where the row opens (e.g. just before the episode you're on); nil: at its start.
    var startAt: Item.ID?
    @ViewBuilder var card: (Item) -> Card

    @State private var hover = false
    @State private var position: Item.ID?
    @State private var visibleWidth: CGFloat = 0
    @Environment(\.kpMetrics) private var metrics

    private var width: CGFloat { itemWidth ?? metrics.card }
    private var gap: CGFloat { spacing ?? metrics.cardGap }
    private var perPage: Int { max(1, Int((visibleWidth - KP.gutter * 2 + gap) / (width + gap))) }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.stackGap) {
            if !title.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    KPSectionTitle(title: title, count: count)
                    Spacer()
                    if let seeAll {
                        KPLinkButton(title: "Все", action: seeAll)
                    }
                }
                .padding(.horizontal, KP.gutter)
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: gap) {
                    ForEach(items) { item in
                        card(item).id(item.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, KP.gutter)
                .padding(.vertical, 12) // room for the hover ring and the shadow
            }
            .scrollIndicators(.never)
            .kpReportsScrolling()
            .scrollPosition(id: $position, anchor: .leading)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .padding(.vertical, -12)
            .overlay {
                HStack {
                    arrow(left: true)
                        .opacity(currentIndex > 0 ? 1 : 0)
                    Spacer()
                    arrow(left: false)
                        .opacity(currentIndex + perPage < items.count ? 1 : 0)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, captioned ? metrics.captionHeight + 8 : 0) // centred on the posters, not the names under them
                .opacity(hover && items.count > perPage ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hover)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
        .onHover { hover = $0 }
        .onAppear {
            if position == nil, let startAt { position = startAt }
        }
    }

    private var currentIndex: Int {
        position.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
    }

    private func arrow(left: Bool) -> some View {
        Button {
            let ids = items.map(\.id)
            let current = currentIndex
            let target = left ? max(0, current - perPage) : min(ids.count - 1, current + perPage)
            withAnimation(.smooth(duration: 0.45)) { position = ids[target] }
        } label: {
            Image(systemName: left ? "chevron.left" : "chevron.right")
        }
        .buttonStyle(KPIconButtonStyle(diameter: metrics.rowArrow))
        .background(Circle().fill(.black.opacity(0.55)))
        .shadow(color: .black.opacity(0.5), radius: 10)
    }
}

/// «Все ›»: a quiet text link that brightens under the pointer.
struct KPLinkButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }
            .font(KP.font(13, .semibold))
            .foregroundStyle(hover ? KP.fg : KP.fg55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Grid

/// Cards in a grid that fills the width (lists, search results, bookmarks).
struct KPGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// nil: the size tier's card width.
    var itemWidth: CGFloat?
    @ViewBuilder var card: (Item) -> Card

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        let width = itemWidth ?? metrics.card
        LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width + 16), spacing: metrics.compact ? 16 : 18, alignment: .top)], alignment: .leading, spacing: metrics.compact ? 22 : 26) {
            ForEach(items) { item in
                card(item)
            }
        }
        .padding(.horizontal, KP.gutter)
    }
}

// MARK: - Hero

/// The big picture at the top of Home and of a title's page, as on the TV: the site's large poster is tall, so
/// it stands sharp at the right, fading into the rest, and a blurred copy of it washes the whole width. The
/// title, facts, description and buttons sit over the dark left side. `art` is drawn twice (the copy and the
/// sharp one): a resizable image.
struct KPHero<Art: View, Actions: View>: View {
    var kicker: String?
    let title: String
    var original: String?
    var facts: [String] = []
    var ratings: [(source: String, value: String)] = []
    var description: String?
    var descriptionLines = 3
    /// A title's page: the taller banner of the two (`height` overrides both).
    var details = false
    var height: CGFloat?
    /// The facts and the description are on their way: grey stand-ins in their places, so nothing jumps when they come.
    var isPlaceholder = false
    /// The text settles a little on appearing, as the page fade lifts (a title's page).
    var entrance = false
    /// The name the title's size is chosen by (a page keeps the card's name's size when the full name comes in, so
    /// the font doesn't jump from 52 to 40 mid-page).
    var titleSizeBasis: String?
    @ViewBuilder var art: () -> Art
    @ViewBuilder var actions: () -> Actions

    @State private var settled = false
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.kpMetrics) private var metrics

    private var shown: Bool { !entrance || entered }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let sharpWidth = min(w * 0.62, h * 0.95)
                ZStack(alignment: .trailing) {
                    // The wash is blurred at an eighth of its size and scaled up: the same look (it's a 60 pt blur) for a
                    // sixty-fourth of the pixels, drawn once into a bitmap (drawingGroup) beside the Ken Burns zoom.
                    art()
                        .scaledToFill()
                        .frame(width: w / 8, height: h / 8)
                        .clipped()
                        .blur(radius: 60 / 8, opaque: true)
                        .saturation(1.2)
                        .drawingGroup()
                        .scaleEffect(8)
                        .frame(width: w, height: h)
                        .opacity(0.5)

                    art()
                        .scaledToFill()
                        .frame(width: sharpWidth, height: h, alignment: .top)
                        .scaleEffect(settled || reduceMotion ? 1 : 1.07, anchor: .center)
                        .clipped()
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.7), location: 0.3),
                                .init(color: .black, location: 0.55),
                            ], startPoint: .leading, endPoint: .trailing)
                        }
                }
                .frame(width: w, height: h)
                .overlay {
                    // The left side darkens into the background behind the text.
                    LinearGradient(stops: [
                        .init(color: KP.bg.opacity(0.96), location: 0),
                        .init(color: KP.bg.opacity(0.85), location: 0.28),
                        .init(color: KP.bg.opacity(0.35), location: 0.5),
                        .init(color: .clear, location: 0.68),
                    ], startPoint: .leading, endPoint: .trailing)
                }
                .overlay {
                    LinearGradient(stops: [
                        .init(color: KP.bg.opacity(0.5), location: 0),
                        .init(color: .clear, location: 0.2),
                        .init(color: .clear, location: 0.62),
                        .init(color: KP.bg, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            }

            VStack(alignment: .leading, spacing: metrics.heroSpacing) {
                if let kicker {
                    Text(verbatim: kicker.uppercased())
                        .font(KP.font(metrics.kicker, .bold))
                        .tracking(1.6)
                        .foregroundStyle(KP.sun)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: title)
                        .font(KP.font((titleSizeBasis ?? title).count > 28 ? metrics.displayLong : metrics.display, .heavy))
                        .tracking(metrics.compact ? -0.6 : -0.8)
                        .foregroundStyle(KP.fg)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.4), radius: 20)
                    if isPlaceholder || original?.isEmpty == false {
                        ZStack(alignment: .leading) {
                            if isPlaceholder {
                                KPSkeleton(width: 170, height: 14)
                                    .padding(.vertical, 3.5)
                                    .transition(.opacity)
                            } else if let original {
                                Text(verbatim: original)
                                    .font(KP.font(metrics.original, .medium))
                                    .foregroundStyle(KP.fg55)
                                    .lineLimit(1)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                // Each late slot is a ZStack: the stand-in and the real line overlap while they cross-fade, instead
                // of stacking up for a moment and pushing the title.
                if isPlaceholder || !facts.isEmpty || !ratings.isEmpty {
                    ZStack(alignment: .leading) {
                        if isPlaceholder {
                            HStack(spacing: 10) {
                                KPSkeleton(width: 72, height: 24, radius: 6)
                                KPSkeleton(width: 62, height: 24, radius: 6)
                                KPSkeleton(width: 280, height: 13)
                            }
                            .transition(.opacity)
                        } else {
                            HStack(spacing: 10) {
                                ForEach(Array(ratings.enumerated()), id: \.offset) { _, rating in
                                    KPRatingChip(source: rating.source, value: rating.value)
                                }
                                if !facts.isEmpty {
                                    Text(verbatim: facts.joined(separator: "  ·  "))
                                        .font(KP.font(metrics.facts, .medium))
                                        .foregroundStyle(KP.fg70)
                                        .lineLimit(1)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                }
                if isPlaceholder || description?.isEmpty == false {
                    ZStack(alignment: .topLeading) {
                        if isPlaceholder {
                            // As many bars as the description's lines, on its line pitch (Inter's line is ~1.21 of its size,
                            // plus the line spacing): a long description, the usual case, then takes exactly their place.
                            let line = metrics.body * 1.21
                            VStack(alignment: .leading, spacing: line + 3 - 11) {
                                ForEach(0 ..< descriptionLines, id: \.self) { index in
                                    KPSkeleton(width: index == descriptionLines - 1 ? 300 : [560, 540, 550, 520][index % 4] * (metrics.compact ? 0.9 : 1), height: 11)
                                }
                            }
                            .padding(.vertical, (line - 11) / 2)
                            .transition(.opacity)
                        } else if let description {
                            Text(verbatim: description)
                                .font(KP.font(metrics.body))
                                .lineSpacing(3)
                                .foregroundStyle(KP.fg70)
                                .lineLimit(descriptionLines)
                                .frame(maxWidth: metrics.compact ? 540 : 600, alignment: .leading)
                                .transition(.opacity)
                        }
                    }
                }
                // At its own width: the text column's 700 pt mustn't wrap a long «Смотреть · 1 сезон, 1 серия».
                HStack(spacing: 12) {
                    actions()
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 6)
            }
            .frame(maxWidth: metrics.heroColumn, alignment: .leading)
            .padding(.horizontal, KP.gutter)
            .padding(.bottom, metrics.heroBottom)
            .offset(y: shown || reduceMotion ? 0 : 12)
        }
        .frame(height: height ?? (details ? metrics.heroDetails : metrics.heroHome))
        .frame(maxWidth: .infinity)
        .clipped()
        .onAppear {
            withAnimation(.easeOut(duration: 2.4)) { settled = true }
            if entrance, !entered {
                withAnimation(.smooth(duration: 0.6)) { entered = true }
            }
        }
    }
}

// MARK: - Top bar

/// Logo, the sections, and what's on the right (search, settings, the account), over the top of the window on a
/// frosted dark band, so posters and buttons scrolling under it never show through; the window's traffic lights are
/// to its left. The chosen section's underline slides to the next one.
struct KPTopBar<Tab: Hashable & Identifiable, Trailing: View>: View {
    let tabs: [Tab]
    let selected: Tab
    let title: (Tab) -> String
    let select: (Tab) -> Void
    var canGoBack = false
    var back: () -> Void = {}
    var logo: Image?
    /// The logo and name after the back button (off by default; Settings turns it on).
    var showsLogo = false
    @ViewBuilder var trailing: () -> Trailing

    @Namespace private var underline
    @State private var backShown = false
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        HStack(spacing: 20) {
            // Its place is kept when there's nowhere to go back to, so the logo and sections never shift.
            ZStack {
                if backShown {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(KPIconButtonStyle(diameter: metrics.topBarControl))
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Назад")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: metrics.topBarControl, height: metrics.topBarControl)
            .padding(.trailing, -6)
            // Its own transaction: the page fade swaps the stack with animations off, which would make it pop.
            .onChange(of: canGoBack, initial: true) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { backShown = canGoBack }
            }

            if showsLogo {
                KPLogo(height: 20, sun: logo)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }

            HStack(spacing: metrics.compact ? 18 : 20) {
                ForEach(tabs) { tab in
                    KPTabButton(title: title(tab), selected: tab == selected, underline: underline) { select(tab) }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                trailing()
            }
        }
        .animation(.smooth(duration: 0.3), value: showsLogo)
        .padding(.leading, 86) // the traffic lights
        .padding(.trailing, KP.gutter - 12)
        .frame(height: KP.topBarHeight)
        .background {
            // The window has no title bar: it's moved by the empty parts of this one.
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
        .background {
            // A plain gradient, not a material: a backdrop blur across the window's width would be sampled again on
            // every frame of scrolling under it.
            LinearGradient(stops: [
                .init(color: KP.bg.opacity(0.95), location: 0),
                .init(color: KP.bg.opacity(0.88), location: 0.8),
                .init(color: KP.bg.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: KP.topBarHeight + 10)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
    }
}

struct KPTabButton: View {
    let title: String
    let selected: Bool
    let underline: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(KP.font(metrics.tabFont, selected ? .bold : .medium))
                .foregroundStyle(selected ? KP.fg : hover ? KP.fg80 : KP.fg55)
                .overlay(alignment: .bottom) {
                    if selected {
                        Capsule()
                            .fill(KP.fg)
                            .frame(height: 2)
                            .offset(y: 7)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
    }
}

// MARK: - States

/// A screen that couldn't load: what went wrong and «Повторить».
struct KPErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(KP.fg38)
            Text(verbatim: message)
                .font(KP.font(14, .medium))
                .foregroundStyle(KP.fg70)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Повторить", action: retry)
                .buttonStyle(KPSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nothing here (an empty list, no results).
struct KPEmptyView: View {
    let message: String
    var symbol = "film.stack"

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(KP.fg38)
            Text(verbatim: message)
                .font(KP.font(14, .medium))
                .foregroundStyle(KP.fg55)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The app's own spinner: three dots in the sun's colour.
struct KPLoadingView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 5
            HStack(spacing: 8) {
                ForEach(0 ..< 3) { i in
                    Circle()
                        .fill(KP.sun)
                        .frame(width: 9, height: 9)
                        .opacity(0.3 + 0.7 * max(0, sin(t - Double(i) * 0.7)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension KP {
    /// Kinopoisk's colours for a rating: green from 7, grey in the middle, red under 5.
    static func ratingColor(_ value: Float) -> Color {
        value >= 7 ? Color(red: 0.2, green: 0.62, blue: 0.27) : value >= 5 ? Color(white: 0.36) : Color(red: 0.78, green: 0.2, blue: 0.18)
    }

    static func ratingText(_ value: Float) -> String {
        String(format: "%.1f", value)
    }
}

// MARK: - Screen header

/// A screen's big title under the top bar, with its own controls (filters, sorting) at the right.
struct KPScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: title)
                    .font(KP.font(metrics.pageTitle, .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(KP.fg)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(KP.font(metrics.compact ? 13 : 14, .medium))
                        .foregroundStyle(KP.fg55)
                }
            }
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                trailing()
            }
        }
        .padding(.horizontal, KP.gutter)
    }
}

extension KPScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension View {
    /// Room for the top bar above a screen's own content.
    func kpBelowTopBar(extra: CGFloat? = nil) -> some View {
        modifier(KPBelowTopBar(extra: extra))
    }
}

private struct KPBelowTopBar: ViewModifier {
    let extra: CGFloat?
    @Environment(\.kpMetrics) private var metrics

    func body(content: Content) -> some View {
        content.padding(.top, KP.topBarHeight + (extra ?? (metrics.compact ? 16 : 22)))
    }
}

// MARK: - Sheet

/// A sheet in the app's look: an icon in the sun's colour, the title, a close button in the corner, the content on
/// the app's background.
struct KPSheet<Content: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var width: CGFloat = 560
    var height: CGFloat?
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KP.sun)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(KP.sun.opacity(0.14)))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title)
                        .font(KP.font(19, .bold))
                        .foregroundStyle(KP.fg)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .font(KP.font(14, .medium))
                            .foregroundStyle(KP.fg55)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(KPIconButtonStyle(diameter: 26))
                .keyboardShortcut(.cancelAction)
            }

            content()
        }
        .padding(20)
        .frame(width: width)
        .frame(height: height)
        .background(KP.bg)
        .environment(\.colorScheme, .dark)
    }
}

/// A person's round picture; with none (or the site's stock silhouette), their initial on a colour of their own.
struct KPAvatar: View {
    let url: String
    let name: String
    var size: CGFloat = 34

    private var hasPhoto: Bool {
        !url.isEmpty && !url.contains("noavatar") && !url.contains("nopersonphoto")
    }

    private var initial: String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    private static let palette: [(Color, Color)] = [
        (Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.93, green: 0.33, blue: 0.1)),
        (Color(red: 0.36, green: 0.62, blue: 1), Color(red: 0.2, green: 0.36, blue: 0.9)),
        (Color(red: 0.3, green: 0.82, blue: 0.6), Color(red: 0.1, green: 0.55, blue: 0.45)),
        (Color(red: 0.78, green: 0.5, blue: 1), Color(red: 0.5, green: 0.28, blue: 0.85)),
        (Color(red: 1, green: 0.45, blue: 0.55), Color(red: 0.82, green: 0.2, blue: 0.38)),
        (Color(red: 0.95, green: 0.8, blue: 0.3), Color(red: 0.8, green: 0.55, blue: 0.1)),
    ]

    private var colors: (Color, Color) {
        // A stable pick per name (String.hashValue changes between launches).
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[sum % Self.palette.count]
    }

    var body: some View {
        Group {
            if hasPhoto {
                KPRemoteImage(url: url, downsample: CGSize(width: size * 2, height: size * 2))
            } else {
                ZStack {
                    LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(verbatim: initial)
                        .font(KP.font(size * 0.44, .heavy))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// A grey stand-in for something on its way (text, a button, a picture), breathing softly until it comes.
struct KPSkeleton<S: Shape>: View {
    var width: CGFloat?
    var height: CGFloat
    var shape: S
    var fill: Color = KP.fg.opacity(0.09)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A phase animator keeps the breathing to the opacity alone: a repeating withAnimation started on appear can
        // catch the page's own movement (a push) and repeat that too.
        shape
            .fill(fill)
            .frame(width: width, height: height)
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
    }
}

extension KPSkeleton where S == RoundedRectangle {
    init(width: CGFloat? = nil, height: CGFloat, radius: CGFloat? = nil, fill: Color = KP.fg.opacity(0.09)) {
        self.init(width: width, height: height, shape: RoundedRectangle(cornerRadius: radius ?? height / 2, style: .continuous), fill: fill)
    }
}
