import Foundation

/// What a run looked like inside: each source's own ranking, filter counts and stage timings (RecEval, the debug view).
public struct EngineDiagnostics: Sendable {
    /// Each source's candidates after filters (title ids, best first).
    public var sources: [SourceKind: [String]]
    /// Far graph links (the «Открытия» pool), best first.
    public var farGraph: [String]
    /// How many pool titles each filter removed.
    public var filtered: [String: Int]
    /// Milliseconds per stage.
    public var timings: [String: Double]
    public var poolSize: Int
    /// Titles any source produced (before franchise collapse).
    public var candidateCount: Int
}

/// A prepared engine: holds the computed weights, profile, graph and scores for one input.
public final class PreparedEngine: Sendable {
    public let input: EngineInput
    public let output: EngineOutput
    public let diagnostics: EngineDiagnostics

    let core: EngineCore
    let similarity: TitleSimilarity
    /// Every scored title by index (franchise representatives carry their franchise's score).
    let scored: [Int: ScoredTitle]
    /// Reasons fixed outside the score (a next episode in «Своё»).
    let fixedReasons: [Int: Reason]
    let pickContext: PickContext
    let fitScores: [Double]
    let sortedFitScores: [Double]

    init(input: EngineInput) {
        self.input = input
        let clock = ContinuousClock()
        let started = clock.now
        var timings: [String: Double] = [:]
        var mark = clock.now
        func lap(_ name: String) {
            timings[name, default: 0] += Self.milliseconds(clock.now - mark)
            mark = clock.now
        }

        let core = EngineCore.build(input, timings: &timings)
        mark = clock.now
        let weights = core.weights

        // Sources → fusion → scores → one title per franchise.
        let rankingList = CandidateSources.all(core)
        var rankings: [SourceKind: SourceRanking] = [:]
        for ranking in rankingList { rankings[ranking.kind] = ranking }
        let farHits = GraphSource.farHits(core)
        lap("sources")
        let allScored = Scorer.score(rankingList, core: core)
        let nextParts = Set(
            (rankings[.continuation]?.hits ?? []).filter { $0.evidence.board?.kind == .franchise }.map(\.title),
        )
        let ranked = FranchiseCollapse.collapse(allScored, core: core, nextParts: nextParts)
        lap("score")

        let isColdStart = core.profile.positiveCount < weights.coldStartPositives
        let similarity = TitleSimilarity(core: core)
        let page = HomeAssembler(
            core: core, ranked: ranked, rankings: rankings, farHits: farHits, similarity: similarity,
            isColdStart: isColdStart,
        ).assemble()
        lap("page")

        var scored: [Int: ScoredTitle] = [:]
        for item in allScored { scored[item.title] = item }
        for item in ranked { scored[item.title] = item }

        func recommendation(_ item: ScoredTitle, options: ReasonOptions = ReasonOptions()) -> Recommendation {
            Recommendation(
                titleId: core.titles[item.title].id, score: item.score, contributions: item.contributions,
                reason: ReasonBuilder.reason(for: item, core: core, options: options),
                tags: ReasonBuilder.tags(for: item.title, core: core),
            )
        }
        let rankedRecommendations = ranked.map { recommendation($0) }
        let inRanked = Set(ranked.map(\.title))

        // «Своё»: next parts, new seasons, bookmarks and «Можно начать», and the next episode of what's in progress.
        var own: [(item: ScoredTitle, recommendation: Recommendation)] = []
        var ownTitles = Set<Int>()
        let ownOptions = ReasonOptions(preferredKinds: [.nextPart, .newSeason, .bookmark, .canStart])
        for kind in [SourceKind.continuation, .intent] {
            for hit in rankings[kind]?.hits ?? [] where inRanked.contains(hit.title) && !ownTitles.contains(hit.title) {
                guard let item = scored[hit.title] else { continue }
                own.append((item, recommendation(item, options: ownOptions)))
                ownTitles.insert(hit.title)
            }
        }
        var fixedReasons: [Int: Reason] = [:]
        let extraShows = Fatigue.extraShows(core.impressions, now: core.now, weights: weights)
        for (index, title) in core.titles.enumerated() where title.isSeries && !ownTitles.contains(index) {
            guard let signal = core.signal(index), signal.state == .started, !signal.continueHidden, signal.weight >= 0,
                  let resume = signal.resume,
                  core.filters.settingsReason(title: title, features: core.table.ofTitle[index], signal: signal) == nil,
                  let last = signal.lastActivity, EngineTime.days(from: last, to: core.now) <= 30
            else { continue }
            let item = Scorer.make(title: index, fused: 0, contributions: [], core: core, extraShows: extraShows[title.id] ?? 0)
            let reason = ReasonBuilder.nextEpisodeReason(resume, titleId: title.id)
            fixedReasons[index] = reason
            scored[index] = item
            own.append((item, Recommendation(
                titleId: title.id, score: item.score, contributions: [], reason: reason,
                tags: ReasonBuilder.tags(for: index, core: core),
            )))
            ownTitles.insert(index)
        }
        own.sort { $0.item.score != $1.item.score ? $0.item.score > $1.item.score : $0.item.title < $1.item.title }

        // «Открытия»: far graph links and exploration.
        var discoverTitles = Set<Int>()
        for hit in farHits where inRanked.contains(hit.title) { discoverTitles.insert(hit.title) }
        for hit in rankings[.exploration]?.hits ?? [] where inRanked.contains(hit.title) { discoverTitles.insert(hit.title) }
        let discover = discoverTitles.compactMap { scored[$0] }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
            .map { recommendation($0, options: ReasonOptions(preferredKinds: [.discovery])) }

        var titleWeights: [String: Double] = [:]
        for signal in core.orderedSignals { titleWeights[signal.titleId] = signal.weight }
        lap("reasons")

        var byId: [String: TitleFeatures] = [:]
        byId.reserveCapacity(core.titles.count)
        for title in core.titles { byId[title.id] = title }
        pickContext = PickContext(
            ranked: rankedRecommendations, titles: byId, ownPool: own.map(\.recommendation), discoverPool: discover,
            titleWeights: titleWeights, impressions: input.signals.impressions, context: input.context,
            settings: input.settings, weights: weights,
        )
        fitScores = TitleExplainer.fitScores(core: core)
        sortedFitScores = fitScores.sorted()
        lap("pick")

        output = EngineOutput(
            page: page, ranked: rankedRecommendations, profile: core.profile.summary, titleWeights: titleWeights,
            isColdStart: isColdStart,
        )
        var filtered: [String: Int] = [:]
        for reason in core.filterReason.compactMap(\.self) { filtered[reason.rawValue, default: 0] += 1 }
        timings["total"] = Self.milliseconds(clock.now - started)
        diagnostics = EngineDiagnostics(
            sources: rankings.mapValues { $0.hits.map { core.titles[$0.title].id } },
            farGraph: farHits.map { core.titles[$0.title].id }, filtered: filtered, timings: timings,
            poolSize: core.titles.count, candidateCount: allScored.count,
        )
        self.core = core
        self.similarity = similarity
        self.scored = scored
        self.fixedReasons = fixedReasons
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// «Выбери за меня»: one pick and two alternatives for the request.
    public func pick(_ request: PickRequest) -> PickResult {
        Picker.pick(request, in: pickContext)
    }

    /// What «Выбери за меня» picks from (the ranked candidates, «Своё», «Открытия»).
    public var pickPools: PickContext { pickContext }

    /// «Почему это?» for a title (nil when it isn't a candidate).
    public func explain(_ titleId: String) -> Explanation? {
        guard let index = core.titleIndex[titleId], let item = scored[index] else { return nil }
        let reason = fixedReasons[index] ?? ReasonBuilder.reason(for: item, core: core)
        return TitleExplainer.explanation(for: item, reason: reason, core: core)
    }

    /// «Вам подойдёт?» for any title in the pool.
    public func fit(_ titleId: String) -> FitVerdict? {
        guard let index = core.titleIndex[titleId] else { return nil }
        return TitleExplainer.verdict(for: index, fitScores: fitScores, sortedFit: sortedFitScores, core: core)
    }

    /// The onboarding's stack: up to `count` of the user's own titles worth rating (half uncertain, half confident).
    public func onboardingStack(count: Int = 12) -> [String] {
        OnboardingStack.titles(core: core, similarity: similarity, count: count)
    }

    /// Why a pool title isn't recommended («seen», «excludedGenre»…), nil when it may be (the debug view).
    public func filterReason(_ titleId: String) -> String? {
        guard let index = core.titleIndex[titleId] else { return nil }
        return core.filterReason[index]?.rawValue
    }
}
