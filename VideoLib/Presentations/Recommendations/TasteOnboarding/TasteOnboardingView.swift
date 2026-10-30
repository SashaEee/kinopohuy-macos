import ComposableArchitecture
import Kingfisher
import RecommenderCore
import SwiftUI

/// The taste stack's sheet: «Мы уже кое-что знаем» with your taste as chips; then your own titles one by one, a big
/// poster and «Не моё · Нравится · Обожаю · Не помню» (1 2 3 0, or the arrows), the card flying off the way it was
/// answered; then «Чего не показывать?». Under a minute, «Пропустить» in the corner of every step.
struct TasteOnboardingView: View {
    let store: StoreOf<TasteOnboardingFeature>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The answer the current card is flying off with (then the next one comes in).
    @State private var flying: OnboardingChoice?
    @State private var forward = true

    private static let posterSize = CGSize(width: 212, height: 318)
    private static var posterPixels: CGSize { CGSize(width: posterSize.width * 2, height: posterSize.height * 2) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 18)
                .padding(.horizontal, 22)

            ZStack {
                if store.isLoading {
                    KPLoadingView()
                        .transition(.opacity)
                } else {
                    switch store.step {
                    case .intro:
                        intro.transition(stepTransition)
                    case .stack:
                        stack.transition(stepTransition)
                    case .exclusions:
                        exclusions.transition(stepTransition)
                    case .done:
                        done.transition(stepTransition)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
        .frame(width: 640, height: 660)
        .background {
            ZStack(alignment: .top) {
                KP.bg
                // The sun's glow behind the top, as on the welcome screen.
                Rectangle()
                    .fill(EllipticalGradient(colors: [KP.sun.opacity(0.16), KP.sun.opacity(0.05), .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                    .frame(width: 820, height: 480)
                    .offset(y: -270)
            }
        }
        .clipped()
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: store.step)
        .onAppear {
            store.send(.onAppear)
        }
        .onChange(of: store.isFinished) {
            if store.isFinished { dismiss() }
        }
        .onChange(of: store.stack) {
            // The posters come from the cache as each card comes in.
            let urls = store.stack.compactMap { $0.poster.flatMap(URL.init(string:)) }
            ImagePrefetcher(urls: urls, options: [.processor(DownsamplingImageProcessor(size: Self.posterPixels))]).start()
        }
        .onChange(of: store.step) { old, new in
            forward = new.rawValue >= old.rawValue
        }
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Header

    /// The steps as dots; «Назад» on the stack; «Пропустить» (or «Закрыть» at the end) on the right.
    private var header: some View {
        ZStack {
            StepDots(count: 3, current: min(store.step.rawValue, 2), finished: store.step == .done)

            HStack {
                if store.step == .stack, !store.answers.isEmpty {
                    QuietButton(title: "Назад", symbol: "chevron.left") {
                        store.send(.backTapped, animation: .spring(response: 0.38, dampingFraction: 0.82))
                    }
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Вернуть предыдущий тайтл (⌘Z)")
                    .transition(.opacity)
                }
                Spacer()
                if store.step == .done {
                    QuietButton(title: "Закрыть") { store.send(.closeTapped) }
                } else {
                    QuietButton(title: "Пропустить") {
                        store.send(.skipStepTapped, animation: .spring(response: 0.42, dampingFraction: 0.88))
                    }
                    .help(store.step == .intro ? "Сразу к рекомендациям" : "Дальше без этого шага")
                }
            }
        }
        .frame(height: 28)
        .animation(.smooth(duration: 0.2), value: store.answers.isEmpty)
    }

    // MARK: - 1. What we know

    private var intro: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(KP.sunGradient)
                .frame(width: 64, height: 64)
                .background(Circle().fill(KP.sun.opacity(0.13)))

            Text(verbatim: store.tasteChips.isEmpty ? "Начнём с вашего" : "Мы уже кое-что знаем")
                .font(KP.font(26, .heavy))
                .tracking(-0.5)
                .foregroundStyle(KP.fg)
                .padding(.top, 18)

            Text(verbatim: store.tasteChips.isEmpty
                ? "Вкус собирается из «Досмотреть» и просмотров на этом Mac. Отметьте несколько своих тайтлов — подборка сразу станет точнее."
                : "По списку «Досмотреть» и просмотрам на этом Mac. Всё хранится только здесь.")
                .font(KP.font(14, .medium))
                .foregroundStyle(KP.fg55)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 8)

            if !store.tasteChips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(Array(store.tasteChips.enumerated()), id: \.offset) { index, chip in
                        TasteChip(title: chip)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                            .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.04), value: store.tasteChips)
                    }
                }
                .frame(maxWidth: 500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
            }

            if let counts = store.countsLine {
                Text(verbatim: counts)
                    .font(KP.font(12.5, .medium))
                    .foregroundStyle(KP.fg38)
                    .padding(.top, 14)
            }

            Spacer(minLength: 24)

            Button {
                store.send(.startTapped, animation: .spring(response: 0.42, dampingFraction: 0.88))
            } label: {
                Text(verbatim: store.stack.isEmpty ? "Дальше" : "Уточнить за минуту")
            }
            .buttonStyle(KPSheetButtonStyle(primary: true, width: 260))
            .keyboardShortcut(.defaultAction)

            if !store.stack.isEmpty {
                Text(verbatim: "\(store.stack.count) \(RussianPlural.form(store.stack.count, "ваш тайтл", "ваших тайтла", "ваших тайтлов")): одна клавиша на каждый")
                    .font(KP.font(12, .medium))
                    .foregroundStyle(KP.fg38)
                    .padding(.top, 8)
            }

            Button {
                store.send(.skipAllTapped)
            } label: {
                Text(verbatim: "Сразу к рекомендациям")
                    .font(KP.font(13, .semibold))
                    .foregroundStyle(KP.fg55)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }

    // MARK: - 2. Your titles

    private var stack: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: TasteOnboardingRules.counter(index: store.index, total: store.stack.count))
                    .font(KP.font(13, .semibold).monospacedDigit())
                    .foregroundStyle(KP.fg70)
                    .contentTransition(.numericText(value: Double(store.index)))
                StackProgress(total: store.stack.count, done: store.index)
                    .frame(maxWidth: 260)
            }
            .padding(.top, 6)

            Spacer(minLength: 10)

            ZStack {
                if let title = store.current {
                    card(title)
                        .id(title.id)
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .opacity : .scale(scale: 0.93).combined(with: .opacity),
                            removal: .identity
                        ))
                }
            }
            .frame(height: Self.posterSize.height + 74)

            Spacer(minLength: 14)

            HStack(spacing: 10) {
                ForEach(TasteLevel.allCases, id: \.self) { level in
                    ChoiceButton(
                        title: level.title,
                        symbol: level.symbol,
                        hint: "\(level.key) · \(arrow(for: OnboardingChoice(level)))",
                        primary: level == .love,
                        highlighted: flying == OnboardingChoice(level)
                    ) {
                        choose(OnboardingChoice(level))
                    }
                    .keyboardShortcut(KeyEquivalent(level.key), modifiers: [])
                }
            }

            Button {
                choose(.dontRemember)
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: "Не помню")
                    Text(verbatim: "0 · ↓")
                        .font(KP.font(11, .semibold).monospacedDigit())
                        .foregroundStyle(KP.fg38)
                }
                .font(KP.font(13, .semibold))
                .foregroundStyle(KP.fg55)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("0", modifiers: [])
            .padding(.top, 10)
        }
        .background {
            // The arrows, as the buttons' second keys.
            Group {
                Button("") { choose(.notForMe) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { choose(.like) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { choose(.love) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { choose(.dontRemember) }.keyboardShortcut(.downArrow, modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    /// The title: its poster big, its name and facts under it; what it was already rated, if anything.
    private func card(_ title: TitleFeatures) -> some View {
        let offset = flyOffset(flying)
        return VStack(spacing: 12) {
            KPRemoteImage(url: title.poster, downsample: Self.posterPixels, immediate: true)
                .frame(width: Self.posterSize.width, height: Self.posterSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if let previous = store.currentPrevious {
                        Label {
                            Text(verbatim: "Было: \(previous.title.lowercased())")
                        } icon: {
                            Image(systemName: previous.activeSymbol)
                        }
                        .font(KP.font(11.5, .semibold))
                        .foregroundStyle(KP.fg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .padding(8)
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 24, y: 14)

            VStack(spacing: 4) {
                Text(verbatim: title.name)
                    .font(KP.font(18, .bold))
                    .foregroundStyle(KP.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let facts = facts(title) {
                    Text(verbatim: facts)
                        .font(KP.font(12.5, .medium))
                        .foregroundStyle(KP.fg55)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 420)
        }
        .offset(x: offset.width, y: offset.height)
        .rotationEffect(.degrees(flyRotation(flying)), anchor: .bottom)
        .opacity(flying == nil ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    /// «2019 · Сериал · Драмы, Детективы».
    private func facts(_ title: TitleFeatures) -> String? {
        var parts: [String] = []
        if let year = title.year { parts.append(String(year)) }
        if let kind = title.kind.map(Self.kindName) { parts.append(kind) }
        if !title.genres.isEmpty { parts.append(title.genres.prefix(2).joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func kindName(_ kind: TitleKind) -> String {
        switch kind {
        case .film: "Фильм"
        case .series: "Сериал"
        case .cartoon: "Мультфильм"
        case .anime: "Аниме"
        case .show: "ТВ-шоу"
        }
    }

    private func arrow(for choice: OnboardingChoice) -> String {
        switch choice {
        case .notForMe: "←"
        case .like: "↑"
        case .love: "→"
        case .dontRemember: "↓"
        }
    }

    private func flyOffset(_ choice: OnboardingChoice?) -> CGSize {
        switch choice {
        case .notForMe: CGSize(width: -360, height: 30)
        case .love: CGSize(width: 360, height: 30)
        case .like: CGSize(width: 0, height: -260)
        case .dontRemember: CGSize(width: 0, height: 220)
        case nil: .zero
        }
    }

    private func flyRotation(_ choice: OnboardingChoice?) -> Double {
        switch choice {
        case .notForMe: -10
        case .love: 10
        default: 0
        }
    }

    /// The card flies off the way it was answered, then the answer is recorded and the next one comes in.
    private func choose(_ choice: OnboardingChoice) {
        guard flying == nil, store.step == .stack, store.current != nil else { return }
        guard !reduceMotion else {
            store.send(.choose(choice), animation: .easeInOut(duration: 0.2))
            return
        }
        withAnimation(.easeIn(duration: 0.2)) {
            flying = choice
        }
        Task {
            try? await Task.sleep(for: .milliseconds(190))
            store.send(.choose(choice), animation: .spring(response: 0.36, dampingFraction: 0.8))
            // The next card starts where cards rest, not where the last one flew to.
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                flying = nil
            }
        }
    }

    // MARK: - 3. What not to show

    private var exclusions: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            Image(systemName: "eye.slash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(KP.sun)
                .frame(width: 58, height: 58)
                .background(Circle().fill(KP.sun.opacity(0.13)))

            Text(verbatim: "Чего не показывать?")
                .font(KP.font(26, .heavy))
                .tracking(-0.5)
                .foregroundStyle(KP.fg)
                .padding(.top, 16)

            Text(verbatim: "Это уберём из рекомендаций совсем. Изменить можно в настройках.")
                .font(KP.font(14, .medium))
                .foregroundStyle(KP.fg55)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            FlowLayout(spacing: 8) {
                ForEach(ExclusionChip.allCases) { chip in
                    ExclusionChipButton(title: chip.title, selected: store.exclusions.contains(chip)) {
                        store.send(.exclusionToggled(chip), animation: .snappy(duration: 0.2))
                    }
                }
            }
            .frame(maxWidth: 480)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 24)

            VStack(spacing: 10) {
                Text(verbatim: "Возраст")
                    .font(KP.font(12.5, .semibold))
                    .foregroundStyle(KP.fg55)
                HStack(spacing: 6) {
                    ForEach(AgeLimit.allCases) { limit in
                        KPPill(title: limit.title, selected: store.maxAge == limit) {
                            store.send(.maxAgeSelected(limit), animation: .snappy(duration: 0.2))
                        }
                    }
                }
            }
            .padding(.top, 26)

            Spacer(minLength: 24)

            Button {
                store.send(.finishTapped, animation: .spring(response: 0.42, dampingFraction: 0.88))
            } label: {
                Text(verbatim: "Готово")
            }
            .buttonStyle(KPSheetButtonStyle(primary: true, width: 260))
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Done

    private var done: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(KP.ink)
                .frame(width: 64, height: 64)
                .background(Circle().fill(KP.fg))
                .symbolEffect(.bounce, value: store.step == .done)

            Text(verbatim: "Готово")
                .font(KP.font(26, .heavy))
                .tracking(-0.5)
                .foregroundStyle(KP.fg)
                .padding(.top, 18)

            Text(verbatim: summary)
                .font(KP.font(14, .medium))
                .foregroundStyle(KP.fg55)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.top, 8)

            Spacer()

            Button {
                store.send(.closeTapped)
            } label: {
                Text(verbatim: "К рекомендациям")
            }
            .buttonStyle(KPSheetButtonStyle(primary: true, width: 260))
            .keyboardShortcut(.defaultAction)
        }
    }

    /// «Учли 9 оценок. Не покажем: аниме, ужасы. Уточнить вкус можно в настройках.»
    private var summary: String {
        var lines: [String] = []
        let rated = store.ratedCount
        lines.append(rated > 0
            ? "Учли \(rated) \(RussianPlural.form(rated, "оценку", "оценки", "оценок"))."
            : "Рекомендации будут строиться по тому, что вы смотрите.")
        let excluded = ExclusionChip.allCases.filter(store.exclusions.contains).map { $0.title.lowercased() }
        if !excluded.isEmpty { lines.append("Не покажем: \(excluded.joined(separator: ", ")).") }
        lines.append("Уточнить вкус снова можно в настройках.")
        return lines.joined(separator: " ")
    }
}

// MARK: - Pieces

/// The steps as dots, the current one long; all lit at the end.
private struct StepDots: View {
    let count: Int
    let current: Int
    var finished = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { index in
                Capsule()
                    .fill(finished || index < current ? KP.fg38 : index == current ? KP.fg : KP.chipStrong)
                    .frame(width: index == current && !finished ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: finished)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Шаг \(min(current + 1, count)) из \(count)"))
    }
}

/// How far through the stack: a thin bar in the sun's gradient.
private struct StackProgress: View {
    let total: Int
    let done: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(KP.chip)
                Capsule()
                    .fill(KP.sunGradient)
                    .frame(width: total > 0 ? proxy.size.width * CGFloat(done) / CGFloat(total) : 0)
            }
        }
        .frame(height: 4)
        .animation(.smooth(duration: 0.3), value: done)
    }
}

/// A taste chip in «Мы уже кое-что знаем».
private struct TasteChip: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(KP.font(13.5, .semibold))
            .foregroundStyle(KP.fg)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(KP.chip))
            .overlay(Capsule().strokeBorder(KP.sun.opacity(0.25), lineWidth: 1))
    }
}

/// One of the three answers under the card: an icon, its name and its keys; «Обожаю» is the white one.
private struct ChoiceButton: View {
    let title: String
    let symbol: String
    let hint: String
    var primary = false
    var highlighted = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: highlighted ? symbol + ".fill" : symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(verbatim: title)
                    .font(KP.font(13.5, .semibold))
                Text(verbatim: hint)
                    .font(KP.font(10.5, .semibold).monospacedDigit())
                    .opacity(0.5)
            }
            .foregroundStyle(primary ? KP.ink : KP.fg)
            .frame(width: 128, height: 82)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(primary ? (hover || highlighted ? Color.white : KP.fg) : (hover || highlighted ? KP.chipStrong : KP.chip))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(highlighted ? 0.95 : hover ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: hover)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: highlighted)
    }
}

/// A chip of «Чего не показывать?»: crossed out and white while it's excluded.
private struct ExclusionChipButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "nosign" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(verbatim: title)
                    .font(KP.font(13.5, .semibold))
            }
            .foregroundStyle(selected ? KP.ink : KP.fg80)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(selected ? KP.fg : hover ? KP.chipStrong : KP.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A quiet text button in the header («Пропустить», «Назад»).
private struct QuietButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                }
                Text(verbatim: title)
            }
            .font(KP.font(13, .semibold))
            .foregroundStyle(hover ? KP.fg : KP.fg55)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Offering it once

extension View {
    /// Offers the taste stack once, when it's worth it (see `TasteOnboardingFeature.shouldOffer`), as a sheet over this
    /// view, a moment after it appears so the screen settles first. For Home or the main window.
    func kpTasteOnboardingOffer(after delay: Duration = .seconds(2)) -> some View {
        modifier(TasteOnboardingOffer(delay: delay))
    }

    /// The taste stack as a sheet while `isPresented` (Settings → «Уточнить вкус»).
    func kpTasteOnboardingSheet(isPresented: Binding<Bool>) -> some View {
        modifier(TasteOnboardingSheet(isPresented: isPresented))
    }
}

private struct TasteOnboardingOffer: ViewModifier {
    let delay: Duration

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, await TasteOnboardingFeature.shouldOffer() else { return }
                isPresented = true
            }
            .kpTasteOnboardingSheet(isPresented: $isPresented)
    }
}

private struct TasteOnboardingSheet: ViewModifier {
    @Binding var isPresented: Bool

    /// Made once per showing, so the sheet keeps its place while the view under it redraws.
    @State private var store: StoreOf<TasteOnboardingFeature>?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) {
                if isPresented, store == nil {
                    store = Store(initialState: TasteOnboardingFeature.State()) { TasteOnboardingFeature() }
                }
            }
            // Up only once its store is made, so it never opens empty.
            .sheet(isPresented: Binding(get: { isPresented && store != nil }, set: { shown in
                guard !shown else { return }
                isPresented = false
                store = nil
            })) {
                if let store {
                    TasteOnboardingView(store: store)
                }
            }
    }
}
