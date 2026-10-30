import AppKit
import Defaults
import Dependencies
import RecommenderCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings → «Рекомендации»: your taste as it stands (and «Уточнить вкус», «Экспорт…»), what Home's top shows, how
/// familiar or new the picks are, what never to show, what the taste is built from, the catalogue learned in the
/// background (with its live count and an honest note), and the resets. All of it stays on this Mac.
struct RecommendationsSettings: View {
    @Default(.recHeroMode) private var heroMode
    @Default(.recFamiliarity) private var familiarity
    @Default(.recExcludedKinds) private var excludedKinds
    @Default(.recExcludedGenres) private var excludedGenres
    @Default(.recMaxAge) private var maxAge
    @Default(.recAskAfterWatch) private var askAfterWatch
    @Default(.recUseLocalHistory) private var useLocalHistory
    @Default(.recUseAccountList) private var useAccountList
    @Default(.recUseBookmarks) private var useBookmarks
    @Default(.recCrawlEnabled) private var crawlEnabled
    @Default(.recCrawlDailyLimit) private var crawlDailyLimit
    @Default(.isLoggedIn) private var isLoggedIn

    @Dependency(\.recommender) private var recommender

    @State private var profile: ProfileSummary?
    @State private var status: RecStatus?
    @State private var isOnboardingPresented = false
    @State private var confirmResetTaste = false
    @State private var confirmClearAll = false
    /// A short line after an action («Вкус сброшен»), under the group it came from.
    @State private var notice: Notice?

    private enum Notice: Equatable {
        /// Under «Ваш вкус» (the export): good or not.
        case taste(String, ok: Bool)
        case reset(String)
    }

    /// The daily limits offered for the background reading.
    private static let dailyLimits = [150, 300, 600]

    var body: some View {
        // The Settings window's own spacing between groups.
        VStack(alignment: .leading, spacing: 22) {
            tasteGroup
            homeGroup
            showGroup
            sourcesGroup
            catalogueGroup
            resetGroup
        }
            .task {
                await refreshProfile()
                // Redrawn as the taste changes (a rating, a batch of the catalogue).
                for await _ in recommender.updates() {
                    await refreshProfile()
                }
            }
            .task {
                while !Task.isCancelled {
                    let status = await recommender.status()
                    withAnimation(.snappy) { self.status = status }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .kpTasteOnboardingSheet(isPresented: $isOnboardingPresented)
            .onChange(of: isOnboardingPresented) {
                if !isOnboardingPresented {
                    Task { await refreshProfile() }
                }
            }
    }

    // MARK: - Ваш вкус

    private var tasteGroup: some View {
        SettingsGroup(title: "Ваш вкус", footer: tasteFooter) {
            VStack(alignment: .leading, spacing: 12) {
                let chips = profile.map { TasteSummary.chips($0, limit: 10) } ?? []
                if chips.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KP.sun)
                        Text(verbatim: profile == nil ? "Собираем…" : "Пока мало данных: смотрите, отмечайте «Нравится» — и здесь появится ваш вкус")
                            .font(KP.font(13, .medium))
                            .foregroundStyle(KP.fg70)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            Text(verbatim: chip)
                                .font(KP.font(12.5, .semibold))
                                .foregroundStyle(KP.fg)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(KP.chip))
                        }
                    }
                    .transition(.opacity)
                }

                if let counts = profile.flatMap(TasteSummary.counts) {
                    Text(verbatim: counts)
                        .font(KP.font(12))
                        .foregroundStyle(KP.fg55)
                }

                HStack(spacing: 8) {
                    Button {
                        isOnboardingPresented = true
                    } label: {
                        Label {
                            Text(verbatim: "Уточнить вкус")
                        } icon: {
                            Image(systemName: "hand.thumbsup")
                        }
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    .help("Оценить до 12 своих тайтлов и выбрать, чего не показывать — около минуты")

                    Button {
                        export()
                    } label: {
                        Label {
                            Text(verbatim: "Экспорт…")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    .help("Сохранить оценки, отметки и вкус в файл JSON: ваши данные принадлежат вам")

                    Spacer(minLength: 0)

                    if case let .taste(text, ok) = notice {
                        SettingsStatusLine(text: text, symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", tone: ok ? .good : .bad)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
            }
            .padding(16)
            .animation(.smooth(duration: 0.3), value: profile)
        }
    }

    private var tasteFooter: String {
        "Вкус строится из «Досмотреть», закладок, просмотров на этом Mac и ваших оценок. Никуда не отправляется."
    }

    // MARK: - Главная

    private var homeGroup: some View {
        SettingsGroup(title: "Главная") {
            SettingsRow(title: "Наверху главной", subtitle: heroSubtitle) {
                Picker(selection: $heroMode) {
                    Text(verbatim: "Сегодня вечером").tag(HeroMode.tonight.rawValue)
                    Text(verbatim: "Тренды").tag(HeroMode.trends.rawValue)
                    Text(verbatim: "Скрыть").tag(HeroMode.hidden.rawValue)
                } label: {
                    Text(verbatim: "Наверху главной")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SettingsRow(title: "Знакомое или новое", subtitle: familiaritySubtitle) {
                HStack(spacing: 8) {
                    Text(verbatim: "Знакомое")
                        .font(KP.font(12, .medium))
                        .foregroundStyle(KP.fg55)
                    Slider(value: $familiarity, in: 0 ... 1) {
                        Text(verbatim: "Знакомое или новое")
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150)
                    Text(verbatim: "Новое")
                        .font(KP.font(12, .medium))
                        .foregroundStyle(KP.fg55)
                }
            }
        }
    }

    private var heroSubtitle: String {
        switch HeroMode(rawValue: heroMode) ?? .tonight {
        case .tonight: "Один главный вариант и два запасных под ваш вкус и время дня"
        case .trends: "Что сейчас популярно на сайте, как раньше"
        case .hidden: "Главная начинается с «Продолжить просмотр»"
        }
    }

    private var familiaritySubtitle: String {
        switch familiarity {
        case ..<0.2: "Только проверенное: продолжения, похожее на любимое"
        case ..<0.55: "В основном похожее на ваше, иногда что-то новое"
        case ..<0.8: "Поровну похожего и новых жанров и стран"
        default: "Больше открытий: жанры и страны, которые вы редко смотрите"
        }
    }

    // MARK: - Что показывать

    private var showGroup: some View {
        SettingsGroup(title: "Что показывать") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Не показывать")
                        .font(KP.font(13.5, .medium))
                        .foregroundStyle(KP.fg)
                    Text(verbatim: "Эти виды и жанры не попадут в рекомендации")
                        .font(KP.font(12))
                        .foregroundStyle(KP.fg55)
                }
                FlowLayout(spacing: 6) {
                    ForEach(ExclusionChip.allCases) { chip in
                        KPPill(title: chip.title, selected: excludedChips.contains(chip)) {
                            toggle(chip)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            SettingsRow(title: "Возраст", subtitle: "Не советовать то, что старше этой отметки") {
                Picker(selection: Binding(get: { AgeLimit(stored: maxAge) }, set: { maxAge = $0.rawValue })) {
                    ForEach(AgeLimit.allCases) { limit in
                        Text(verbatim: limit.title).tag(limit)
                    }
                } label: {
                    Text(verbatim: "Возраст")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsToggle(
                title: "Спрашивать оценку после просмотра",
                subtitle: "Когда фильм дошёл до титров или закончился сезон: «Как вам?» на 10 секунд, один раз на тайтл",
                isOn: $askAfterWatch
            )
        }
    }

    private var excludedChips: Set<ExclusionChip> {
        ExclusionChip.selected(kinds: excludedKinds, genres: excludedGenres)
    }

    private func toggle(_ chip: ExclusionChip) {
        var chips = excludedChips
        if chips.contains(chip) {
            chips.remove(chip)
        } else {
            chips.insert(chip)
        }
        let applied = ExclusionChip.apply(chips, kinds: excludedKinds, genres: excludedGenres)
        withAnimation(.snappy(duration: 0.2)) {
            excludedKinds = applied.kinds
            excludedGenres = applied.genres
        }
    }

    // MARK: - Учитывать

    private var sourcesGroup: some View {
        SettingsGroup(title: "Учитывать", footer: "Выключенное не участвует во вкусе, но и не удаляется.") {
            SettingsToggle(title: "Просмотры на этом Mac", subtitle: "Что и насколько досмотрено в плеере приложения", isOn: $useLocalHistory)
            SettingsToggle(title: "Список «Досмотреть»", subtitle: "Начатое и просмотренное на сайте и на ТВ", isOn: $useAccountList)
            SettingsToggle(title: "Закладки", subtitle: "Папки вроде «Любимое» говорят о вкусе, «На потом» — о намерении", isOn: $useBookmarks)
        }
    }

    // MARK: - Изучение каталога

    private var catalogueGroup: some View {
        SettingsGroup(
            title: "Изучение каталога",
            footer: "Приложение открывает страницы сайта в фоне под вашим аккаунтом — сайт видит эти открытия, как если бы вы листали сами."
        ) {
            SettingsToggle(
                title: "Изучать каталог в фоне",
                subtitle: isLoggedIn ? "Жанры, люди и связи тайтлов делают рекомендации точнее; страницы читаются по одной, не чаще раза в 1,5 секунды" : "Только после входа: гостям сайт страницы тайтлов не показывает",
                isOn: $crawlEnabled
            )

            SettingsRow(title: "Страниц в день", subtitle: "Больше — быстрее растёт каталог") {
                Picker(selection: $crawlDailyLimit) {
                    ForEach(Self.dailyLimits, id: \.self) { limit in
                        Text(verbatim: "\(limit)").tag(limit)
                    }
                } label: {
                    Text(verbatim: "Страниц в день")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(!crawlEnabled)
            }
            .opacity(crawlEnabled ? 1 : 0.5)

            SettingsRow(title: "Сейчас", subtitle: statusLine) {
                if status?.isEnriching == true, crawlEnabled {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(verbatim: "изучаем")
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.fg55)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var statusLine: String {
        guard let status else { return "Считаем…" }
        return CatalogueStatusText.line(
            known: status.known, pages: status.pages, fetchedToday: status.fetchedToday,
            dailyLimit: status.dailyLimit > 0 ? status.dailyLimit : crawlDailyLimit, enabled: crawlEnabled && isLoggedIn
        )
    }

    // MARK: - Сброс

    private var resetGroup: some View {
        SettingsGroup(title: "Сброс") {
            SettingsRow(title: "Сбросить вкус", subtitle: "Забыть, что выведено из просмотров, и показы. Ваши оценки и исключения останутся") {
                Button {
                    confirmResetTaste = true
                } label: {
                    Text(verbatim: "Сбросить")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            }

            SettingsRow(title: "Очистить данные рекомендаций", subtitle: resetSubtitle) {
                Button {
                    confirmClearAll = true
                } label: {
                    Text(verbatim: "Очистить")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            }
        }
        .confirmationDialog(Text(verbatim: "Сбросить вкус?"), isPresented: $confirmResetTaste) {
            Button(role: .destructive) {
                Task {
                    await recommender.resetTaste()
                    await refreshProfile()
                    show(.reset("Вкус сброшен: он соберётся заново из того, что вы смотрите"))
                }
            } label: {
                Text(verbatim: "Сбросить")
            }
        } message: {
            Text(verbatim: "Оценки «Не моё · Нравится · Обожаю» и исключения сохранятся.")
        }
        .confirmationDialog(Text(verbatim: "Очистить все данные рекомендаций?"), isPresented: $confirmClearAll) {
            Button(role: .destructive) {
                Task {
                    await recommender.clearAll()
                    await refreshProfile()
                    show(.reset("Данные рекомендаций очищены"))
                }
            } label: {
                Text(verbatim: "Очистить")
            }
        } message: {
            Text(verbatim: "Пропадут оценки, отметки «Скрыть» и «Уже смотрел», история показов и вкус. Изученный каталог останется. Отменить это нельзя — можно сначала сделать «Экспорт…».")
        }
    }

    private var resetSubtitle: String {
        if case let .reset(text) = notice { return text }
        return "Оценки, отметки, показы и вкус. Изученный каталог тайтлов останется"
    }

    // MARK: - Actions

    private func refreshProfile() async {
        let profile = await recommender.home(false)?.output.profile ?? .empty
        withAnimation(.smooth(duration: 0.3)) { self.profile = profile }
    }

    private func show(_ notice: Notice) {
        withAnimation(.smooth(duration: 0.25)) { self.notice = notice }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.smooth(duration: 0.25)) {
                if self.notice == notice { self.notice = nil }
            }
        }
    }

    /// «Экспорт…»: everything the recommendations know, as JSON, where you choose.
    private func export() {
        Task {
            guard let data = await recommender.exportJSON() else {
                show(.taste("Пока нечего сохранять", ok: false))
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(AppInfo.name) — вкус \(Date.now.formatted(.iso8601.year().month().day())).json"
            panel.message = "Оценки, отметки и вкус: всё, что знают рекомендации"
            panel.prompt = "Сохранить"
            guard await panel.begin() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                show(.taste("Сохранено: \(url.lastPathComponent)", ok: true))
            } catch {
                show(.taste("Не получилось сохранить: \(error.localizedDescription)", ok: false))
            }
        }
    }
}
