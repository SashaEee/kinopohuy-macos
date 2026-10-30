import Foundation

/// When the recommendations are asked for: the hero and «Выбери за меня» read the evening differently from a Sunday
/// afternoon.
public struct EngineContext: Codable, Sendable, Hashable {
    /// Seconds since 1970.
    public var now: Double
    /// 1 = Monday … 7 = Sunday (ISO), in the user's time zone.
    public var weekday: Int
    /// Local hour (0–23) and minute.
    public var hour: Int
    public var minute: Int

    public init(now: Double, weekday: Int, hour: Int, minute: Int) {
        self.now = now
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }

    /// Builds the context for a date in a calendar's time zone.
    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        // Calendar's weekday is 1 = Sunday; ISO is 1 = Monday.
        let weekday = parts.weekday ?? 2
        self.init(
            now: date.timeIntervalSince1970,
            weekday: weekday == 1 ? 7 : weekday - 1,
            hour: parts.hour ?? 20,
            minute: parts.minute ?? 0,
        )
    }
}

/// What Home's top shows.
public enum HeroMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// «Сегодня вечером» (falls back to trends while taste is too thin).
    case tonight
    /// The site's trends, as before.
    case trends
    /// Nothing.
    case hidden
}

/// The user's settings that shape recommendations.
public struct RecommenderSettings: Codable, Sendable, Hashable {
    public var excludedKinds: Set<TitleKind>
    /// Genre names never to recommend («Ужасы»).
    public var excludedGenres: Set<String>
    /// The highest age rating to recommend, nil for any.
    public var maxAge: Int?
    /// 0 = only the familiar … 1 = discoveries; the Home mix and the «Выбери за меня» default.
    public var familiarity: Double
    public var heroMode: HeroMode
    public var useLocalHistory: Bool
    public var useAccountList: Bool
    public var useBookmarks: Bool
    /// Prefer titles that have this voice-over (empty: no preference).
    public var preferredVoiceOver: String?

    public init(
        excludedKinds: Set<TitleKind> = [], excludedGenres: Set<String> = [], maxAge: Int? = nil,
        familiarity: Double = 0.35, heroMode: HeroMode = .tonight, useLocalHistory: Bool = true,
        useAccountList: Bool = true, useBookmarks: Bool = true, preferredVoiceOver: String? = nil
    ) {
        self.excludedKinds = excludedKinds
        self.excludedGenres = excludedGenres
        self.maxAge = maxAge
        self.familiarity = familiarity
        self.heroMode = heroMode
        self.useLocalHistory = useLocalHistory
        self.useAccountList = useAccountList
        self.useBookmarks = useBookmarks
        self.preferredVoiceOver = preferredVoiceOver
    }
}

/// Where a candidate came from (the plan's S1–S7).
public enum SourceKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// S1: the site's graph (watch-also, lists, collections, franchises, people), personalized PageRank.
    case graph
    /// S2: the next part, a new season.
    case continuation
    /// S3: bookmarks and «Можно начать».
    case intent
    /// S4: taste affinity over features.
    case affinity
    /// S5: directors and actors you like.
    case people
    /// S6: the site's best lists and trends, intersected with taste; new releases.
    case qualityFresh
    /// S7: something new for you.
    case exploration
}

/// Why a title is recommended: the kind decides the template (and its priority when contributions are close).
public enum ReasonKind: String, Codable, Sendable, Hashable, CaseIterable {
    case nextEpisode
    case nextPart
    case newSeason
    case becauseWatched
    case similarToMany
    case loved
    case person
    case rankedList
    case collection
    case bookmark
    case featureCombo
    case critics
    case discovery
    case trending
    case canStart
}

/// The proof behind a reason: what in the user's history or the title makes it true.
public struct Evidence: Codable, Sendable, Hashable {
    /// Anchor titles (history) that led here.
    public var anchorIds: [String]
    /// The path through the site's graph, as names («Мост» → «Смотрите также» → «Убийство»).
    public var path: [String]
    public var board: BoardRef?
    public var person: PersonRef?
    /// How many of the user's titles share it (verifiable counts: «3 его фильма»).
    public var count: Int?
    public var features: [FeatureKey]
    /// The bookmark folder an intent comes from («На выходные»).
    public var folder: String?
    /// What an intent to watch rests on (S3): a bookmark, «Досмотреть», a followed series.
    public var origin: IntentOrigin?

    public init(
        anchorIds: [String] = [], path: [String] = [], board: BoardRef? = nil, person: PersonRef? = nil,
        count: Int? = nil, features: [FeatureKey] = [], folder: String? = nil, origin: IntentOrigin? = nil
    ) {
        self.anchorIds = anchorIds
        self.path = path
        self.board = board
        self.person = person
        self.count = count
        self.features = features
        self.folder = folder
        self.origin = origin
    }
}

/// Where an intent to watch comes from: «Из закладок «На выходные»», «Ждёт в «Досмотреть»», «Вы отслеживаете».
public enum IntentOrigin: String, Codable, Sendable, Hashable, CaseIterable {
    case bookmark
    case accountList
    case followed
}

/// One reason, ready to show: a short line on the card and a longer one for «Почему это?».
public struct Reason: Codable, Sendable, Hashable {
    public var kind: ReasonKind
    /// The card's line, ≤ ~28 characters where possible («Похоже на «Мост»»).
    public var short: String
    /// The full sentence («Потому что вы досмотрели «Мост» и «Убийство»»).
    public var long: String
    public var evidence: Evidence

    public init(kind: ReasonKind, short: String, long: String, evidence: Evidence) {
        self.kind = kind
        self.short = short
        self.long = long
        self.evidence = evidence
    }
}

/// A source's share in a title's score (for «Почему это?» and the debug view).
public struct SourceContribution: Codable, Sendable, Hashable {
    public var source: SourceKind
    public var rank: Int
    public var value: Double
    public var evidence: Evidence

    public init(source: SourceKind, rank: Int, value: Double, evidence: Evidence) {
        self.source = source
        self.rank = rank
        self.value = value
        self.evidence = evidence
    }
}

/// A recommended title with its score, where it came from and why.
public struct Recommendation: Codable, Sendable, Hashable, Identifiable {
    public var titleId: String
    public var score: Double
    public var contributions: [SourceContribution]
    public var reason: Reason
    /// Up to three tags («детектив · Скандинавия · мини-сериал»).
    public var tags: [String]

    public var id: String { titleId }

    public init(titleId: String, score: Double, contributions: [SourceContribution], reason: Reason, tags: [String]) {
        self.titleId = titleId
        self.score = score
        self.contributions = contributions
        self.reason = reason
        self.tags = tags
    }
}

/// A Home row.
public struct RecRow: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case forYou
        case becauseWatched
        case becauseLoved
        case continuation
        case person
        case collections
        case discover
        case canStart
    }

    public var id: String
    public var kind: Kind
    /// «Потому что вы досмотрели «Мост»».
    public var title: String
    public var items: [Recommendation]
    /// The anchor, person or board the row is about.
    public var anchorId: String?
    public var person: PersonRef?
    public var board: BoardRef?

    public init(
        id: String, kind: Kind, title: String, items: [Recommendation], anchorId: String? = nil,
        person: PersonRef? = nil, board: BoardRef? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.items = items
        self.anchorId = anchorId
        self.person = person
        self.board = board
    }
}

/// «Сегодня вечером»: one main pick and two alternatives of another kind or genre.
public struct TonightHero: Codable, Sendable, Hashable {
    public var main: Recommendation
    public var alternatives: [Recommendation]
    /// What the context asked for («Фильм на вечер», «Серия на 40 минут»).
    public var contextLabel: String

    public init(main: Recommendation, alternatives: [Recommendation], contextLabel: String) {
        self.main = main
        self.alternatives = alternatives
        self.contextLabel = contextLabel
    }
}

/// Home's personal part: the hero and the rows, no title twice.
public struct PageLayout: Codable, Sendable, Hashable {
    public var hero: TonightHero?
    public var rows: [RecRow]

    public init(hero: TonightHero?, rows: [RecRow]) {
        self.hero = hero
        self.rows = rows
    }
}

/// A taste feature with its affinity (−1…1) and how many titles back it.
public struct FeatureAffinity: Codable, Sendable, Hashable {
    public var feature: FeatureKey
    /// The display name («Детективы», «Скандинавия», «2010-е», «Дэвид Финчер»).
    public var name: String
    public var affinity: Double
    public var support: Int

    public init(feature: FeatureKey, name: String, affinity: Double, support: Int) {
        self.feature = feature
        self.name = name
        self.affinity = affinity
        self.support = support
    }
}

/// The taste in brief, for the onboarding's chips and the settings' «Ваш вкус».
public struct ProfileSummary: Codable, Sendable, Hashable {
    public var top: [FeatureAffinity]
    public var disliked: [FeatureAffinity]
    /// Titles with a positive weight (anchors) and with a negative one.
    public var positiveCount: Int
    public var negativeCount: Int
    /// Series share among positive titles (0…1).
    public var seriesShare: Double

    public init(top: [FeatureAffinity], disliked: [FeatureAffinity], positiveCount: Int, negativeCount: Int, seriesShare: Double) {
        self.top = top
        self.disliked = disliked
        self.positiveCount = positiveCount
        self.negativeCount = negativeCount
        self.seriesShare = seriesShare
    }

    public static let empty = ProfileSummary(top: [], disliked: [], positiveCount: 0, negativeCount: 0, seriesShare: 0)
}

/// What the engine needs: the pool (titles the app has seen on the site), the user's signals and settings.
public struct EngineInput: Codable, Sendable {
    public var context: EngineContext
    public var titles: [TitleFeatures]
    public var signals: UserSignals
    public var settings: RecommenderSettings
    public var weights: Weights
    /// Seeds every random choice, so the same day and profile give the same page.
    public var seed: UInt64

    public init(
        context: EngineContext, titles: [TitleFeatures], signals: UserSignals, settings: RecommenderSettings,
        weights: Weights = .default, seed: UInt64
    ) {
        self.context = context
        self.titles = titles
        self.signals = signals
        self.settings = settings
        self.weights = weights
        self.seed = seed
    }

    /// Weights are optional in JSON (an export without them, or with a partial set, uses the defaults).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        context = try c.decode(EngineContext.self, forKey: .context)
        titles = try c.decode([TitleFeatures].self, forKey: .titles)
        signals = try c.decode(UserSignals.self, forKey: .signals)
        settings = try c.decodeIfPresent(RecommenderSettings.self, forKey: .settings) ?? RecommenderSettings()
        weights = try c.decodeIfPresent(Weights.self, forKey: .weights) ?? .default
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 0
    }
}

/// What the engine gives back: Home's page, the ranked candidates (the pool of «Выбери за меня») and the taste.
public struct EngineOutput: Codable, Sendable {
    public var page: PageLayout
    /// All scored candidates after filters, best first (not diversified).
    public var ranked: [Recommendation]
    public var profile: ProfileSummary
    /// The title weights after signals and decay (for the debug view and the onboarding's picks).
    public var titleWeights: [String: Double]
    /// Whether taste is thin (fewer than 5 positive signals): Home keeps trends in the hero.
    public var isColdStart: Bool

    public init(
        page: PageLayout, ranked: [Recommendation], profile: ProfileSummary, titleWeights: [String: Double],
        isColdStart: Bool
    ) {
        self.page = page
        self.ranked = ranked
        self.profile = profile
        self.titleWeights = titleWeights
        self.isColdStart = isColdStart
    }
}
