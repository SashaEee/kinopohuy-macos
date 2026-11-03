import Foundation
import RecommenderCore

// The rules behind the recommendation screens (the title page's bar, the cards' menus, the rating after watching,
// «Досмотреть»'s segments, the taste stack, Settings), kept apart from the views: Foundation and RecommenderCore
// only, so `RecsAppLogic` tests them with `swift test` (this file is linked there as is).

// MARK: - The three levels

/// «Не моё · Нравится · Обожаю»: three levels instead of stars (thumbs got Netflix twice the ratings of five stars).
enum TasteLevel: String, CaseIterable, Sendable, Hashable {
    case notForMe
    case like
    case love

    /// What the recommender stores: −2 («Не моё», never shown again), +1, +2.
    var level: Double {
        switch self {
        case .notForMe: -2
        case .like: 1
        case .love: 2
        }
    }

    var title: String {
        switch self {
        case .notForMe: "Не моё"
        case .like: "Нравится"
        case .love: "Обожаю"
        }
    }

    var symbol: String {
        switch self {
        case .notForMe: "hand.thumbsdown"
        case .like: "hand.thumbsup"
        case .love: "heart"
        }
    }

    /// The filled symbol while it's the chosen one.
    var activeSymbol: String { symbol + ".fill" }

    /// The digit that chooses it (the taste stack, the rating after watching).
    var key: Character {
        switch self {
        case .notForMe: "1"
        case .like: "2"
        case .love: "3"
        }
    }

    /// Which button a stored level lights up. Imports and the site's own scale land between the levels (−1.5 for a
    /// site rating of 4 or less, 0 for «смотрел» at 5–6): the nearest button, and none for the neutral «смотрел».
    init?(stored: Double?) {
        guard let stored else { return nil }
        if stored >= 1.5 {
            self = .love
        } else if stored >= 0.5 {
            self = .like
        } else if stored <= -1 {
            self = .notForMe
        } else {
            return nil
        }
    }

    /// A press on `tapped` when `current` is lit: the lit one again clears it, another one takes its place.
    static func toggled(current: TasteLevel?, tapped: TasteLevel) -> TasteLevel? {
        current == tapped ? nil : tapped
    }
}

// MARK: - The site's own rating, copied here

/// The site never gives its rating back, so a rating sent to it is kept here too, on the three-level scale (the plan's
/// import scale): 9–10 «Обожаю», 7–8 «Нравится», 5–6 «смотрел» (neutral), 4 or less «Не моё» but softer than the
/// button (−1.5).
enum SiteRatingMirror {
    static func level(for score: Int) -> Double? {
        switch score {
        case 9 ... 10: 2
        case 7 ... 8: 1
        case 5 ... 6: 0
        case 1 ... 4: -1.5
        default: nil
        }
    }
}

// MARK: - What a menu or a bar does to a title

/// Everything a person can say about a title from the cards' menus, the title page's bar and «Досмотреть», and what
/// the recommender records for it: a rating, or a service mark (hidden, seen, not today…).
enum TitleAction: String, CaseIterable, Sendable, Hashable {
    case notForMe
    case like
    case love
    case hidden
    case seen
    case notToday
    case notMe
    case continueHidden
    case dropped

    init(_ level: TasteLevel) {
        switch level {
        case .notForMe: self = .notForMe
        case .like: self = .like
        case .love: self = .love
        }
    }

    /// The rating it sets, if it's one of the three levels.
    var rating: Double? {
        switch self {
        case .notForMe: TasteLevel.notForMe.level
        case .like: TasteLevel.like.level
        case .love: TasteLevel.love.level
        default: nil
        }
    }

    /// The service mark it sets otherwise.
    var feedback: FeedbackKind? {
        switch self {
        case .hidden: .hidden
        case .seen: .seen
        case .notToday: .notToday
        case .notMe: .notMe
        case .continueHidden: .continueHidden
        case .dropped: .dropped
        case .notForMe, .like, .love: nil
        }
    }

    /// The menu item.
    var title: String {
        switch self {
        case .notForMe: "Не моё"
        case .like: "Нравится"
        case .love: "Обожаю"
        case .hidden: "Скрыть"
        case .seen: "Уже смотрел"
        case .notToday: "Не сегодня"
        case .notMe: "Это смотрел не я"
        case .continueHidden: "Убрать из ряда"
        case .dropped: "Бросил"
        }
    }

    var symbol: String {
        switch self {
        case .notForMe: "hand.thumbsdown"
        case .like: "hand.thumbsup"
        case .love: "heart"
        case .hidden: "eye.slash"
        case .seen: "checkmark.circle"
        case .notToday: "moon.zzz"
        case .notMe: "person.crop.circle.badge.xmark"
        case .continueHidden: "rectangle.stack.badge.minus"
        case .dropped: "xmark.circle"
        }
    }

    /// The short line a card shows once it's done, so the press is felt without a dialog (≤ ~22 characters: it sits on
    /// a poster).
    var confirmation: String {
        switch self {
        case .notForMe, .hidden: "Больше не покажем"
        case .like: "Учтём"
        case .love: "Учтём: любимое"
        case .seen: "Отметили"
        case .notToday: "Вернём через неделю"
        case .notMe: "Не учитываем просмотр"
        case .continueHidden: "Убрали из ряда"
        case .dropped: "Отметили: бросили"
        }
    }

    /// The menu's explanation of what it changes (shown as help).
    var help: String {
        switch self {
        case .notForMe: "Больше не советовать, и похожего станет меньше"
        case .like: "Советовать больше похожего"
        case .love: "Советовать похожее в первую очередь"
        case .hidden: "Не показывать в рекомендациях; вкус не меняется"
        case .seen: "Смотрели в другом месте: не советовать"
        case .notToday: "Не показывать неделю"
        case .notMe: "Просмотр не ваш (общий аккаунт, случайный клик): вкус его не учтёт"
        case .continueHidden: "Убрать из «Продолжить просмотр»; прогресс на сайте останется"
        case .dropped: "Больше не смотрите: тайтл уйдёт из «Похоже, бросили?»"
        }
    }

    /// The service mark as a feedback kind's own action (for undoing what a set holds).
    static func of(_ kind: FeedbackKind) -> TitleAction? {
        allCases.first { $0.feedback == kind }
    }

    /// The quiet label of a mark that's on (the title page lists them, each with «×» to take it back).
    var activeLabel: String {
        switch self {
        case .hidden: "Скрыто"
        case .seen: "Смотрели"
        case .notToday: "Не сегодня"
        case .notMe: "Смотрел не я"
        case .continueHidden: "Убрано из ряда"
        case .dropped: "Брошено"
        case .notForMe, .like, .love: title
        }
    }
}

// MARK: - «Досмотреть» in segments

/// «Досмотреть» isn't a dump of 300 titles: what's going on, what's waiting to start, what looks abandoned, and what's
/// done (the plan's §2.6, after Trakt's smart lists).
enum WatchingSegment: String, CaseIterable, Sendable, Hashable, Identifiable {
    case continueWatching
    case canStart
    case abandoned
    case watched

    var id: Self { self }

    var title: String {
        switch self {
        case .continueWatching: "Продолжить"
        case .canStart: "Можно начать"
        case .abandoned: "Похоже, бросили?"
        case .watched: "Досмотрено"
        }
    }

    /// Days of quiet after which a barely started title looks abandoned.
    static let abandonedAfterDays = 60
    /// Activity this recent keeps a title in «Продолжить».
    static let recentDays = 30

    /// Which segment a title of the list falls in; nil when it was taken off the row or dropped (then it's only under
    /// «Все»). Without a date the benefit of the doubt goes to «Продолжить».
    static func classify(_ facts: WatchingFacts, now: Date) -> WatchingSegment? {
        if facts.watched { return .watched }
        if facts.isSetAside { return nil }
        guard facts.isStarted else { return .canStart }
        if facts.hasNewEpisode { return .continueWatching }
        guard let last = facts.lastActivity else { return .continueWatching }
        let days = now.timeIntervalSince(last) / 86400
        if days <= Double(recentDays) { return .continueWatching }
        if days > Double(abandonedAfterDays), facts.isBarelyStarted { return .abandoned }
        return .continueWatching
    }
}

/// What's known of a title in «Досмотреть»: the site's card (watched, where you are, its date) and this Mac's history.
struct WatchingFacts: Sendable, Hashable {
    var watched: Bool
    /// The latest of the site's date and this Mac's last play.
    var lastActivity: Date?
    var isSeries: Bool
    /// Where the site says you are («2 сезон 5 серия»), for a series.
    var season: Int?
    var episode: Int?
    /// How far this Mac got into a film (0…1; 1 once watched), when it played it.
    var filmFraction: Double?
    /// This Mac played it for 30 s or more (any episode).
    var playedHere: Bool
    /// More episodes came out than you've watched (the site's «Ещё N серий» with fresh activity, or the new-episodes
    /// feed).
    var hasNewEpisode: Bool = false
    /// «Убрать из ряда» or «Бросил» was pressed.
    var isSetAside: Bool = false

    /// Any progress at all: a series past its first episode, or something played here.
    var isStarted: Bool {
        if playedHere { return true }
        if let fraction = filmFraction, fraction > 0 { return true }
        if isSeries, let season, let episode { return season > 1 || episode > 1 }
        return false
    }

    /// At most half a film, or two episodes of a series, watched.
    var isBarelyStarted: Bool {
        if isSeries {
            guard let season, let episode else { return true }
            // On «1 сезон 3 серия» two are behind you.
            return season == 1 && episode - 1 <= 2
        }
        return (filmFraction ?? 0) <= 0.5
    }
}

/// The site's dates in «Досмотреть»: «12-10-2026», «12.10.2026», or «сегодня»/«вчера».
enum ActivityDate {
    static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> Date? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("сегодня") { return calendar.startOfDay(for: now) }
        if text.hasPrefix("вчера") { return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) }
        let parts = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        let (day, month, year) = (parts[0], parts[1], parts[2] < 100 ? 2000 + parts[2] : parts[2])
        guard (1 ... 31).contains(day), (1 ... 12).contains(month), (1990 ... 2200).contains(year) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

// MARK: - The taste stack

/// When and how the taste stack (onboarding, branch A) is offered.
enum TasteOnboardingRules {
    /// Fewer than this many of your own titles and there's nothing worth asking about yet.
    static let minimumOwnTitles = 5
    static let stackLimit = 12
    /// The deck grows with titles next to liked ones, up to this many cards in all.
    static let deckLimit = 30
    /// «Что вам близко?» starts with this many bubbles chosen from the data.
    static let preselectedBubbles = 6

    /// Once, signed in, with enough of your own titles to rate.
    static func shouldOffer(offered: Bool, signedIn: Bool, ownTitles: Int) -> Bool {
        !offered && signedIn && ownTitles >= minimumOwnTitles
    }

    /// «4 из 12».
    static func counter(index: Int, total: Int) -> String {
        "\(min(index + 1, total)) из \(total)"
    }
}

/// An answer in the taste stack: the three levels and «Не помню» (skipped, nothing recorded).
enum OnboardingChoice: String, CaseIterable, Sendable, Hashable {
    case notForMe
    case like
    case love
    case dontRemember

    init(_ level: TasteLevel) {
        switch level {
        case .notForMe: self = .notForMe
        case .like: self = .like
        case .love: self = .love
        }
    }

    var tasteLevel: TasteLevel? {
        switch self {
        case .notForMe: .notForMe
        case .like: .like
        case .love: .love
        case .dontRemember: nil
        }
    }

    /// 1 · 2 · 3 · 0, as on the buttons.
    init?(key: Character) {
        switch key {
        case "1": self = .notForMe
        case "2": self = .like
        case "3": self = .love
        case "0": self = .dontRemember
        default: return nil
        }
    }

    var key: Character {
        switch self {
        case .notForMe: "1"
        case .like: "2"
        case .love: "3"
        case .dontRemember: "0"
        }
    }

    var title: String {
        tasteLevel?.title ?? "Не помню"
    }
}

/// «Чего не показывать?»: the kinds and genres people most often don't want, as chips. A chip stands for the site's
/// section (anime, cartoons, TV shows) or its genre names; what else is excluded (from Settings) is left alone.
enum ExclusionChip: String, CaseIterable, Sendable, Hashable, Identifiable {
    case anime
    case cartoons
    case shows
    case documentary
    case horror
    case melodrama
    case reality

    var id: Self { self }

    var title: String {
        switch self {
        case .anime: "Аниме"
        case .cartoons: "Мультфильмы"
        case .shows: "ТВ-шоу"
        case .documentary: "Документальное"
        case .horror: "Ужасы"
        case .melodrama: "Мелодрамы"
        case .reality: "Реалити"
        }
    }

    var kinds: [TitleKind] {
        switch self {
        case .anime: [.anime]
        case .cartoons: [.cartoon]
        case .shows: [.show]
        default: []
        }
    }

    /// The site's genre names it covers (the spellings the site uses).
    var genres: [String] {
        switch self {
        case .documentary: ["Документальные", "Документальный"]
        case .horror: ["Ужасы"]
        case .melodrama: ["Мелодрамы"]
        case .reality: ["Реалити-шоу", "Реалити"]
        default: []
        }
    }

    /// The chips that are on for what's excluded now.
    static func selected(kinds: [String], genres: [String]) -> Set<ExclusionChip> {
        let kinds = Set(kinds), genres = Set(genres)
        return Set(allCases.filter { chip in
            (!chip.kinds.isEmpty && chip.kinds.allSatisfy { kinds.contains($0.rawValue) })
                || (!chip.genres.isEmpty && chip.genres.contains { genres.contains($0) })
        })
    }

    /// What's excluded with `chips` on and the others off; kinds and genres no chip stands for stay as they were.
    /// Sorted, so the stored lists don't churn.
    static func apply(_ chips: Set<ExclusionChip>, kinds: [String], genres: [String]) -> (kinds: [String], genres: [String]) {
        let managedKinds = Set(allCases.flatMap(\.kinds).map(\.rawValue))
        let managedGenres = Set(allCases.flatMap(\.genres))
        var newKinds = Set(kinds).subtracting(managedKinds)
        var newGenres = Set(genres).subtracting(managedGenres)
        for chip in chips {
            newKinds.formUnion(chip.kinds.map(\.rawValue))
            newGenres.formUnion(chip.genres)
        }
        return (newKinds.sorted(), newGenres.sorted())
    }
}

/// The age limits offered (0 = any).
enum AgeLimit: Int, CaseIterable, Sendable, Identifiable {
    case any = 0
    case six = 6
    case twelve = 12
    case sixteen = 16

    var id: Self { self }

    var title: String {
        switch self {
        case .any: "Любой"
        case .six: "До 6+"
        case .twelve: "До 12+"
        case .sixteen: "До 16+"
        }
    }

    /// The stored value as one of these (an 18 means any).
    init(stored: Int) {
        self = AgeLimit.allCases.last { $0.rawValue != 0 && $0.rawValue <= stored && stored < 18 } ?? .any
    }
}

// MARK: - The taste in words

enum TasteSummary {
    /// The chips of «Мы уже кое-что знаем» and Settings' «Ваш вкус»: the liked features with real support, strongest
    /// first, no repeats, then whether series or films win.
    static func chips(_ profile: ProfileSummary, limit: Int = 8) -> [String] {
        var seen: Set<String> = []
        var chips: [String] = []
        for feature in profile.top where feature.affinity > 0 && feature.support >= 2 {
            let name = feature.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            chips.append(name)
            if chips.count == limit { break }
        }
        if profile.positiveCount >= 5 {
            if profile.seriesShare >= 0.6 {
                chips.append("Сериалы чаще фильмов")
            } else if profile.seriesShare <= 0.3 {
                chips.append("Фильмы чаще сериалов")
            }
        }
        return chips
    }

    /// «Учтено 42 тайтла: 37 по душе, 5 нет».
    static func counts(_ profile: ProfileSummary) -> String? {
        let total = profile.positiveCount + profile.negativeCount
        guard total > 0 else { return nil }
        let head = "Учтено \(total) \(RussianPlural.form(total, "тайтл", "тайтла", "тайтлов"))"
        guard profile.negativeCount > 0 else { return head }
        return "\(head): \(profile.positiveCount) по душе, \(profile.negativeCount) нет"
    }
}

/// How far the catalogue has got, in one line: «Изучено 1 240 тайтлов из 3 120 · сегодня 84 из 300».
enum CatalogueStatusText {
    static func line(known: Int, pages: Int, fetchedToday: Int, dailyLimit: Int, enabled: Bool) -> String {
        var parts: [String] = []
        if known == 0 {
            parts.append("Каталог пока пуст: он растёт, пока вы листаете")
        } else {
            let studied = "Изучено \(RussianPlural.number(pages)) \(RussianPlural.form(pages, "тайтл", "тайтла", "тайтлов"))"
            parts.append(known > pages ? "\(studied) из \(RussianPlural.number(known))" : studied)
        }
        if enabled {
            if dailyLimit > 0 { parts.append("сегодня \(RussianPlural.number(fetchedToday)) из \(RussianPlural.number(dailyLimit))") }
        } else {
            parts.append("фоновое изучение выключено")
        }
        return parts.joined(separator: " · ")
    }
}

/// Russian plurals and numbers with a space between thousands («1 240»).
enum RussianPlural {
    static func form(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = abs(n) % 10, n100 = abs(n) % 100
        if n10 == 1, n100 != 11 { return one }
        if (2 ... 4).contains(n10), !(12 ... 14).contains(n100) { return few }
        return many
    }

    /// 1240 → «1 240» (a no-break space, so it never splits across lines).
    static func number(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (index, char) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append("\u{00A0}") }
            out.append(char)
        }
        return n < 0 ? "−" + out : out
    }
}

// MARK: - The rating after watching

/// «Как вам «…»?» after a film's credits or a season's finale: once per title, only while it's switched on and the
/// title has no rating yet.
enum PostPlayRules {
    /// The last 90 s count as watched, as the player itself treats them.
    static let creditsSeconds: Double = 90
    /// The titles asked about are kept up to this many (the oldest go first).
    static let memory = 400
    /// It hides by itself after this long.
    static let visibleSeconds: Double = 10

    /// Whether what's playing has just reached its end for asking: a film in its credits, or a season's last episode in
    /// its credits (or played to the end).
    static func reachedEnd(isSeries: Bool, isLastOfSeason: Bool, currentTime: Double, duration: Double?, finished: Bool) -> Bool {
        if isSeries, !isLastOfSeason { return false }
        if finished { return true }
        guard let duration, duration > creditsSeconds * 2 else { return false }
        return currentTime >= duration - creditsSeconds
    }

    static func shouldAsk(enabled: Bool, titleId: String?, asked: [String], hasRating: Bool) -> Bool {
        guard enabled, let titleId, !titleId.isEmpty else { return false }
        return !hasRating && !asked.contains(titleId)
    }

    /// `asked` with `titleId` added at the end, the oldest dropped beyond `memory`.
    static func remembering(_ titleId: String, in asked: [String], limit: Int = memory) -> [String] {
        var list = asked.filter { $0 != titleId }
        list.append(titleId)
        return list.count > limit ? Array(list.suffix(limit)) : list
    }

    /// «Как вам «Мост»?», a long name cut so the pill stays small.
    static func question(_ name: String, maxLength: Int = 30) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Как вам?" }
        let short = name.count > maxLength ? String(name.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…" : name
        return "Как вам «\(short)»?"
    }
}
