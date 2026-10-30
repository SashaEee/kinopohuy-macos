import SwiftUI

/// A title in «Продолжить просмотр» and «Досмотреть». A click goes on with it at once: the title's page opens and the
/// player starts where you stopped (a play disc shows under the pointer); a watched one just opens its page. Where you
/// are sits on the poster («1 сезон 7 серия · Дубляж»), what's left at its corner («Ещё 12 серий»), the years and the
/// day you watched under it («2017–2021 · 12.10.2026»). When this Mac played that very episode or film, a bar shows
/// how far, and the line under it says what's left («Осталось 42 мин · 12.10.2026»).
struct WatchingLaterCardView: View {
    private let movie: MovieWatchLater
    private let fixedWidth: CGFloat?

    @State private var hover = false
    @Environment(\.kpMetrics) private var metrics
    @Environment(\.kpWatchHistory) private var history
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// width: nil is the size tier's card width.
    init(movie: MovieWatchLater, width: CGFloat? = nil) {
        self.movie = movie
        fixedWidth = width
    }

    private var simple: MovieSimple { movie.simple }

    /// «1 сезон 7 серия (Дубляж)» → «1 сезон 7 серия · Дубляж»; a watched one says so.
    private var note: String? {
        if movie.watched { return "Просмотрено" }
        let info = movie.watchingInfo.trim()
        guard !info.isEmpty else { return nil }
        // The demo keeps only a series' place («1 сезон 7 серия»), never a voice-over.
        if KPDemo.isOn {
            let place = info.substringBefore("(").trim()
            return place.contains("сери") ? place : nil
        }
        guard info.contains("(") else { return info }
        let voice = info.substringAfter("(").substringBeforeLast(")").trim()
        let place = info.substringBefore("(").trim()
        return [place, voice].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// This Mac's progress, only if it's for where the site says you are: watched on, say, the TV since, a bar for an
    /// earlier episode would be wrong.
    private var progress: WatchHistory? {
        guard !movie.watched, let entry = history[movie.watchLaterId.id], entry.fraction != nil else { return nil }
        guard let place = movie.place else { return entry }
        // By number: the site writes «1 сезон», its ids may read «01».
        func same(_ a: String, _ b: String) -> Bool { Int(a).map { $0 == Int(b) } ?? (a == b) }
        return same(entry.season, place.season) && same(entry.episode, place.episode) ? entry : nil
    }

    /// «Осталось 42 мин · 12.10.2026», or «2017–2021 · 12.10.2026».
    private var subtitle: String? {
        let parts = [progress?.remainingText ?? movie.years, movie.date.replacingOccurrences(of: "-", with: ".").trim().firstLetterUppercased]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        KPRouteLink(route: movie.watched ? .details(simple) : .watch(simple)) {
            KPPosterCard(
                title: movie.name,
                subtitle: subtitle,
                kind: movie.watched ? nil : movie.episodesLeft,
                note: note,
                progress: progress?.fraction,
                width: fixedWidth ?? metrics.card,
                interactive: RecCardMarks.shared.mark(movie.watchLaterId.id) == nil
            ) {
                // Decoded at the card's fixed pixel size whatever the tier, so the title's page finds it in memory.
                KPRemoteImage(url: movie.cover, downsample: KP.cardPosterPixels())
                    .overlay {
                        if !movie.watched {
                            playDisc
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityHint(Text(verbatim: movie.watched ? "Открывает страницу" : "Продолжает просмотр"))
        .opacity(movie.watched ? 0.55 : 1)
        .disabled(movie.watchLaterId.id == nil)
        // «Убрать из ряда», «Это смотрел не я», «Не моё» from the menu: the poster says so, with «Вернуть».
        .overlay(alignment: .top) {
            RecCardMarkOverlay(titleId: movie.watchLaterId.id, width: fixedWidth ?? metrics.card)
        }
    }

    /// A click plays: the white disc says so under the pointer.
    private var playDisc: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(KP.ink)
            .offset(x: 1)
            .frame(width: 42, height: 42)
            .background(Circle().fill(KP.fg))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 4)
            .opacity(hover ? 1 : 0)
            .scaleEffect(hover || reduceMotion ? 1 : 0.8)
            .animation(.smooth(duration: 0.22), value: hover)
            .allowsHitTesting(false)
    }
}

extension WatchingLaterCardView: Equatable {
    nonisolated static func == (lhs: WatchingLaterCardView, rhs: WatchingLaterCardView) -> Bool {
        lhs.movie == rhs.movie
    }
}

extension MovieWatchLater {
    /// A fresh copy of the list with the ids the titles had in `old`: each fetch makes new ones, which would redraw
    /// every card and lose a row's scroll position although nothing changed.
    static func keepingIds(_ movies: [MovieWatchLater], from old: [MovieWatchLater]) -> [MovieWatchLater] {
        guard !old.isEmpty else { return movies }
        let ids = Dictionary(old.map { ($0.watchLaterId, $0.id) }, uniquingKeysWith: { first, _ in first })
        var used: Set<UUID> = []
        return movies.map { movie in
            guard let id = ids[movie.watchLaterId], used.insert(id).inserted else { return movie }
            return MovieWatchLater(
                watchLaterId: movie.watchLaterId, name: movie.name, cover: movie.cover, details: movie.details,
                watchingInfo: movie.watchingInfo, date: movie.date, buttonText: movie.buttonText, dataId: movie.dataId,
                watched: movie.watched, id: id
            )
        }
    }

    /// The title as a link target (its page, or straight into the player).
    var simple: MovieSimple {
        MovieSimple(movieId: watchLaterId, name: name, poster: cover)
    }

    /// The season and episode in «1 сезон 7 серия (Дубляж)»: the site's numbers, as the player saves them. nil for a film.
    var place: (season: String, episode: String)? {
        guard let match = watchingInfo.range(of: "(\\d+)\\s*сезон\\s*(\\d+)\\s*серия", options: .regularExpression) else { return nil }
        let numbers = watchingInfo[match].split(whereSeparator: { !$0.isNumber }).map(String.init)
        return numbers.count >= 2 ? (numbers[0], numbers[1]) : nil
    }

    /// «смотреть ещё 12 серий в 2 сезоне» → «Ещё 12 серий».
    var episodesLeft: String? {
        guard let text = buttonText,
              let match = text.range(of: "ещ[её]\\s+\\d+\\s+\\S+", options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let words = text[match].split(whereSeparator: \.isWhitespace).dropFirst()
        return (["Ещё"] + words.map(String.init)).joined(separator: " ")
    }

    /// «(2017-2021, проект завершен)» → «2017–2021», «(2011 - ...)» → «2011–…».
    var years: String {
        details
            .replacingOccurrences(of: "[()]", with: "", options: .regularExpression)
            .replacingOccurrences(of: ",\\s*проект завершен", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s*-\\s*\\.\\.\\.", with: "–…", options: .regularExpression)
            .replacingOccurrences(of: "\\s*-\\s*", with: "–", options: .regularExpression)
            .trim()
    }

    /// A series: it has a season in «where you are», or its years are still open («2011–…»).
    var isSeries: Bool {
        watchingInfo.contains("сезон") || details.contains("...") || details.contains("–…")
    }

    /// «1 сезон 7 серия (Дубляж)» → season 1, episode 7.
    var watchingEpisode: (season: Int, episode: Int)? {
        guard let match = watchingInfo.range(of: "\\d+\\s*сезон\\s*\\d+\\s*серия", options: .regularExpression) else { return nil }
        let numbers = watchingInfo[match].split { !$0.isNumber }.compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return (numbers[0], numbers[1])
    }
}

extension View {
    /// The continue list's right-click menu: go on watching, open the page, take it off the row («Убрать из ряда», the
    /// site's progress stays), «Это смотрел не я», «Не моё», mark it watched (or not), take it off the list.
    /// onAction: a screen that records these itself and redraws (e.g. «Досмотреть»'s segments); nil records them here
    /// and the card shows what was done.
    func kpWatchingMenu(_ movie: MovieWatchLater, switchWatched: @escaping () -> Void, remove: @escaping () -> Void, onAction: ((TitleAction) -> Void)? = nil) -> some View {
        modifier(WatchingMenu(movie: movie, switchWatched: switchWatched, remove: remove, onAction: onAction))
    }
}

private struct WatchingMenu: ViewModifier {
    let movie: MovieWatchLater
    let switchWatched: () -> Void
    let remove: () -> Void
    let onAction: ((TitleAction) -> Void)?

    @Environment(\.kpNavigate) private var navigate

    func body(content: Content) -> some View {
        content.contextMenu {
            if !movie.watched {
                Button {
                    navigate(.watch(movie.simple))
                } label: {
                    Label { Text(verbatim: "Продолжить просмотр") } icon: { Image(systemName: "play.fill") }
                }
            }
            Button {
                navigate(.details(movie.simple))
            } label: {
                Label { Text(verbatim: "Подробнее") } icon: { Image(systemName: "info.circle") }
            }
            if let titleId = movie.watchLaterId.id {
                Divider()
                // «Бросил» only where the screen can ask about the site's list too («Досмотреть»).
                TitleFeedbackMenuItems(
                    titleId: titleId,
                    actions: movie.watched ? [.notMe, .notForMe] : onAction == nil ? [.continueHidden, .notMe, .notForMe] : [.continueHidden, .dropped, .notMe, .notForMe],
                    perform: onAction
                )
            }
            Divider()
            Button {
                switchWatched()
            } label: {
                Label {
                    Text(verbatim: movie.watched ? "Отметить как непросмотренное" : "Отметить как просмотренное")
                } icon: {
                    Image(systemName: movie.watched ? "eye.slash" : "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                remove()
            } label: {
                Label { Text(verbatim: "Убрать из списка") } icon: { Image(systemName: "trash") }
            }
        }
    }
}
