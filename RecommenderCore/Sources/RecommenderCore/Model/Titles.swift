import Foundation

/// What a title is, as the site groups them.
public enum TitleKind: String, Codable, Sendable, Hashable, CaseIterable {
    case film
    case series
    case cartoon
    case anime
    case show
}

/// How much the app knows about a title: only its card from a list, or its whole page.
public enum TitleLevel: String, Codable, Sendable, Hashable {
    case card
    case page
}

/// A person on the site (director, actor), by the site's own id.
public struct PersonRef: Codable, Sendable, Hashable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// What groups titles on the site, so two titles can be related through it ("boards", as in Pinterest's Pixie).
public enum BoardKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// A ranked list («Лучшие криминальные сериалы 2023 года»).
    case list
    /// A collection («Подборки»).
    case collection
    /// A franchise (parts of one story).
    case franchise
    case director
    case actor
}

/// A title's membership in a board: the list, collection or franchise, and its place there when ranked.
public struct BoardRef: Codable, Sendable, Hashable {
    /// The board's own id on the site (for a person: the person's id).
    public var id: String
    public var kind: BoardKind
    public var name: String
    /// 1-based place in a ranked list or franchise.
    public var rank: Int?
    /// How many titles the board holds, when known.
    public var size: Int?

    public init(id: String, kind: BoardKind, name: String, rank: Int? = nil, size: Int? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.rank = rank
        self.size = size
    }

    /// A key unique across kinds ("list:123").
    public var key: String { "\(kind.rawValue):\(id)" }
}

/// One part of a franchise as the title's page lists it.
public struct FranchisePart: Codable, Sendable, Hashable {
    /// The part's title id when the page links to it (the current part and unreleased ones may not).
    public var titleId: String?
    public var name: String
    public var year: Int?
    /// 1-based order in the franchise.
    public var position: Int
    public var isCurrent: Bool

    public init(titleId: String?, name: String, year: Int?, position: Int, isCurrent: Bool) {
        self.titleId = titleId
        self.name = name
        self.year = year
        self.position = position
        self.isCurrent = isCurrent
    }
}

/// Everything the engine knows about one title on the site. Built by the app from title pages it has seen and from
/// list cards (then most fields are empty). The id is the site's number (from the page path); the path itself never
/// leaves the Mac.
public struct TitleFeatures: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// The site path, so the app can open it.
    public var path: String
    public var level: TitleLevel
    public var kind: TitleKind?
    public var name: String
    public var originalName: String?
    public var year: Int?
    /// Genre names as the site shows them («Драмы», «Комедии»); the card level has at most the primary one.
    public var genres: [String]
    public var countries: [String]
    /// Film length or a typical episode, in minutes.
    public var durationMin: Int?
    /// Age rating (0, 6, 12, 16, 18).
    public var age: Int?
    public var directors: [PersonRef]
    /// Top-billed actors, in billing order (at most 5 are used).
    public var actors: [PersonRef]

    public var kpId: Int?
    public var imdbId: String?

    public var kpRating: Double?
    public var kpVotes: Int?
    public var imdbRating: Double?
    public var imdbVotes: Int?
    /// The site's own rating (1–10) and votes.
    public var siteRating: Double?
    public var siteVotes: Int?
    /// Critics, from the open data pack (later stages).
    public var rtCritic: Int?
    public var metacritic: Int?

    /// Ranked lists and collections the title is in.
    public var boards: [BoardRef]
    /// The franchise id and its parts, when the page lists them.
    public var franchiseId: String?
    public var franchise: [FranchisePart]
    /// «Смотрите также» on its page: ids of related titles, in the site's order.
    public var watchAlso: [String]

    public var isSeries: Bool
    /// Released episodes in total (from the schedule or «ещё N серий»), when known.
    public var releasedEpisodes: Int?
    /// Seasons released, when known.
    public var seasons: Int?
    /// When the latest episode came out (seconds since 1970), for «вышел новый сезон».
    public var lastEpisodeAt: Double?
    /// The release date (seconds since 1970), for freshness.
    public var releasedAt: Double?
    public var comingSoon: Bool
    public var available: Bool
    /// Names of the voice-overs on the page.
    public var voiceOvers: [String]

    public var poster: String?
    /// The site's description (never leaves the Mac; used by the explain and later the embedding stages).
    public var synopsis: String?
    /// When the page (or card) was read, seconds since 1970.
    public var fetchedAt: Double

    public init(
        id: String, path: String, level: TitleLevel, kind: TitleKind?, name: String, originalName: String? = nil,
        year: Int? = nil, genres: [String] = [], countries: [String] = [], durationMin: Int? = nil, age: Int? = nil,
        directors: [PersonRef] = [], actors: [PersonRef] = [], kpId: Int? = nil, imdbId: String? = nil,
        kpRating: Double? = nil, kpVotes: Int? = nil, imdbRating: Double? = nil, imdbVotes: Int? = nil,
        siteRating: Double? = nil, siteVotes: Int? = nil, rtCritic: Int? = nil, metacritic: Int? = nil,
        boards: [BoardRef] = [], franchiseId: String? = nil, franchise: [FranchisePart] = [], watchAlso: [String] = [],
        isSeries: Bool = false, releasedEpisodes: Int? = nil, seasons: Int? = nil, lastEpisodeAt: Double? = nil,
        releasedAt: Double? = nil, comingSoon: Bool = false, available: Bool = true, voiceOvers: [String] = [],
        poster: String? = nil, synopsis: String? = nil, fetchedAt: Double
    ) {
        self.id = id
        self.path = path
        self.level = level
        self.kind = kind
        self.name = name
        self.originalName = originalName
        self.year = year
        self.genres = genres
        self.countries = countries
        self.durationMin = durationMin
        self.age = age
        self.directors = directors
        self.actors = actors
        self.kpId = kpId
        self.imdbId = imdbId
        self.kpRating = kpRating
        self.kpVotes = kpVotes
        self.imdbRating = imdbRating
        self.imdbVotes = imdbVotes
        self.siteRating = siteRating
        self.siteVotes = siteVotes
        self.rtCritic = rtCritic
        self.metacritic = metacritic
        self.boards = boards
        self.franchiseId = franchiseId
        self.franchise = franchise
        self.watchAlso = watchAlso
        self.isSeries = isSeries
        self.releasedEpisodes = releasedEpisodes
        self.seasons = seasons
        self.lastEpisodeAt = lastEpisodeAt
        self.releasedAt = releasedAt
        self.comingSoon = comingSoon
        self.available = available
        self.voiceOvers = voiceOvers
        self.poster = poster
        self.synopsis = synopsis
        self.fetchedAt = fetchedAt
    }
}
