import Defaults
import Dependencies
import Foundation
import RecommenderCore

/// Home's personal part, ready to draw: the engine's page and ranking plus the titles it refers to (names, posters,
/// paths), so views never look anything up.
struct RecSnapshot: Equatable, Sendable {
    var output: EngineOutput
    var titles: [String: TitleFeatures]
    var builtAt: Date

    static func == (lhs: RecSnapshot, rhs: RecSnapshot) -> Bool {
        lhs.builtAt == rhs.builtAt && lhs.output.page == rhs.output.page
    }

    /// The card a view needs for a recommended title.
    func simple(_ titleId: String) -> MovieSimple? {
        guard let title = titles[titleId] else { return nil }
        return MovieSimple(movieId: title.path, name: title.name, poster: title.poster)
    }
}

/// A «Досмотреть» title, as `continueStatus` needs it.
struct ContinueItem: Sendable, Hashable {
    var titleId: String
    var isSeries: Bool
}

/// «Оценил фильм — значит посмотрел» and «Убрать из ряда», for the rows that show «Досмотреть».
struct ContinueStatus: Equatable, Sendable {
    /// Done here: a film rated or marked «Уже смотрел».
    var done: Set<String> = []
    /// Set aside: «Убрать из ряда», «Бросил», «Не моё» on a series, «Это смотрел не я».
    var setAside: Set<String> = []
}

/// What «Импорт оценок» did: rows read, films recognised, and how many of those the app has already met on the site.
struct RatingImportResult: Equatable, Sendable {
    var source: String
    var total: Int
    var matched: Int
    var onSite: Int
}

/// The critics' scores the data pack has for a title.
struct CriticScores: Equatable, Sendable {
    var rottenTomatoes: Int?
    var metacritic: Int?
}

/// How far the local catalogue has got (Settings → «Рекомендации» → «Изучение каталога»).
struct RecStatus: Equatable, Sendable {
    /// Titles known at all (cards and pages).
    var known: Int
    /// Titles with their whole page read.
    var pages: Int
    /// Pages read in the background today, and the daily limit.
    var fetchedToday: Int
    var dailyLimit: Int
    var isEnriching: Bool
}

/// The recommender as the app sees it. The live value (Data/Recs) stores signals in the local database, keeps the
/// catalogue growing in the background, and runs RecommenderCore; features only call these closures.
struct RecommenderClient: Sendable {
    // Home and «Выбери за меня»
    /// The latest snapshot (cached instantly when possible; `force` rebuilds now).
    var home: @Sendable (_ force: Bool) async -> RecSnapshot?
    /// One step of «Выбери за меня».
    var pick: @Sendable (_ request: PickRequest) async -> PickResult
    /// Free text → intent, with «как X» and people looked up in the catalogue.
    var parse: @Sendable (_ text: String) async -> ParsedRequest
    /// The default intent for now (evening, late night, weekend).
    var contextIntent: @Sendable () -> WatchIntent
    var critique: @Sendable (_ critique: Critique, _ intent: WatchIntent, _ currentTitleId: String?) async -> WatchIntent
    var explain: @Sendable (_ titleId: String) async -> Explanation?
    var fit: @Sendable (_ titleId: String) async -> FitVerdict?
    /// The titles for the taste stack (onboarding A): the user's own, half uncertain, half confident.
    var onboardingStack: @Sendable () async -> [TitleFeatures]
    /// A title the engine knows (from the local catalogue).
    var title: @Sendable (_ titleId: String) async -> TitleFeatures?

    // Signals
    /// «Не моё» −2, «Нравится» +1, «Обожаю» +2 (and imports, site ratings mapped onto the scale).
    var rate: @Sendable (_ titleId: String, _ level: Double, _ source: ExplicitRating.Source) async -> Void
    var clearRating: @Sendable (_ titleId: String) async -> Void
    var rating: @Sendable (_ titleId: String) async -> Double?
    var feedback: @Sendable (_ titleId: String, _ kind: FeedbackKind) async -> Void
    var removeFeedback: @Sendable (_ titleId: String, _ kind: FeedbackKind) async -> Void
    var activeFeedback: @Sendable (_ titleId: String) async -> Set<FeedbackKind>
    var override: @Sendable (_ override: TasteOverride) async -> Void
    var clearOverride: @Sendable (_ feature: FeatureKey) async -> Void
    var overrides: @Sendable () async -> [TasteOverride]

    // «Уточнить вкус»
    /// «Что вам близко»: liked features first (pre-selected), then the common genres and countries.
    var tasteBubbles: @Sendable () async -> [FeatureAffinity]
    /// «Что хочется посмотреть?»: well-known titles not yet seen, to tick (interest, not a rating).
    var interestGrid: @Sendable () async -> [TitleFeatures]
    /// 0…1, «Вкус изучен на N %».
    var tasteConfidence: @Sendable () async -> Double
    /// Rotten Tomatoes (critics, %) and Metacritic (0–100) for a title page, from the data pack, by its IMDb id or its
    /// Kinopoisk id.
    var critics: @Sendable (_ imdbId: String?, _ kpId: Int?) async -> CriticScores?
    /// Which «Досмотреть» titles are done here (a rated film) and which are set aside: «Продолжить просмотр» and
    /// «Досмотреть» leave them out (or put them under «Досмотрено») before the site catches up.
    var continueStatus: @Sendable (_ items: [ContinueItem]) async -> ContinueStatus
    /// «Импорт оценок»: the text of an IMDb or Letterboxd CSV export; nil when it's neither.
    var importRatings: @Sendable (_ csv: String) async -> RatingImportResult?
    var recordImpressions: @Sendable (_ titleIds: [String], _ surface: String) async -> Void
    var markOpened: @Sendable (_ titleId: String) async -> Void
    /// A playing session ended (the player calls it on pause, close and end).
    var logSession: @Sendable (_ session: WatchSession) async -> Void

    // Passive capture: what the app reads anyway goes into the catalogue (no extra requests).
    var captureDetails: @Sendable (_ details: MovieDetailed) async -> Void
    var captureCards: @Sendable (_ cards: [MovieSimple], _ board: BoardRef?) async -> Void
    var captureAccountList: @Sendable (_ items: [MovieWatchLater]) async -> Void

    // Background and settings
    var status: @Sendable () async -> RecStatus
    /// Starts the background catalogue work (signed in only); safe to call again.
    var startBackground: @Sendable () async -> Void
    /// Fires whenever the recommendations changed (new signal, enrichment batch): Home redraws.
    var updates: @Sendable () -> AsyncStream<Void>
    /// «Сбросить вкус»: implicit weights and impressions go; ratings and exclusions stay.
    var resetTaste: @Sendable () async -> Void
    /// «Очистить все данные рекомендаций» (the catalogue cache stays).
    var clearAll: @Sendable () async -> Void
    /// Everything about taste as JSON (ratings, feedback, the catalogue ids), for «Экспорт…».
    var exportJSON: @Sendable () async -> Data?

    // More passive capture and the player's presence (defaults keep every existing call site as it is).
    /// Titles seen in a bookmark folder: the folder's name tells intent («Посмотреть потом») from favourites.
    var captureBookmarks: @Sendable (_ cards: [MovieSimple], _ folder: String) async -> Void = { _, _ in }
    /// The feed of new episodes: the series it marks as followed.
    var captureSeriesUpdates: @Sendable (_ groups: [SeriesUpdateGroup]) async -> Void = { _ in }
    /// A player window opened (true) or closed (false), by its own id: background reading waits while one is open.
    var playerPresence: @Sendable (_ windowId: UUID, _ isOpen: Bool) async -> Void = { _, _ in }
}

extension RecommenderClient: DependencyKey {
    static var liveValue: RecommenderClient { .live }

    /// Does nothing (previews, tests).
    static let noop = RecommenderClient(
        home: { _ in nil },
        pick: { PickResult(main: nil, alternatives: [], showGrid: false, relaxed: [], question: nil, suggestRefine: false, effectiveIntent: $0.intent) },
        parse: { _ in ParsedRequest(intent: .empty, chips: []) },
        contextIntent: { .empty },
        critique: { _, intent, _ in intent },
        explain: { _ in nil },
        fit: { _ in nil },
        onboardingStack: { [] },
        title: { _ in nil },
        rate: { _, _, _ in },
        clearRating: { _ in },
        rating: { _ in nil },
        feedback: { _, _ in },
        removeFeedback: { _, _ in },
        activeFeedback: { _ in [] },
        override: { _ in },
        clearOverride: { _ in },
        overrides: { [] },
        tasteBubbles: { [] },
        interestGrid: { [] },
        tasteConfidence: { 0 },
        critics: { _, _ in nil },
        continueStatus: { _ in ContinueStatus() },
        importRatings: { _ in nil },
        recordImpressions: { _, _ in },
        markOpened: { _ in },
        logSession: { _ in },
        captureDetails: { _ in },
        captureCards: { _, _ in },
        captureAccountList: { _ in },
        status: { RecStatus(known: 0, pages: 0, fetchedToday: 0, dailyLimit: 0, isEnriching: false) },
        startBackground: {},
        updates: { AsyncStream { $0.finish() } },
        resetTaste: {},
        clearAll: {},
        exportJSON: { nil },
    )

    static var testValue: RecommenderClient { .noop }
    static var previewValue: RecommenderClient { .noop }
}

extension DependencyValues {
    var recommender: RecommenderClient {
        get { self[RecommenderClient.self] }
        set { self[RecommenderClient.self] = newValue }
    }
}

// MARK: - Settings

extension Defaults.Keys {
    /// What Home's top shows: "tonight", "trends", "hidden".
    static let recHeroMode = Key<String>("rec_hero_mode", default: HeroMode.tonight.rawValue)
    /// 0 = familiar … 1 = discoveries.
    static let recFamiliarity = Key<Double>("rec_familiarity", default: 0.35)
    static let recExcludedKinds = Key<[String]>("rec_excluded_kinds", default: [])
    static let recExcludedGenres = Key<[String]>("rec_excluded_genres", default: [])
    /// The highest age rating to recommend; 0 = any.
    static let recMaxAge = Key<Int>("rec_max_age", default: 0)
    static let recPreferredVoiceOver = Key<String>("rec_preferred_voice_over", default: "")
    static let recUseLocalHistory = Key<Bool>("rec_use_local_history", default: true)
    static let recUseAccountList = Key<Bool>("rec_use_account_list", default: true)
    static let recUseBookmarks = Key<Bool>("rec_use_bookmarks", default: true)
    /// Background reading of title pages on the site (signed in only).
    static let recCrawlEnabled = Key<Bool>("rec_crawl_enabled", default: true)
    /// Pages per day: 150, 300, 600.
    static let recCrawlDailyLimit = Key<Int>("rec_crawl_daily_limit", default: 300)
    /// The small «Как вам «…»?» after a film or a season's finale.
    static let recAskAfterWatch = Key<Bool>("rec_ask_after_watch", default: true)
    /// The taste stack was offered (shown once).
    static let recOnboardingOffered = Key<Bool>("rec_onboarding_offered", default: false)
}

extension RecommenderSettings {
    /// The settings as stored in Defaults.
    static var current: RecommenderSettings {
        RecommenderSettings(
            excludedKinds: Set(Defaults[.recExcludedKinds].compactMap(TitleKind.init(rawValue:))),
            excludedGenres: Set(Defaults[.recExcludedGenres]),
            maxAge: Defaults[.recMaxAge] > 0 ? Defaults[.recMaxAge] : nil,
            familiarity: Defaults[.recFamiliarity],
            heroMode: HeroMode(rawValue: Defaults[.recHeroMode]) ?? .tonight,
            useLocalHistory: Defaults[.recUseLocalHistory],
            useAccountList: Defaults[.recUseAccountList],
            useBookmarks: Defaults[.recUseBookmarks],
            preferredVoiceOver: Defaults[.recPreferredVoiceOver].isEmpty ? nil : Defaults[.recPreferredVoiceOver],
        )
    }
}
