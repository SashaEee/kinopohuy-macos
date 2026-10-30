import Foundation

/// A prepared engine: holds the computed weights, profile, graph and scores for one input.
public final class PreparedEngine: Sendable {
    public let input: EngineInput
    public let output: EngineOutput

    init(input: EngineInput) {
        self.input = input
        // Placeholder until the pipeline lands: no recommendations, cold start.
        self.output = EngineOutput(
            page: PageLayout(hero: nil, rows: []), ranked: [], profile: .empty, titleWeights: [:], isColdStart: true,
        )
    }

    /// «Выбери за меня»: one pick and two alternatives for the request.
    public func pick(_ request: PickRequest) -> PickResult {
        PickResult(main: nil, alternatives: [], showGrid: false, relaxed: [], question: nil, suggestRefine: false, effectiveIntent: request.intent)
    }

    /// «Почему это?» for a title (nil when it isn't a candidate).
    public func explain(_ titleId: String) -> Explanation? { nil }

    /// «Вам подойдёт?» for any title in the pool.
    public func fit(_ titleId: String) -> FitVerdict? { nil }

    /// The onboarding's stack: up to `count` of the user's own titles worth rating (half uncertain, half confident).
    public func onboardingStack(count: Int = 12) -> [String] { [] }
}
