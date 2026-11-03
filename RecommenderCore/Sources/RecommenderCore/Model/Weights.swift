import Foundation

/// Every coefficient of the engine in one place (the plan's §4.2–§4.8). `Weights.default` holds the plan's values;
/// `Resources/weights.json` mirrors them so they can be tuned without touching code. Decoding is lenient: a key that
/// is missing keeps its default, so an old or partial weights file never breaks the engine.
public struct Weights: Codable, Sendable, Hashable {
    // §4.2 Signals → title weights
    public var lovedLevel: Double = 2
    public var likedLevel: Double = 1
    public var dislikedLevel: Double = -2
    public var explicitHalfLifeDays: Double = 730

    public var filmCompleted: Double = 0.8
    public var filmMostly: Double = 0.3
    public var filmMostlyTwoSessions: Double = 0.5
    public var filmAbandoned: Double = -0.4
    public var seriesBase: Double = 0.5
    public var seriesProgressBonus: Double = 0.5
    public var seriesNextSeason: Double = 0.3
    public var seriesBinge: Double = 0.2
    public var seriesAbandoned: Double = -0.4
    public var listWatched: Double = 0.6
    public var listRecent: Double = 0.4
    public var listStale: Double = -0.2
    /// Played from «Досмотреть» (a film, or a series a few episodes in) with nothing on this Mac to say how far.
    public var listStarted: Double = 0.45
    public var rewatch: Double = 0.5
    public var bookmarkIntent: Double = 0.3
    public var bookmarkTasteFactor: Double = 0.5
    public var bookmarkLovedFolder: Double = 0.8
    public var followed: Double = 0.3
    public var dropped: Double = -0.4

    public var longMemoryShare: Double = 0.7
    public var longHalfLifeDays: Double = 180
    public var shortHalfLifeDays: Double = 14
    /// Onboarding group picks (a +0.6 pseudo-rating per title of a chosen group) fade with this half-life (§2.1).
    public var onboardingGroupHalfLifeDays: Double = 30
    /// A signal the site gave no date for counts as this old.
    public var undatedAgeDays: Double = 180
    /// A typical season, for series whose released episode count is unknown.
    public var typicalSeasonEpisodes: Double = 8

    // §4.3 Profile
    public var affinitySmoothing: Double = 2
    /// A liked genre, country, person, collection or list needs A(f) above this to make a title «in taste».
    public var tasteMatchMinAffinity: Double = 0.1
    public var groupWeights: [String: Double] = [
        "genre": 1.0, "country": 0.7, "decade": 0.4, "director": 1.2, "actor": 0.5, "kind": 0.8,
        "duration": 0.3, "collection": 0.6, "list": 0.6,
    ]
    public var anchorMinWeight: Double = 0.3
    public var anchorCount: Int = 40
    public var negativeAnchorMaxWeight: Double = -0.3
    public var personDislikeFloor: Double = -0.2
    /// Below this many anchors the graph is seeded from every positive title (old taste still counts).
    public var minSeedAnchors: Int = 5
    /// «Приглушить» and «Больше такого» pull a feature's affinity to at most / at least these.
    public var muteAffinity: Double = -0.5
    public var pinAffinity: Double = 0.7
    public var moreAffinity: Double = 0.5

    // §4.5 S1: the graph
    public var edgeWatchAlso: Double = 1.0
    public var edgeWatchAlsoReverse: Double = 0.5
    public var edgeFranchise: Double = 1.0
    public var edgeList: Double = 0.8
    public var edgeCollection: Double = 0.6
    public var edgeDirector: Double = 0.5
    public var edgeActor: Double = 0.25
    public var pprAlphaForYou: Double = 0.3
    public var pprAlphaFamiliar: Double = 0.5
    public var pprAlphaDiscover: Double = 0.15
    public var pprIterations: Int = 20
    public var extraAnchorBonus: Double = 0.05
    /// At most this many extra anchors earn the bonus (a hub linked to every anchor shouldn't win on links alone).
    public var extraAnchorBonusCap: Int = 6
    /// How many graph candidates are kept (by PageRank) before their evidence is looked up.
    public var graphCandidateLimit: Int = 300

    // §4.5 Other sources
    public var peopleMinWeight: Double = 1.5
    public var peopleMinTitles: Int = 2
    public var peopleMaxPersons: Int = 10
    public var newReleaseDays: Double = 365
    /// A new season counts as news for this long.
    public var newSeasonWindowDays: Double = 120
    public var explorationMinQuality: Double = 0.6
    public var explorationMaxAffinity: Double = 0.1

    // §4.6 Fusion
    public var rrfK: Double = 60
    public var sourcePriors: [String: Double] = [
        "graph": 1.0, "continuation": 1.0, "intent": 0.8, "affinity": 0.7, "people": 0.6, "qualityFresh": 0.5,
        "exploration": 0.3,
    ]
    public var kpPriorVotes: Double = 3000
    public var kpPriorMean: Double = 6.6
    public var imdbPriorVotes: Double = 8000
    public var imdbPriorMean: Double = 6.5
    /// The site's own rating, the last fallback.
    public var sitePriorVotes: Double = 200
    public var sitePriorMean: Double = 6.5
    /// A rating whose votes are unknown (list cards show only the badge) counts as this share of the prior's votes.
    public var unknownVotesShare: Double = 0.5
    public var criticsShare: Double = 0.2
    public var freshnessDays: Double = 180
    /// A new season of a loved series earns +1 freshness for this long.
    public var newSeasonFreshDays: Double = 30
    public var scoreAffinity: Double = 0.25
    public var scoreQuality: Double = 0.15
    public var scoreFresh: Double = 0.05
    public var scoreMultiSource: Double = 0.05
    public var scoreNegProximity: Double = 0.3
    /// A title without the preferred voice-over sinks by this much (when its voice-overs are known).
    public var voiceOverPenalty: Double = 0.1

    // §4.7 Re-ranking
    public var fatigueFactor: Double = 0.85
    public var fatigueFreeShows: Int = 2
    public var fatigueWindowDays: Double = 14
    public var notTodayDays: Double = 7
    public var mmrLambda: Double = 0.7
    /// MMR looks at this many best candidates per row.
    public var mmrWindow: Int = 200
    public var genreCapMin: Double = 0.4
    public var genreCapSlack: Double = 0.1
    public var perAnchorCap: Int = 2

    // §4.8 Home
    public var rowMinItems: Int = 8
    public var rowMaxItems: Int = 20
    public var maxPersonalRows: Int = 8
    public var maxRowsPerKind: Int = 2
    public var coldStartPositives: Int = 5
    /// «Следующая часть / Вышел новый сезон» shows from this many titles (§2.2).
    public var continuationRowMinItems: Int = 3
    /// «Потому что вы досмотрели «X»» is tried for this many top anchors.
    public var anchorRowCandidates: Int = 5
    /// Row type priors and the penalty for a second row of the same type.
    public var rowPriors: [String: Double] = [
        "forYou": 1.0, "becauseWatched": 0.9, "becauseLoved": 0.95, "continuation": 1.2, "person": 0.85,
        "collections": 0.75, "discover": 0.7, "canStart": 0.8,
    ]
    public var rowRepeatPenalty: Double = 0.8
    /// Day-to-day rotation of the anchor rows (a seeded ±share of their score).
    public var rowRotation: Double = 0.15
    public var heroWeekdayMaxMinutes: Int = 110
    public var heroEpisodeMinMinutes: Int = 20
    public var heroEpisodeMaxMinutes: Int = 45
    public var miniSeriesMaxEpisodes: Int = 10

    // §2.5 Explanations
    /// «Вы досмотрели «X»» only when X weighs at least this much.
    public var reasonAnchorMinWeight: Double = 0.5
    /// Contributions this close to the top one (share of it) let the template priority decide.
    public var reasonTieShare: Double = 0.1
    /// «Вам подойдёт?»: score percentiles for «Скорее да» and «Скорее нет».
    public var fitLikelyPercentile: Double = 0.7
    public var fitUnlikelyPercentile: Double = 0.35

    public init() {}

    public static let `default` = Weights()

    public func group(_ group: FeatureKey.Group) -> Double { groupWeights[group.rawValue] ?? 0.5 }
    public func prior(_ source: SourceKind) -> Double { sourcePriors[source.rawValue] ?? 0.5 }
    public func rowPrior(_ kind: RecRow.Kind) -> Double { rowPriors[kind.rawValue] ?? 0.8 }

    /// The weights shipped with the package (`Resources/weights.json`), or the defaults if the file can't be read.
    public static var bundled: Weights {
        guard let url = Bundle.module.url(forResource: "weights", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let weights = try? JSONDecoder().decode(Weights.self, from: data)
        else { return .default }
        return weights
    }

    // swiftlint:disable:next function_body_length
    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d(_ key: CodingKeys, _ value: inout Double) throws {
            if let v = try c.decodeIfPresent(Double.self, forKey: key) { value = v }
        }
        func i(_ key: CodingKeys, _ value: inout Int) throws {
            if let v = try c.decodeIfPresent(Int.self, forKey: key) { value = v }
        }
        func m(_ key: CodingKeys, _ value: inout [String: Double]) throws {
            // A partial map overrides only the keys it names.
            if let v = try c.decodeIfPresent([String: Double].self, forKey: key) { value.merge(v) { _, new in new } }
        }
        try d(.lovedLevel, &lovedLevel)
        try d(.likedLevel, &likedLevel)
        try d(.dislikedLevel, &dislikedLevel)
        try d(.explicitHalfLifeDays, &explicitHalfLifeDays)
        try d(.filmCompleted, &filmCompleted)
        try d(.filmMostly, &filmMostly)
        try d(.filmMostlyTwoSessions, &filmMostlyTwoSessions)
        try d(.filmAbandoned, &filmAbandoned)
        try d(.seriesBase, &seriesBase)
        try d(.seriesProgressBonus, &seriesProgressBonus)
        try d(.seriesNextSeason, &seriesNextSeason)
        try d(.seriesBinge, &seriesBinge)
        try d(.seriesAbandoned, &seriesAbandoned)
        try d(.listWatched, &listWatched)
        try d(.listRecent, &listRecent)
        try d(.listStale, &listStale)
        try d(.listStarted, &listStarted)
        try d(.rewatch, &rewatch)
        try d(.bookmarkIntent, &bookmarkIntent)
        try d(.bookmarkTasteFactor, &bookmarkTasteFactor)
        try d(.bookmarkLovedFolder, &bookmarkLovedFolder)
        try d(.followed, &followed)
        try d(.dropped, &dropped)
        try d(.longMemoryShare, &longMemoryShare)
        try d(.longHalfLifeDays, &longHalfLifeDays)
        try d(.shortHalfLifeDays, &shortHalfLifeDays)
        try d(.onboardingGroupHalfLifeDays, &onboardingGroupHalfLifeDays)
        try d(.undatedAgeDays, &undatedAgeDays)
        try d(.typicalSeasonEpisodes, &typicalSeasonEpisodes)
        try d(.affinitySmoothing, &affinitySmoothing)
        try d(.tasteMatchMinAffinity, &tasteMatchMinAffinity)
        try m(.groupWeights, &groupWeights)
        try d(.anchorMinWeight, &anchorMinWeight)
        try i(.anchorCount, &anchorCount)
        try d(.negativeAnchorMaxWeight, &negativeAnchorMaxWeight)
        try d(.personDislikeFloor, &personDislikeFloor)
        try i(.minSeedAnchors, &minSeedAnchors)
        try d(.muteAffinity, &muteAffinity)
        try d(.pinAffinity, &pinAffinity)
        try d(.moreAffinity, &moreAffinity)
        try d(.edgeWatchAlso, &edgeWatchAlso)
        try d(.edgeWatchAlsoReverse, &edgeWatchAlsoReverse)
        try d(.edgeFranchise, &edgeFranchise)
        try d(.edgeList, &edgeList)
        try d(.edgeCollection, &edgeCollection)
        try d(.edgeDirector, &edgeDirector)
        try d(.edgeActor, &edgeActor)
        try d(.pprAlphaForYou, &pprAlphaForYou)
        try d(.pprAlphaFamiliar, &pprAlphaFamiliar)
        try d(.pprAlphaDiscover, &pprAlphaDiscover)
        try i(.pprIterations, &pprIterations)
        try d(.extraAnchorBonus, &extraAnchorBonus)
        try i(.extraAnchorBonusCap, &extraAnchorBonusCap)
        try i(.graphCandidateLimit, &graphCandidateLimit)
        try d(.peopleMinWeight, &peopleMinWeight)
        try i(.peopleMinTitles, &peopleMinTitles)
        try i(.peopleMaxPersons, &peopleMaxPersons)
        try d(.newReleaseDays, &newReleaseDays)
        try d(.newSeasonWindowDays, &newSeasonWindowDays)
        try d(.explorationMinQuality, &explorationMinQuality)
        try d(.explorationMaxAffinity, &explorationMaxAffinity)
        try d(.rrfK, &rrfK)
        try m(.sourcePriors, &sourcePriors)
        try d(.kpPriorVotes, &kpPriorVotes)
        try d(.kpPriorMean, &kpPriorMean)
        try d(.imdbPriorVotes, &imdbPriorVotes)
        try d(.imdbPriorMean, &imdbPriorMean)
        try d(.sitePriorVotes, &sitePriorVotes)
        try d(.sitePriorMean, &sitePriorMean)
        try d(.unknownVotesShare, &unknownVotesShare)
        try d(.criticsShare, &criticsShare)
        try d(.freshnessDays, &freshnessDays)
        try d(.newSeasonFreshDays, &newSeasonFreshDays)
        try d(.scoreAffinity, &scoreAffinity)
        try d(.scoreQuality, &scoreQuality)
        try d(.scoreFresh, &scoreFresh)
        try d(.scoreMultiSource, &scoreMultiSource)
        try d(.scoreNegProximity, &scoreNegProximity)
        try d(.voiceOverPenalty, &voiceOverPenalty)
        try d(.fatigueFactor, &fatigueFactor)
        try i(.fatigueFreeShows, &fatigueFreeShows)
        try d(.fatigueWindowDays, &fatigueWindowDays)
        try d(.notTodayDays, &notTodayDays)
        try d(.mmrLambda, &mmrLambda)
        try i(.mmrWindow, &mmrWindow)
        try d(.genreCapMin, &genreCapMin)
        try d(.genreCapSlack, &genreCapSlack)
        try i(.perAnchorCap, &perAnchorCap)
        try i(.rowMinItems, &rowMinItems)
        try i(.rowMaxItems, &rowMaxItems)
        try i(.maxPersonalRows, &maxPersonalRows)
        try i(.maxRowsPerKind, &maxRowsPerKind)
        try i(.coldStartPositives, &coldStartPositives)
        try i(.continuationRowMinItems, &continuationRowMinItems)
        try i(.anchorRowCandidates, &anchorRowCandidates)
        try m(.rowPriors, &rowPriors)
        try d(.rowRepeatPenalty, &rowRepeatPenalty)
        try d(.rowRotation, &rowRotation)
        try i(.heroWeekdayMaxMinutes, &heroWeekdayMaxMinutes)
        try i(.heroEpisodeMinMinutes, &heroEpisodeMinMinutes)
        try i(.heroEpisodeMaxMinutes, &heroEpisodeMaxMinutes)
        try i(.miniSeriesMaxEpisodes, &miniSeriesMaxEpisodes)
        try d(.reasonAnchorMinWeight, &reasonAnchorMinWeight)
        try d(.reasonTieShare, &reasonTieShare)
        try d(.fitLikelyPercentile, &fitLikelyPercentile)
        try d(.fitUnlikelyPercentile, &fitUnlikelyPercentile)
    }
}
