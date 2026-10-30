import Foundation

/// Every coefficient of the engine in one place (the plan's §4.2–§4.8). `Weights.default` holds the plan's values;
/// `Resources/weights.json` mirrors them so they can be tuned without touching code.
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
    public var rewatch: Double = 0.5
    public var bookmarkIntent: Double = 0.3
    public var bookmarkTasteFactor: Double = 0.5
    public var bookmarkLovedFolder: Double = 0.8
    public var followed: Double = 0.3
    public var dropped: Double = -0.4

    public var longMemoryShare: Double = 0.7
    public var longHalfLifeDays: Double = 180
    public var shortHalfLifeDays: Double = 14

    // §4.3 Profile
    public var affinitySmoothing: Double = 2
    public var groupWeights: [String: Double] = [
        "genre": 1.0, "country": 0.7, "decade": 0.4, "director": 1.2, "actor": 0.5, "kind": 0.8,
        "duration": 0.3, "collection": 0.6, "list": 0.6,
    ]
    public var anchorMinWeight: Double = 0.3
    public var anchorCount: Int = 40
    public var negativeAnchorMaxWeight: Double = -0.3
    public var personDislikeFloor: Double = -0.2

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
    public var criticsShare: Double = 0.2
    public var freshnessDays: Double = 180
    public var scoreAffinity: Double = 0.25
    public var scoreQuality: Double = 0.15
    public var scoreFresh: Double = 0.05
    public var scoreMultiSource: Double = 0.05
    public var scoreNegProximity: Double = 0.3

    // §4.7 Re-ranking
    public var fatigueFactor: Double = 0.85
    public var fatigueFreeShows: Int = 2
    public var fatigueWindowDays: Double = 14
    public var notTodayDays: Double = 7
    public var mmrLambda: Double = 0.7
    public var genreCapMin: Double = 0.4
    public var genreCapSlack: Double = 0.1
    public var perAnchorCap: Int = 2

    // §4.8 Home
    public var rowMinItems: Int = 8
    public var rowMaxItems: Int = 20
    public var maxPersonalRows: Int = 8
    public var maxRowsPerKind: Int = 2
    public var coldStartPositives: Int = 5

    public init() {}

    public static let `default` = Weights()

    public func group(_ group: FeatureKey.Group) -> Double { groupWeights[group.rawValue] ?? 0.5 }
    public func prior(_ source: SourceKind) -> Double { sourcePriors[source.rawValue] ?? 0.5 }
}
