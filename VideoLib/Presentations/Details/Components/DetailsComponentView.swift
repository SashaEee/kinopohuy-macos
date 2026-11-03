import ComposableArchitecture
import Defaults
import SwiftUI

/// A title's page: the banner (its large poster, name, facts, description, what to do), then the cast, the facts
/// with links, the site's rating, the franchise, the release schedule and «Смотрите также».
/// Until the page is in (details nil) it is already laid out: the card's name and picture in the banner, grey
/// stand-ins for the rest, which the real content then takes over in place.
struct DetailsComponentView: View {
    private let details: MovieDetailed?
    private let previewTitle: String
    private let previewPoster: String?
    @Binding private var isSchedulePresented: Bool

    init(details: MovieDetailed?, previewTitle: String, previewPoster: String?, isSchedulePresented: Binding<Bool>) {
        self.details = details
        self.previewTitle = previewTitle
        self.previewPoster = previewPoster
        _isSchedulePresented = isSchedulePresented
    }

    @Environment(StoreOf<DetailsFeature>.self) private var store
    @Environment(Downloader.self) private var downloader
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @Environment(\.kpMetrics) private var metrics
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Default(.isLoggedIn) private var isLoggedIn
    @Default(.mirror) private var mirror

    @State private var hasExternalPlayer = false
    @State private var franchiseExpanded = false
    /// «Смотреть» or an episode was pressed before its stream was in: play once it is.
    @State private var pendingPlay = false
    /// …and it was «С начала».
    @State private var pendingStartOver = false
    /// The minute «закончится в 23:40» is worked out from.
    @State private var now = Date.now

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: metrics.sectionGap) {
            KPHero(
                kicker: kindTitle,
                title: details?.nameRussian ?? previewTitle,
                original: details?.nameOriginal,
                facts: details.map(heroFacts) ?? [],
                ratings: details?.heroRatings ?? [],
                description: details?.description,
                descriptionLines: metrics.compact ? 4 : 5,
                details: true,
                isPlaceholder: details == nil,
                entrance: true,
                titleSizeBasis: previewTitle.isEmpty ? nil : previewTitle
            ) {
                // The card's picture (decoded at the card's size, so straight from memory, in the first frame) stays
                // underneath; the large one fades in over it, so the picture only sharpens, never dims.
                ZStack {
                    if let poster = previewPoster ?? details?.poster {
                        KPRemoteImage(url: poster, downsample: previewPoster == nil ? nil : KP.cardPosterPixels(), immediate: true)
                    }
                    // The full-size picture over it: the large poster, or the page's own one when there's none (left out
                    // when it is the very picture already underneath).
                    if let details {
                        let large = details.hposter.isEmpty ? details.poster : details.hposter
                        if !large.isEmpty, previewPoster != nil || large != details.poster {
                            KPRemoteImage(url: large, clearPlaceholder: true)
                                .transition(.identity)
                        }
                    }
                }
            } actions: {
                // One slot: the stand-ins and the buttons overlap while they cross-fade, instead of standing side by
                // side in the row for a moment.
                ZStack(alignment: .leading) {
                    if let details {
                        HStack(spacing: 12) { actions(details) }
                            .animation(.smooth(duration: 0.3), value: store.selection?.resumePosition != nil)
                            .animation(.smooth(duration: 0.3), value: store.isBookmarked)
                            .transition(.opacity)
                    } else {
                        HStack(spacing: 12) { DetailsActionsPlaceholder() }
                            .transition(.opacity)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                if let details {
                    sections(details)
                        .transition(.opacity.combined(with: .offset(y: 24)))
                } else {
                    DetailsSectionsPlaceholder()
                        .transition(.opacity)
                }
            }
        }
        .padding(.bottom, metrics.screenBottom)
        .onAppear {
            hasExternalPlayer = ExternalPlayers.isAnyInstalled
            // Back on the page (from a person's page, say): where things were left may have moved.
            refreshPositions()
        }
        .onChange(of: controlActiveState) { _, state in
            // The window is in front again, the player closed: «Продолжить с …» and the ticks catch up.
            if state == .key { refreshPositions() }
        }
        .task {
            // On the minute, so «закончится в» stays true while the page is open.
            while !Task.isCancelled {
                let second = Calendar.current.component(.second, from: .now)
                try? await Task.sleep(for: .seconds(60 - second))
                now = .now
            }
        }
        .onChange(of: readiness, initial: true) {
            guard pendingPlay || store.autoWatch else { return }
            if let data = store.selection?.playerData(startOver: pendingStartOver) {
                openPlayer(data)
            } else if store.selection?.movie?.needPremium == true {
                // Premium-only: the sheet explains it and offers premium.
                pendingPlay = false
                pendingStartOver = false
                if store.autoWatch { store.send(.autoWatchHandled) }
                store.send(.watchTapped)
            } else {
                chooseQualityIfNeeded()
            }
        }
        .sheet(item: $store.scope(state: \.destination?.watch, action: \.destination.watch)) { store in
            WatchSheetView(store: store)
        }
        .sheet(item: $store.scope(state: \.destination?.download, action: \.destination.download)) { store in
            DownloadSheetView(store: store)
        }
        .sheet(item: $store.scope(state: \.destination?.openExternalPlayer, action: \.destination.openExternalPlayer)) { store in
            OpenExternalPlayerSheetView(store: store)
        }
    }

    /// Everything under the banner, once the page is in.
    private func sections(_ details: MovieDetailed) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionGap) {
            // Only with something to choose: an empty slot would still take the sections' spacing.
            if let selection = store.scope(state: \.selection, action: \.selection),
               details.series != nil || (details.voiceActing?.count ?? 0) > 1
            {
                WatchOptionsView(store: selection, pageActings: details.voiceActing ?? [], pageIsSeries: details.series != nil, popularity: details.voiceActingRating ?? []) { episode in
                    playEpisode(episode)
                }
                .padding(.top, -(metrics.sectionGap * 0.4).rounded())
            }

            let cast = castMembers(details)
            if !cast.isEmpty {
                KPRow(title: "В ролях", items: cast, itemWidth: metrics.personColumn, spacing: metrics.compact ? 14 : 16) { member in
                    PersonCircle(person: member.person, role: member.role)
                }
            }

            facts(details)

            if let franchise = details.franchise, !franchise.isEmpty {
                franchiseSection(franchise)
            }

            if let schedule = details.schedule, let first = schedule.first, !first.items.isEmpty {
                scheduleSection(first, more: schedule.count > 1 || first.items.count > 5)
            }

            if !details.watchAlsoMovies.isEmpty {
                KPRow(title: "Смотрите также", items: details.watchAlsoMovies) { movie in
                    CardView(movie: movie)
                        .equatable()
                }
            }
        }
    }

    /// «Фильм · 18+», «Аниме · сериал · 16+»: what it is from the site's section in the title's address, known from
    /// the first frame (so the line is there at once), then whether it has episodes and the age once the page is in.
    private var kindTitle: String? {
        let section = store.id.pathParts.first ?? ""
        let isSeries = details.map { $0.series != nil }
        let kind: String? = switch section {
        case "films": "Фильм"
        case "series": "Сериал"
        case "cartoons": isSeries == true ? "Мультфильм · сериал" : "Мультфильм"
        case "animation": isSeries == true ? "Аниме · сериал" : "Аниме"
        case "show": isSeries == true ? "ТВ-шоу · сериал" : "ТВ-шоу"
        default: isSeries.map { $0 ? "Сериал" : "Фильм" }
        }
        let parts = [kind, details?.ageRestriction].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «2024 · США, Великобритания · 2 ч 4 мин · закончится в 23:40 · Драма, Триллер». The age is in the kicker; the
    /// end time comes right after the length, before the genres, so a long line cuts the genres (they are in «О
    /// фильме» below) rather than it.
    private func heroFacts(_ details: MovieDetailed) -> [String] {
        var facts: [String] = []
        if let year = details.displayYear { facts.append(year) }
        if let countries = details.countries, !countries.isEmpty { facts.append(countries.prefix(2).map(\.name).joined(separator: ", ")) }
        if let duration = details.duration, duration > 0 {
            facts.append(duration >= 60 ? "\(duration / 60) ч \(duration % 60) мин" : "\(duration) мин")
        }
        if let endsAt = endsAt(details) { facts.append(endsAt) }
        if let genres = details.genres, !genres.isEmpty { facts.append(genres.prefix(2).map(\.name).joined(separator: ", ")) }
        return facts
    }

    /// A film's «закончится в 23:40» if it were started now (from where it was left), while over a minute remains.
    private func endsAt(_ details: MovieDetailed) -> String? {
        guard details.series == nil, details.available, let duration = details.duration, duration > 0 else { return nil }
        let remaining = Double(duration * 60) - (store.selection?.resumePosition ?? 0)
        guard remaining > 60 else { return nil }
        let end = Calendar.current.dateComponents([.hour, .minute], from: now.addingTimeInterval(remaining))
        return String(format: "закончится в %d:%02d", end.hour ?? 0, end.minute ?? 0)
    }

    /// «В ролях»: the directors first (signed «режиссёр»), then the cast.
    private func castMembers(_ details: MovieDetailed) -> [CastMember] {
        let directors = (details.producer ?? []).map { CastMember(person: $0, role: "режиссёр") }
        let actors = (details.actors ?? []).map { CastMember(person: $0, role: nil) }
        return directors + actors
    }

    // MARK: - Playing

    /// Changes whenever what «Смотреть» would start becomes ready or changes.
    private var readiness: String {
        guard let selection = store.selection else { return "" }
        return [selection.selectedActing?.translatorId, selection.selectedEpisode?.episodeId, selection.selectedQuality, selection.movie == nil ? nil : "video"]
            .map { $0 ?? "-" }
            .joined(separator: "|")
    }

    /// `startOver`: «С начала», from 0 rather than where it was left.
    private func play(startOver: Bool = false) {
        guard let selection = store.selection else {
            store.send(.watchTapped)
            return
        }
        if let data = selection.playerData(startOver: startOver) {
            openPlayer(data)
        } else if selection.movie?.needPremium == true {
            store.send(.watchTapped)
        } else {
            pendingPlay = true
            pendingStartOver = startOver
            chooseQualityIfNeeded()
        }
    }

    private func playEpisode(_ episode: MovieEpisode?) {
        guard let episode, episode != store.selection?.selectedEpisode else {
            play()
            return
        }
        pendingPlay = true
        pendingStartOver = false
        store.send(.selection(.binding(.set(\.selectedEpisode, episode))))
    }

    /// With «ask every time» as the default quality the stream has none chosen: the best one, rather than waiting.
    private func chooseQualityIfNeeded() {
        guard let selection = store.selection, selection.selectedQuality == nil,
              let best = selection.movie?.getAvailableQualities().last else { return }
        store.send(.selection(.binding(.set(\.selectedQuality, best))))
    }

    private func openPlayer(_ data: PlayerData) {
        pendingPlay = false
        pendingStartOver = false
        if store.autoWatch { store.send(.autoWatchHandled) }
        dismissWindow(id: Windows.player.id)
        openWindow(id: Windows.player.id, value: data)
    }

    private func refreshPositions() {
        guard store.selection != nil else { return }
        store.send(.selection(.refreshPositions))
    }

    /// «Смотреть · 1 сезон, 4 серия» for a series, so it's clear what starts; «Продолжить · 1 сезон, 5 серия с
    /// 12:34» («Продолжить с 1:02:34» for a film) when it was left partway.
    private var playTitle: String {
        let selection = store.selection
        let what: String? = if let season = selection?.selectedSeason, let episode = selection?.selectedEpisode {
            "\(season.name.first?.isNumber == true ? "\(season.name) сезон" : season.name), \(episode.name.first?.isNumber == true ? "\(episode.name) серия" : episode.name)"
        } else {
            nil
        }
        guard let resume = selection?.resumePosition else { return what.map { "Смотреть · \($0)" } ?? "Смотреть" }
        return what.map { "Продолжить · \($0) с \(Self.clock(resume))" } ?? "Продолжить с \(Self.clock(resume))"
    }

    /// «12:34», «1:02:34».
    private static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s < 3600 ? String(format: "%d:%02d", s / 60, s % 60) : String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    // MARK: - Buttons

    @ViewBuilder
    private func actions(_ details: MovieDetailed) -> some View {
        if details.available {
            Button {
                play()
            } label: {
                HStack(spacing: 8) {
                    if pendingPlay, !pendingStartOver {
                        ProgressView().controlSize(.small).tint(KP.ink)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(verbatim: playTitle)
                        .truncationMode(.middle)
                        .frame(maxWidth: metrics.compact ? 300 : 340)
                }
                .contentTransition(.opacity)
            }
            .buttonStyle(KPPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .animation(.snappy, value: playTitle)

            // Left partway: from 0 instead (the player then skips where it was left, once).
            if store.selection?.resumePosition != nil {
                Button {
                    play(startOver: true)
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "arrow.counterclockwise").opacity(pendingPlay && pendingStartOver ? 0 : 1)
                            if pendingPlay, pendingStartOver {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        Text(verbatim: "С начала")
                    }
                }
                .buttonStyle(KPSecondaryButtonStyle())
                .help("Смотреть с самого начала")
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
            }
        } else {
            // «Скоро на сайте · 12 декабря 2025»: when, if the site says.
            let soon = details.releaseDate.map { $0.isEmpty ? "Скоро на сайте" : "Скоро на сайте · \($0)" } ?? "Скоро на сайте"
            Label {
                Text(verbatim: details.comingSoon ? soon : "Пока недоступно")
            } icon: {
                Image(systemName: details.comingSoon ? "clock" : "network.slash")
            }
            .font(KP.font(metrics.controlFont, .semibold))
            .foregroundStyle(KP.fg55)
            .padding(.horizontal, metrics.controlPadding)
            .frame(height: metrics.control)
            .background(Capsule().fill(KP.chip))
        }

        if store.trailer != nil || store.trailerSearching {
            Button {
                store.send(.trailerTapped)
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Image(systemName: "film").opacity(store.trailer == nil ? 0 : 1)
                        if store.trailer == nil {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    Text(verbatim: "Трейлер")
                }
            }
            .buttonStyle(KPSecondaryButtonStyle())
            .disabled(store.trailer == nil)
            .opacity(store.trailer == nil ? 0.5 : 1)
            .help(store.trailer == nil ? "Ищем трейлер…" : "Трейлер")
            .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
        }

        if isLoggedIn {
            // «В закладках» with a filled mark once it's in any folder.
            let bookmarked = store.isBookmarked == true
            Button {
                store.send(.bookmarksTapped)
            } label: {
                Label {
                    Text(verbatim: bookmarked ? "В закладках" : "В закладки")
                } icon: {
                    Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                }
                .contentTransition(.opacity)
            }
            .buttonStyle(KPSecondaryButtonStyle())
            .help(bookmarked ? "Уже в закладках: изменить папки" : "Добавить в закладки")
        }

        if details.available, downloader.isRunning {
            Button {
                store.send(.downloadTapped)
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(KPIconButtonStyle())
            .help("Скачать")
        }

        if details.available, hasExternalPlayer {
            Button {
                store.send(.openExternalPlayerTapped)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(KPIconButtonStyle())
            .help("Открыть во внешнем плеере")
        }

        Button {
            store.send(.push(.comments(details)))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                if details.commentsCount > 0 {
                    Text(verbatim: "\(details.commentsCount)")
                        .font(KP.font(metrics.controlFont, .semibold))
                }
            }
        }
        .buttonStyle(KPSecondaryButtonStyle())
        .help("Отзывы")
        #if DEBUG
            .task {
                // Test hook: KP_COMMENTS opens the reviews as soon as the page is in.
                if ProcessInfo.processInfo.environment["KP_COMMENTS"] != nil {
                    store.send(.push(.comments(details)))
                }
            }
        #endif

        ShareLink(item: mirror.appending(path: store.id, directoryHint: .notDirectory)) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(KPIconButtonStyle())
        .help("Поделиться")
    }

    // MARK: - Facts

    private func facts(_ details: MovieDetailed) -> some View {
        VStack(alignment: .leading, spacing: metrics.stackGap + 4) {
            KPSectionTitle(title: details.series != nil ? "О сериале" : "О фильме")

            HStack(alignment: .top, spacing: metrics.compact ? 32 : 40) {
                VStack(alignment: .leading, spacing: metrics.compact ? 10 : 12) {
                    if let slogan = details.slogan, !slogan.isEmpty, slogan != "-" {
                        FactRow(label: "Слоган") {
                            Text(verbatim: slogan).italic()
                        }
                    }
                    if let releaseDate = details.releaseDate, !releaseDate.isEmpty {
                        FactRow(label: "Дата выхода") { Text(verbatim: releaseDate) }
                    }
                    if let countries = details.countries, !countries.isEmpty {
                        FactRow(label: "Страна") { ChipLinks(items: countries) }
                    }
                    if let genres = details.genres, !genres.isEmpty {
                        FactRow(label: "Жанр") { ChipLinks(items: genres) }
                    }
                    if let producer = details.producer, !producer.isEmpty {
                        FactRow(label: "Режиссёр") { ChipLinks(items: producer) }
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)

                VStack(alignment: .leading, spacing: metrics.compact ? 10 : 12) {
                    if let rating = details.rating {
                        FactRow(label: "Рейтинг сайта") {
                            SiteRating(rating: rating, rated: details.rated, votes: details.votes, canRate: isLoggedIn) { value in
                                store.send(.rate(value))
                            }
                        }
                    }
                    // Right under the site's stars: what you think, for the recommendations (kept on this Mac).
                    if let titleId = store.feedback.titleId {
                        FactRow(label: "Ваша оценка") {
                            FeedbackBarView(store: store.scope(state: \.feedback, action: \.feedback))
                        }
                        // «Вам подойдёт?»: only once the recommender knows enough to say (the row stays out otherwise).
                        .kpFitVerdictRow(titleId: titleId, label: "Вам подойдёт?", spacing: metrics.compact ? 10 : 12)
                    }
                    if details.imdbRating != nil || details.kpRating != nil || details.waRating != nil {
                        FactRow(label: "Оценки") {
                            HStack(spacing: 8) {
                                if let r = details.imdbRating { RatingLink(source: "IMDb", rating: r) }
                                if let r = details.kpRating { RatingLink(source: "КиноПоиск", rating: r) }
                                if let r = details.waRating { RatingLink(source: "World Art", rating: r) }
                                CriticChips(
                                    imdbId: RecParsing.imdbId(fromLink: details.imdbRating?.link),
                                    kpId: RecParsing.kinopoiskId(fromLink: details.kpRating?.link)
                                )
                            }
                        }
                    }
                    if let lists = details.lists, !lists.isEmpty {
                        FactRow(label: "В списках") { ChipLinks(items: lists) }
                    }
                    if let collections = details.collections, !collections.isEmpty {
                        FactRow(label: "Подборки") { ChipLinks(items: collections) }
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
            }
        }
        .padding(.horizontal, KP.gutter)
    }

    // MARK: - Franchise

    private func franchiseSection(_ franchise: [MovieFranchisePart]) -> some View {
        VStack(alignment: .leading, spacing: metrics.stackGap) {
            HStack(alignment: .firstTextBaseline) {
                KPSectionTitle(title: "Франшиза", count: franchise.count)
                Spacer()
                if franchise.count > 6 {
                    KPLinkButton(title: franchiseExpanded ? "Свернуть" : "Показать все") {
                        withAnimation(.snappy) { franchiseExpanded.toggle() }
                    }
                }
            }

            VStack(spacing: 4) {
                ForEach(franchise.prefix(franchiseExpanded ? franchise.count : 6)) { part in
                    FranchiseRow(part: part)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
        .padding(.horizontal, KP.gutter)
    }

    // MARK: - Schedule

    private func scheduleSection(_ group: SeriesScheduleGroup, more: Bool) -> some View {
        VStack(alignment: .leading, spacing: metrics.stackGap) {
            HStack(alignment: .firstTextBaseline) {
                KPSectionTitle(title: "Выход серий")
                Text(verbatim: group.name)
                    .font(KP.font(metrics.sectionCount, .medium))
                    .foregroundStyle(KP.fg38)
                Spacer()
                if more {
                    KPLinkButton(title: "Всё расписание") { isSchedulePresented = true }
                }
            }

            VStack(spacing: 4) {
                ForEach(group.items.prefix(5)) { item in
                    HStack(spacing: 14) {
                        Text(verbatim: item.title)
                            .font(KP.font(13, .semibold))
                            .foregroundStyle(KP.fg55)
                            .frame(width: 136, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.russianEpisodeName)
                                .font(KP.font(14, .medium))
                                .foregroundStyle(KP.fg)
                                .lineLimit(1)
                            if let original = item.originalEpisodeName {
                                Text(verbatim: original)
                                    .font(KP.font(12))
                                    .foregroundStyle(KP.fg38)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(verbatim: item.releaseDate)
                            .font(KP.font(13, .medium))
                            .foregroundStyle(KP.fg70)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KP.surface.opacity(0.7)))
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
        .padding(.horizontal, KP.gutter)
    }
}

// MARK: - Pieces

/// One of «В ролях»: the directors, then the cast.
private struct CastMember: Identifiable {
    let person: PersonSimple
    /// «режиссёр» under the name; nil for the cast.
    let role: String?

    var id: UUID { person.id }
}

/// A person: a round photo (their initials when there's none) and the name, and what they did if they directed it;
/// opens their page.
private struct PersonCircle: View {
    let person: PersonSimple
    var role: String?
    @State private var hover = false
    @Environment(\.kpMetrics) private var metrics

    private var hasPhoto: Bool {
        !person.photo.isEmpty && person.photo != "null" && !person.photo.contains("nopersonphoto")
    }

    /// «АП» for Анна Петрова.
    private var initials: String {
        person.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        KPRouteLink(route: .person(person)) {
            VStack(spacing: 8) {
                ZStack {
                    KP.surface
                    if hasPhoto {
                        KPRemoteImage(url: person.photo, downsample: CGSize(width: 192, height: 192))
                    } else if !initials.isEmpty {
                        Text(verbatim: initials)
                            .font(KP.font(metrics.personPhoto * 0.3, .bold))
                            .foregroundStyle(KP.fg38)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(KP.fg38)
                    }
                }
                .frame(width: metrics.personPhoto, height: metrics.personPhoto)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(KP.fg, lineWidth: 3).padding(-5).opacity(hover ? 1 : 0))
                .scaleEffect(hover ? 1.05 : 1)

                VStack(spacing: 2) {
                    Text(verbatim: person.name)
                        .font(KP.font(metrics.compact ? 12 : 12.5, .medium))
                        .foregroundStyle(hover ? KP.fg : KP.fg70)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let role {
                        Text(verbatim: role)
                            .font(KP.font(11.5, .medium))
                            .foregroundStyle(KP.fg38)
                    }
                }
                .frame(width: metrics.personColumn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.18), value: hover)
    }
}

/// A label on the left, what it is on the right.
private struct FactRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(verbatim: label)
                .font(KP.font(13, .medium))
                .foregroundStyle(KP.fg38)
                .frame(width: 108, alignment: .leading)
            value()
                .font(KP.font(metrics.facts, .medium))
                .foregroundStyle(KP.fg80)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Countries, genres, people, lists, collections: small capsules that open their lists.
private struct ChipLinks<T: Named>: View {
    let items: [T]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { item in
                ChipLink(item: item)
            }
        }
    }
}

private struct ChipLink<T: Named>: View {
    let item: T
    @State private var hover = false

    private var title: String {
        if let list = item as? MovieList, let position = list.moviePosition {
            return "\(list.name) · \(position) место"
        }
        return item.name
    }

    var body: some View {
        KPRouteLink(route: .fromNamed(item)) {
            Text(verbatim: title)
                .font(KP.font(12.5, .medium))
                .foregroundStyle(hover ? KP.fg : KP.fg80)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(hover ? KP.chipStrong : KP.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// IMDb / КиноПоиск / World Art: the number in its colour, the votes on hover; opens the source.
private struct RatingLink: View {
    let source: String
    let rating: MovieRating

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        Link(destination: URL(string: rating.link) ?? URL(string: "about:blank")!) {
            HStack(spacing: 6) {
                Text(verbatim: source).foregroundStyle(KP.fg55)
                Text(verbatim: KP.ratingText(rating.value)).foregroundStyle(KP.ratingColor(rating.value).mix(with: .white, by: 0.25))
            }
            .font(KP.font(metrics.compact ? 12.5 : 13, .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(KP.chip))
        }
        .buttonStyle(.plain)
        .help("Голосов: \(rating.votesCount)")
    }
}

/// Rotten Tomatoes (the critics' Tomatometer) and Metacritic beside the site's ratings, when the data pack knows the
/// title: fresh (60 % and up) in red, rotten in green-grey, as on the sites themselves; Metacritic by its own colours.
private struct CriticChips: View {
    let imdbId: String?
    let kpId: Int?

    @State private var scores: CriticScores?
    @Environment(\.kpMetrics) private var metrics
    @Dependency(\.recommender) private var recommender

    var body: some View {
        HStack(spacing: 8) {
            if let rt = scores?.rottenTomatoes {
                chip("RT", "\(rt) %", color: rt >= 60 ? Color(red: 0.98, green: 0.32, blue: 0.24) : Color(red: 0.56, green: 0.74, blue: 0.36))
                    .help("Rotten Tomatoes: доля положительных рецензий критиков (Викиданные)")
            }
            if let mc = scores?.metacritic {
                chip("Metacritic", "\(mc)", color: mc >= 61 ? Color(red: 0.4, green: 0.8, blue: 0.2) : mc >= 40 ? Color(red: 1, green: 0.8, blue: 0.2) : Color(red: 1, green: 0.35, blue: 0.35))
                    .help("Metacritic: средняя оценка критиков (Викиданные)")
            }
        }
        .task(id: "\(imdbId ?? "")|\(kpId ?? 0)") {
            guard imdbId != nil || kpId != nil else { return }
            scores = await recommender.critics(imdbId, kpId)
        }
    }

    private func chip(_ source: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: source).foregroundStyle(KP.fg55)
            Text(verbatim: value).foregroundStyle(color)
        }
        .font(KP.font(metrics.compact ? 12.5 : 13, .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(KP.chip))
    }
}

/// The site's ten stars: filled to its rating; under the pointer, the one you'd give (once, when signed in).
private struct SiteRating: View {
    let rating: Float
    let rated: Bool
    let votes: String?
    let canRate: Bool
    let rate: (Int) -> Void

    @State private var hover: Int?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(1 ... 10, id: \.self) { star in
                    let lit = hover.map { star <= $0 } ?? (Float(star) <= rating.rounded())
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(lit ? (hover != nil ? KP.sun : KP.fg80) : KP.fg.opacity(0.18))
                        .onHover { inside in
                            guard canRate, !rated else { return }
                            hover = inside ? star : (hover == star ? nil : hover)
                        }
                        .onTapGesture {
                            guard canRate, !rated else { return }
                            rate(star)
                        }
                }
            }
            Text(verbatim: hover.map { "\($0)" } ?? KP.ratingText(rating))
                .font(KP.font(14, .semibold).monospacedDigit())
                .foregroundStyle(KP.fg)
                .contentTransition(.numericText())
            if let votes, hover == nil {
                Text(verbatim: "(\(votes))")
                    .font(KP.font(12.5))
                    .foregroundStyle(KP.fg38)
            }
            if rated {
                Text(verbatim: "вы оценили")
                    .font(KP.font(12.5))
                    .foregroundStyle(KP.fg38)
            }
        }
        .animation(.snappy(duration: 0.12), value: hover)
    }
}

/// One part of the franchise: its place, name, year and rating; this title marked, the others open.
private struct FranchiseRow: View {
    let part: MovieFranchisePart
    @State private var hover = false

    var body: some View {
        if !part.current, let movieId = part.franchiseId {
            KPRouteLink(route: .details(MovieSimple(movieId: movieId, name: part.name))) {
                row
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(part.position)")
                .font(KP.font(12, .bold))
                .foregroundStyle(part.current ? KP.ink : KP.fg70)
                .frame(width: 24, height: 24)
                .background(Circle().fill(part.current ? KP.fg : KP.chip))
            Text(verbatim: part.name)
                .font(KP.font(14, part.current ? .bold : .medium))
                .foregroundStyle(part.current || hover ? KP.fg : KP.fg80)
                .lineLimit(1)
            Spacer()
            Text(verbatim: part.year)
                .font(KP.font(13, .medium))
                .foregroundStyle(KP.fg38)
            if let rating = part.rating {
                KPBadge(text: KP.ratingText(rating), color: KP.ratingColor(rating))
            }
            if !part.current, part.franchiseId != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(KP.fg38)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(part.current ? KP.surfaceHigh : hover ? KP.surface : KP.surface.opacity(0.6)))
        .contentShape(Rectangle())
    }
}

/// Chips that wrap onto the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The banner's buttons while the page loads: their shapes, at the buttons' own height, where «Смотреть» and the
/// rest will be, so the row doesn't jump when they come.
private struct DetailsActionsPlaceholder: View {
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        let height = metrics.control
        let scale: CGFloat = metrics.compact ? 0.85 : 1
        KPSkeleton(width: 168 * scale, height: height, fill: KP.fg.opacity(0.16))
        KPSkeleton(width: 120 * scale, height: height)
        KPSkeleton(width: 140 * scale, height: height)
        KPSkeleton(width: 80 * scale, height: height)
        KPSkeleton(width: height, height: height)
    }
}

/// Under the banner while the page loads: the cast row's shape (circles and names), then a block of facts.
private struct DetailsSectionsPlaceholder: View {
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionGap) {
            VStack(alignment: .leading, spacing: metrics.stackGap) {
                KPSkeleton(width: 120, height: metrics.section, radius: 6)
                HStack(alignment: .top, spacing: metrics.compact ? 14 : 16) {
                    ForEach(0 ..< 10, id: \.self) { _ in
                        VStack(spacing: 8) {
                            KPSkeleton(width: metrics.personPhoto, height: metrics.personPhoto, shape: Circle())
                            KPSkeleton(width: metrics.personPhoto * 0.8, height: 10)
                            KPSkeleton(width: metrics.personPhoto * 0.55, height: 9)
                        }
                        .frame(width: metrics.personColumn)
                    }
                }
                .padding(.vertical, 12)
            }

            VStack(alignment: .leading, spacing: metrics.stackGap + 4) {
                KPSkeleton(width: 140, height: metrics.section, radius: 6)
                ForEach([520, 440, 480, 360] as [CGFloat], id: \.self) { width in
                    KPSkeleton(width: width, height: 13)
                }
            }
        }
        .padding(.horizontal, KP.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}
