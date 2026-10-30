import Foundation

/// A mood the user can ask for. Until the embedding stage these map onto the site's genres (`MoodMap`).
public enum Mood: String, Codable, Sendable, Hashable, CaseIterable {
    /// «Посмеяться».
    case laugh
    /// «Напряжение».
    case tension
    /// «Подумать».
    case think
    /// «Уютное».
    case cozy
    /// «Погрустить».
    case cry
    /// «Пострашнее».
    case scare
}

/// Who's watching.
public enum Company: String, Codable, Sendable, Hashable, CaseIterable {
    case solo
    case couple
    case family
    case friends
}

/// How much time there is.
public enum TimeBudget: Codable, Sendable, Hashable {
    /// A film or episode up to N minutes.
    case maxMinutes(Int)
    /// An episode of a series between these lengths.
    case episode(ClosedRange<Int>)
    /// A full-length film for the evening.
    case filmNight
    /// A series to binge over the weekend.
    case weekendSeries
}

/// A rating floor («КП от 7»).
public struct RatingFloor: Codable, Sendable, Hashable {
    public enum Source: String, Codable, Sendable, Hashable {
        case kp
        case imdb
        case rt
        case any
    }

    public var source: Source
    public var value: Double

    public init(source: Source, value: Double) {
        self.source = source
        self.value = value
    }
}

/// Include/exclude sets for a facet (genres, countries).
public struct Facets: Codable, Sendable, Hashable {
    public var include: Set<String>
    public var exclude: Set<String>

    public init(include: Set<String> = [], exclude: Set<String> = []) {
        self.include = include
        self.exclude = exclude
    }

    public var isEmpty: Bool { include.isEmpty && exclude.isEmpty }
}

/// The one contract between the rules parser, the engine and (later) an LLM: what the user wants to watch now.
/// Empty fields mean «без разницы».
public struct WatchIntent: Codable, Sendable, Hashable {
    public enum Field: String, Codable, Sendable, Hashable, CaseIterable {
        case kinds
        case moods
        case company
        case time
        case genres
        case countries
        case years
        case minRating
        case familiarity
        case similarTo
        case people
        case avoid
    }

    public var kinds: Set<TitleKind>?
    /// Mood → strength (0…1).
    public var moods: [Mood: Double]
    public var company: Company?
    public var time: TimeBudget?
    public var genres: Facets
    public var countries: Facets
    public var years: ClosedRange<Int>?
    public var minRating: RatingFloor?
    /// 0 = only the familiar (bookmarks, next parts) … 1 = discoveries.
    public var familiarity: Double?
    /// Title ids from the pool («как «Мост»»).
    public var similarTo: [String]
    /// People found on the site («с Ди Каприо»).
    public var people: [PersonRef]
    /// Themes to avoid that aren't genres («не про войну»): matched against genres and names for now.
    public var avoid: [String]
    /// Whatever the rules didn't understand (for the embedding stage).
    public var freeText: String?
    /// How sure the parser is per field (0…1), for merging rules with an LLM and for the clarifying question.
    public var confidence: [Field: Double]

    public init(
        kinds: Set<TitleKind>? = nil, moods: [Mood: Double] = [:], company: Company? = nil, time: TimeBudget? = nil,
        genres: Facets = Facets(), countries: Facets = Facets(), years: ClosedRange<Int>? = nil,
        minRating: RatingFloor? = nil, familiarity: Double? = nil, similarTo: [String] = [], people: [PersonRef] = [],
        avoid: [String] = [], freeText: String? = nil, confidence: [Field: Double] = [:]
    ) {
        self.kinds = kinds
        self.moods = moods
        self.company = company
        self.time = time
        self.genres = genres
        self.countries = countries
        self.years = years
        self.minRating = minRating
        self.familiarity = familiarity
        self.similarTo = similarTo
        self.people = people
        self.avoid = avoid
        self.freeText = freeText
        self.confidence = confidence
    }

    public static let empty = WatchIntent()
}

/// A chip that shows how a request was understood («Понял так: лёгкое · до 1,5 ч · вдвоём»), removable one by one.
public struct IntentChip: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var field: WatchIntent.Field
    public var label: String

    public init(id: String, field: WatchIntent.Field, label: String) {
        self.id = id
        self.field = field
        self.label = label
    }
}

/// What the rules parser got from free text: the intent plus what still needs looking up on the site.
public struct ParsedRequest: Codable, Sendable, Hashable {
    public var intent: WatchIntent
    public var chips: [IntentChip]
    /// «как X / типа X / похожее на X»: names to find in the pool (then on the site).
    public var similarQueries: [String]
    /// People to find on the site («Нолан», «с Ди Каприо»).
    public var peopleQueries: [String]
    /// The request was off-topic («какая погода»): answer that we pick what to watch.
    public var offTopic: Bool

    public init(intent: WatchIntent, chips: [IntentChip], similarQueries: [String] = [], peopleQueries: [String] = [], offTopic: Bool = false) {
        self.intent = intent
        self.chips = chips
        self.similarQueries = similarQueries
        self.peopleQueries = peopleQueries
        self.offTopic = offTopic
    }
}

/// The critique buttons under the pick.
public enum Critique: Codable, Sendable, Hashable {
    /// «Полегче».
    case lighter
    /// «Помрачнее».
    case darker
    /// «Покороче».
    case shorter
    /// «Поновее».
    case newer
    /// «Постарше».
    case older
    /// «Не про…»: exclude a genre or theme.
    case notAbout(String)
    /// «Ещё такое же».
    case moreLikeThis
}

/// Where «Выбери за меня» picks from.
public enum PickPool: String, Codable, Sendable, Hashable, CaseIterable {
    /// «Своё»: bookmarks without progress, «Можно начать», next parts, next episodes.
    case own
    /// «Микс»: own plus the top confident matches.
    case mix
    /// «Открытия»: far graph links and exploration.
    case discover
}

/// One step of «Выбери за меня»: the intent so far and what was already shown this session.
public struct PickRequest: Codable, Sendable, Hashable {
    public var intent: WatchIntent
    public var pool: PickPool
    /// Titles shown this session (not shown again; «Другое» = ×0.7 for the rest of the session).
    public var shown: [String]
    /// How many times «Другое» was pressed (3 → a grid of three, 5 → «Уточнить настроение?»).
    public var skips: Int
    /// The session's seed: going back gives the same pick.
    public var seed: UInt64
    /// Whether the clarifying question was already asked this session (at most once).
    public var askedQuestion: Bool

    public init(intent: WatchIntent, pool: PickPool = .mix, shown: [String] = [], skips: Int = 0, seed: UInt64, askedQuestion: Bool = false) {
        self.intent = intent
        self.pool = pool
        self.shown = shown
        self.skips = skips
        self.seed = seed
        self.askedQuestion = askedQuestion
    }
}

/// A constraint the picker dropped because nothing matched («Ровно такого нет — убрал «до 90 минут». [Вернуть]»).
public struct Relaxation: Codable, Sendable, Hashable {
    public var field: WatchIntent.Field
    /// «убрал «до 90 минут»».
    public var label: String

    public init(field: WatchIntent.Field, label: String) {
        self.field = field
        self.label = label
    }
}

/// The one clarifying question, asked with buttons («Фильм или пара серий?»).
public struct ClarifyingQuestion: Codable, Sendable, Hashable {
    public struct Option: Codable, Sendable, Hashable {
        public var label: String
        public var intent: WatchIntent

        public init(label: String, intent: WatchIntent) {
            self.label = label
            self.intent = intent
        }
    }

    public var text: String
    public var options: [Option]

    public init(text: String, options: [Option]) {
        self.text = text
        self.options = options
    }
}

/// What «Выбери за меня» shows.
public struct PickResult: Codable, Sendable, Hashable {
    public var main: Recommendation?
    public var alternatives: [Recommendation]
    /// After three skips: a grid of three.
    public var showGrid: Bool
    public var relaxed: [Relaxation]
    public var question: ClarifyingQuestion?
    /// «Уточнить настроение?» after five skips.
    public var suggestRefine: Bool
    /// The intent actually used (after relaxation), for the chips.
    public var effectiveIntent: WatchIntent

    public init(
        main: Recommendation?, alternatives: [Recommendation], showGrid: Bool, relaxed: [Relaxation],
        question: ClarifyingQuestion?, suggestRefine: Bool, effectiveIntent: WatchIntent
    ) {
        self.main = main
        self.alternatives = alternatives
        self.showGrid = showGrid
        self.relaxed = relaxed
        self.question = question
        self.suggestRefine = suggestRefine
        self.effectiveIntent = effectiveIntent
    }
}

/// «Вам подойдёт?» on a title's page.
public struct FitVerdict: Codable, Sendable, Hashable {
    public enum Level: String, Codable, Sendable, Hashable {
        case likely
        case maybe
        case unlikely
    }

    public var level: Level
    /// Up to two pluses and one minus («+ психологический триллер — ваш жанр № 1»).
    public var pros: [String]
    public var cons: [String]

    public init(level: Level, pros: [String], cons: [String]) {
        self.level = level
        self.pros = pros
        self.cons = cons
    }
}

/// «Почему это?»: the top contributions, the path, the reason.
public struct Explanation: Codable, Sendable, Hashable {
    public var titleId: String
    public var reason: Reason
    /// The top three contributions as sentences.
    public var lines: [String]
    /// The graph path as names, when there is one.
    public var path: [String]
    /// The main feature behind the reason, for «Меньше такого».
    public var mainFeature: FeatureKey?
    /// The main anchor, for «Не учитывать «X»».
    public var mainAnchorId: String?

    public init(titleId: String, reason: Reason, lines: [String], path: [String], mainFeature: FeatureKey?, mainAnchorId: String?) {
        self.titleId = titleId
        self.reason = reason
        self.lines = lines
        self.path = path
        self.mainFeature = mainFeature
        self.mainAnchorId = mainAnchorId
    }
}
