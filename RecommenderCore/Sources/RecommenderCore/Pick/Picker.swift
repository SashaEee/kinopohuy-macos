import Foundation

/// Everything the picker needs from a prepared engine: the ranked candidates (best first, after the engine's filters),
/// the titles they refer to, the user's own pool («Своё»), title weights and recent impressions.
public struct PickContext: Sendable {
    public var ranked: [Recommendation]
    public var titles: [String: TitleFeatures]
    /// «Своё»: bookmarks without progress, «Можно начать», next parts and next episodes, best first.
    public var ownPool: [Recommendation]
    /// Far graph links and exploration candidates, best first.
    public var discoverPool: [Recommendation]
    public var titleWeights: [String: Double]
    public var impressions: [Impression]
    public var context: EngineContext
    public var settings: RecommenderSettings
    public var weights: Weights

    public init(
        ranked: [Recommendation], titles: [String: TitleFeatures], ownPool: [Recommendation],
        discoverPool: [Recommendation], titleWeights: [String: Double], impressions: [Impression],
        context: EngineContext, settings: RecommenderSettings, weights: Weights
    ) {
        self.ranked = ranked
        self.titles = titles
        self.ownPool = ownPool
        self.discoverPool = discoverPool
        self.titleWeights = titleWeights
        self.impressions = impressions
        self.context = context
        self.settings = settings
        self.weights = weights
    }
}

/// «Выбери за меня»: hard filters from the intent, a shortlist from the chosen pool, a seeded noisy argmax, two MMR
/// alternatives, relaxation when nothing matches, at most one clarifying question (the plan's §4.9).
public enum Picker {
    public static func pick(_ request: PickRequest, in context: PickContext) -> PickResult {
        PickResult(main: nil, alternatives: [], showGrid: false, relaxed: [], question: nil, suggestRefine: false, effectiveIntent: request.intent)
    }
}
