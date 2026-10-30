import Foundation

/// One playing session of a title on this Mac: opened in the player, closed (paused, ended, switched away).
public struct WatchSession: Codable, Sendable, Hashable {
    public var titleId: String
    public var season: String?
    public var episode: String?
    public var startedAt: Double
    public var endedAt: Double
    /// Seconds into the stream when the session began and ended.
    public var fromPosition: Double
    public var toPosition: Double
    /// The stream's length in seconds (0 if unknown).
    public var duration: Double
    /// Played to the credits or the end.
    public var completed: Bool

    public init(
        titleId: String, season: String?, episode: String?, startedAt: Double, endedAt: Double,
        fromPosition: Double, toPosition: Double, duration: Double, completed: Bool
    ) {
        self.titleId = titleId
        self.season = season
        self.episode = episode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.fromPosition = fromPosition
        self.toPosition = toPosition
        self.duration = duration
        self.completed = completed
    }
}

/// What this Mac remembers of a title without the session log (the player's saved positions): how far into the film,
/// or how many episodes were watched to the end.
public struct LocalProgress: Codable, Sendable, Hashable {
    public var titleId: String
    /// A film's fraction (0…1), 1 once watched; nil for series.
    public var filmFraction: Double?
    /// Episodes watched to the end (series).
    public var episodesWatched: Int
    /// Episodes started at all (series).
    public var episodesStarted: Int
    /// The furthest season reached (series), as a number when it parses.
    public var lastSeason: Int?
    public var updatedAt: Double

    public init(
        titleId: String, filmFraction: Double?, episodesWatched: Int, episodesStarted: Int, lastSeason: Int?,
        updatedAt: Double
    ) {
        self.titleId = titleId
        self.filmFraction = filmFraction
        self.episodesWatched = episodesWatched
        self.episodesStarted = episodesStarted
        self.lastSeason = lastSeason
        self.updatedAt = updatedAt
    }
}

/// An item of the account's «Досмотреть» list on the site (watched on the TV or the site counts too).
public struct AccountListItem: Codable, Sendable, Hashable {
    public var titleId: String
    public var watched: Bool
    /// The date the site shows for the last activity (seconds since 1970), when it parses.
    public var lastActivityAt: Double?
    /// Where the site says you are: season and episode numbers (series only).
    public var season: Int?
    public var episode: Int?
    /// «Ещё N серий» on the card.
    public var episodesLeft: Int?

    public init(
        titleId: String, watched: Bool, lastActivityAt: Double?, season: Int? = nil, episode: Int? = nil,
        episodesLeft: Int? = nil
    ) {
        self.titleId = titleId
        self.watched = watched
        self.lastActivityAt = lastActivityAt
        self.season = season
        self.episode = episode
        self.episodesLeft = episodesLeft
    }
}

/// A title in one of the account's bookmark folders.
public struct BookmarkItem: Codable, Sendable, Hashable {
    public var titleId: String
    public var folder: String

    public init(titleId: String, folder: String) {
        self.titleId = titleId
        self.folder = folder
    }
}

/// An explicit rating on the three-level scale (−2 «Не моё» … +2 «Обожаю»); imports and the local copy of a site
/// rating map onto it too.
public struct ExplicitRating: Codable, Sendable, Hashable {
    public enum Source: String, Codable, Sendable, Hashable {
        case app
        case site
        case onboarding
        case kinopoisk
        case imdb
        case letterboxd
        case trakt
        case shikimori
    }

    public var titleId: String
    /// −2, −1.5, −1, 0 («смотрел»), 1, 2.
    public var level: Double
    public var source: Source
    public var createdAt: Double

    public init(titleId: String, level: Double, source: Source, createdAt: Double) {
        self.titleId = titleId
        self.level = level
        self.source = source
        self.createdAt = createdAt
    }
}

/// The service actions on a title (see the plan's §2.4); each excludes or reshapes, some only for a while.
public enum FeedbackKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// «Скрыть»: never show, taste untouched.
    case hidden
    /// «Уже смотрел»: watched elsewhere, excluded.
    case seen
    /// «Не сегодня»: hidden until `until` (7 days).
    case notToday
    /// «Это смотрел не я»: the title's implicit signals are zeroed.
    case notMe
    /// «Не учитывать «X»»: not an anchor any more, still excluded.
    case notSeed
    /// «Убрать из ряда» on «Продолжить»: hidden from that row until new activity.
    case continueHidden
    /// «Бросил»: a weak minus.
    case dropped
}

public struct Feedback: Codable, Sendable, Hashable {
    public var titleId: String
    public var kind: FeedbackKind
    public var createdAt: Double
    /// When it stops applying (seconds since 1970), nil for ever.
    public var until: Double?

    public init(titleId: String, kind: FeedbackKind, createdAt: Double, until: Double? = nil) {
        self.titleId = titleId
        self.kind = kind
        self.createdAt = createdAt
        self.until = until
    }
}

/// A feature of taste: a genre, a country, a decade, a person, a kind, a board.
public struct FeatureKey: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public enum Group: String, Codable, Sendable, Hashable, CaseIterable {
        case genre
        case country
        case decade
        case director
        case actor
        case kind
        case duration
        case collection
        case list
    }

    public var group: Group
    public var value: String

    public init(_ group: Group, _ value: String) {
        self.group = group
        self.value = value
    }

    public var description: String { "\(group.rawValue):\(value)" }

    public static func < (lhs: FeatureKey, rhs: FeatureKey) -> Bool { lhs.description < rhs.description }
}

/// «Закрепить / Приглушить / Исключить» a feature by hand, or «Меньше/Больше такого» from «Почему это?».
public struct TasteOverride: Codable, Sendable, Hashable {
    public enum Mode: String, Codable, Sendable, Hashable {
        case pin
        case mute
        case exclude
        case more
    }

    public var feature: FeatureKey
    public var mode: Mode
    public var until: Double?

    public init(feature: FeatureKey, mode: Mode, until: Double? = nil) {
        self.feature = feature
        self.mode = mode
        self.until = until
    }
}

/// A title shown on a surface (for fatigue: shown again and again without being opened sinks).
public struct Impression: Codable, Sendable, Hashable {
    public var titleId: String
    public var surface: String
    public var shownAt: Double
    public var opened: Bool

    public init(titleId: String, surface: String, shownAt: Double, opened: Bool) {
        self.titleId = titleId
        self.surface = surface
        self.shownAt = shownAt
        self.opened = opened
    }
}

/// Everything the engine knows about the user. All of it lives only on this Mac.
public struct UserSignals: Codable, Sendable, Hashable {
    public var sessions: [WatchSession]
    public var progress: [LocalProgress]
    public var accountList: [AccountListItem]
    public var bookmarks: [BookmarkItem]
    /// Followed series (new episodes are announced for them).
    public var followed: [String]
    public var ratings: [ExplicitRating]
    public var feedback: [Feedback]
    public var overrides: [TasteOverride]
    public var impressions: [Impression]
    /// Whether the user is signed in (guests get no title pages, the pool is cards only).
    public var signedIn: Bool

    public init(
        sessions: [WatchSession] = [], progress: [LocalProgress] = [], accountList: [AccountListItem] = [],
        bookmarks: [BookmarkItem] = [], followed: [String] = [], ratings: [ExplicitRating] = [],
        feedback: [Feedback] = [], overrides: [TasteOverride] = [], impressions: [Impression] = [],
        signedIn: Bool = true
    ) {
        self.sessions = sessions
        self.progress = progress
        self.accountList = accountList
        self.bookmarks = bookmarks
        self.followed = followed
        self.ratings = ratings
        self.feedback = feedback
        self.overrides = overrides
        self.impressions = impressions
        self.signedIn = signedIn
    }
}
