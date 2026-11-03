import Foundation

/// Everything computed once per input that the sources, the scorer, the page and the explanations read: titles in
/// the fixed order, signals, features, taste, the graph and its PageRank runs, quality, freshness and filters.
struct EngineCore: Sendable {
    let context: EngineContext
    let settings: RecommenderSettings
    let weights: Weights
    let seed: UInt64
    let impressions: [Impression]

    /// Titles in the fixed order (`TitleOrder`), duplicates merged.
    let titles: [TitleFeatures]
    let titleIndex: [String: Int]
    let signals: [String: TitleSignal]
    /// Signals in the fixed order (for sums that must not depend on dictionary order).
    let orderedSignals: [TitleSignal]
    let signalAt: [TitleSignal?]

    let table: FeatureTable
    let profile: TasteProfile
    let graph: TitleGraph
    let filters: CandidateFilters
    /// Why each title can't be recommended (nil: eligible). New seasons of watched series are let through.
    let filterReason: [FilterReason?]
    /// New seasons of watched or loved series (title → the user's last season, when known).
    let newSeasons: [Int: Int?]

    /// Bayesian rating on the 10-point scale (nil when unknown) and its (Q − 5)/4 normalisation.
    let qualityRating: [Double?]
    let quality: [Double]
    let freshness: [Double]

    /// PageRank from anchors+ for «Для вас» (α 0.3) and for discoveries (α 0.15), and closeness to anchors− (0…1).
    let rankForYou: [Double]
    let rankDiscover: [Double]
    let negProximity: [Double]
    /// Viewer neighbours by title index (S8), best first.
    let viewerNeighbours: [Int: [(title: Int, score: Double)]]
    /// Plot neighbours by title index (S9), best first.
    let plotNeighbours: [Int: [(title: Int, score: Double)]]

    var now: Double { context.now }
    var isGuestPool: Bool { !settings.useLocalHistory && !settings.useAccountList }

    func isEligible(_ title: Int) -> Bool { filterReason[title] == nil }

    func signal(_ title: Int) -> TitleSignal? { signalAt[title] }

    func weight(of title: Int) -> Double { signalAt[title]?.weight ?? 0 }

    static func build(_ input: EngineInput, timings: inout [String: Double]) -> EngineCore {
        let clock = ContinuousClock()
        var mark = clock.now
        func lap(_ name: String) {
            let elapsed = clock.now - mark
            timings[name, default: 0] += Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
            mark = clock.now
        }
        let weights = input.weights
        let titles = mergedTitles(input.titles)
        var titleIndex: [String: Int] = [:]
        titleIndex.reserveCapacity(titles.count)
        for (index, title) in titles.enumerated() { titleIndex[title.id] = index }
        let byId = Dictionary(titles.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        lap("titles")

        let signals = SignalWeighter.weigh(
            input.signals, titles: byId, settings: input.settings, weights: weights, context: input.context,
        )
        let orderedSignals = signals.keys.sorted(by: TitleOrder.precedes).compactMap { signals[$0] }
        var signalAt = [TitleSignal?](repeating: nil, count: titles.count)
        for signal in orderedSignals {
            if let index = titleIndex[signal.titleId] { signalAt[index] = signal }
        }
        lap("signals")

        let table = FeatureTable(titles: titles, weights: weights)
        let profile = ProfileBuilder.build(
            table: table, titles: titles, titleIndex: titleIndex, ordered: orderedSignals,
            overrides: input.signals.overrides, weights: weights, now: input.context.now,
        )
        lap("profile")

        let graph = TitleGraph(titles: titles, titleIndex: titleIndex, weights: weights)
        lap("graph")
        let seeds = profile.seeds.map { (node: $0.title, weight: $0.weight) }
        let rankForYou = PersonalizedPageRank.run(
            graph: graph, seeds: seeds, alpha: weights.pprAlphaForYou, iterations: weights.pprIterations,
        )
        let rankDiscover = PersonalizedPageRank.run(
            graph: graph, seeds: seeds, alpha: weights.pprAlphaDiscover, iterations: weights.pprIterations,
        )
        let negativeSeeds = profile.negativeAnchors.map { (node: $0.title, weight: -$0.weight) }
        let rankNegative = PersonalizedPageRank.run(
            graph: graph, seeds: negativeSeeds, alpha: weights.pprAlphaForYou, iterations: weights.pprIterations,
        )
        var negProximity = [Double](repeating: 0, count: titles.count)
        var negativeMax: Double = 0
        let negativeSeedSet = Set(profile.negativeAnchors.map(\.title))
        for index in 0..<titles.count where !negativeSeedSet.contains(index) {
            negativeMax = max(negativeMax, rankNegative[index])
        }
        if negativeMax > 0 {
            for index in 0..<titles.count {
                negProximity[index] = min(1, rankNegative[index] / negativeMax)
            }
        }
        lap("pagerank")

        var qualityRating = [Double?](repeating: nil, count: titles.count)
        var quality = [Double](repeating: 0, count: titles.count)
        var freshness = [Double](repeating: 0, count: titles.count)
        for (index, title) in titles.enumerated() {
            let rating = QualityPrior.rating(title, weights: weights)
            qualityRating[index] = rating
            quality[index] = QualityPrior.normalized(rating, weights: weights)
            freshness[index] = Freshness.value(title, now: input.context.now, weights: weights)
        }

        let filters = CandidateFilters(settings: input.settings, table: table, profile: profile)
        let newSeasons = ContinuationSource.newSeasons(
            titles: titles, signalAt: signalAt, now: input.context.now, weights: weights,
        )
        var filterReason = [FilterReason?](repeating: nil, count: titles.count)
        for (index, title) in titles.enumerated() {
            filterReason[index] = filters.reason(
                title: title, features: table.ofTitle[index], signal: signalAt[index],
                allowWatched: newSeasons[index] != nil,
            )
        }
        // A loved series' new season is news for a month: +1 freshness (§4.6).
        for (index, _) in newSeasons {
            guard let signal = signalAt[index], signal.weight >= 1 || signal.isLoved,
                  let released = titles[index].lastEpisodeAt,
                  EngineTime.days(from: released, to: input.context.now) <= weights.newSeasonFreshDays
            else { continue }
            freshness[index] += 1
        }
        lap("filters")

        func indexed(_ lists: [String: [ViewerNeighbour]]?) -> [Int: [(title: Int, score: Double)]] {
            var result: [Int: [(title: Int, score: Double)]] = [:]
            for (id, neighbours) in lists ?? [:] {
                guard let title = titleIndex[id] else { continue }
                let mapped = neighbours.compactMap { n in titleIndex[n.titleId].map { (title: $0, score: n.score) } }
                if !mapped.isEmpty { result[title] = mapped }
            }
            return result
        }
        let viewerNeighbours = indexed(input.viewerNeighbours)
        let plotNeighbours = indexed(input.plotNeighbours)

        return EngineCore(
            context: input.context, settings: input.settings, weights: weights, seed: input.seed,
            impressions: input.signals.impressions, titles: titles, titleIndex: titleIndex, signals: signals,
            orderedSignals: orderedSignals, signalAt: signalAt, table: table, profile: profile, graph: graph,
            filters: filters, filterReason: filterReason, newSeasons: newSeasons, qualityRating: qualityRating,
            quality: quality, freshness: freshness, rankForYou: rankForYou, rankDiscover: rankDiscover,
            negProximity: negProximity, viewerNeighbours: viewerNeighbours, plotNeighbours: plotNeighbours,
        )
    }

    /// One entry per id, in the fixed order. When the app sent a card and a page for the same title, the page wins
    /// (then the newer read), and the boards of both are kept: a card knows which list it came from.
    static func mergedTitles(_ titles: [TitleFeatures]) -> [TitleFeatures] {
        var merged: [String: TitleFeatures] = [:]
        for title in titles where !title.id.isEmpty {
            guard let existing = merged[title.id] else {
                merged[title.id] = title
                continue
            }
            let titleWins = (title.level == .page && existing.level == .card)
                || (title.level == existing.level && title.fetchedAt > existing.fetchedAt)
            var winner = titleWins ? title : existing
            let loser = titleWins ? existing : title
            let keys = Set(winner.boards.map(\.key))
            winner.boards += loser.boards.filter { !keys.contains($0.key) }
            merged[title.id] = winner
        }
        return merged.keys.sorted(by: TitleOrder.precedes).compactMap { merged[$0] }
    }
}

/// How new a title is (§4.6): exp(−age / 180 days) for titles younger than a year, 0 otherwise.
enum Freshness {
    static func value(_ title: TitleFeatures, now: Double, weights: Weights) -> Double {
        guard let age = ageDays(title, now: now), age >= 0, age < 365 else { return 0 }
        return exp(-age / max(1, weights.freshnessDays))
    }

    /// Days since release: the release date when known, else the middle of the release year.
    static func ageDays(_ title: TitleFeatures, now: Double) -> Double? {
        if let released = title.releasedAt { return EngineTime.days(from: released, to: now) }
        guard let year = title.year else { return nil }
        // 1 July of the year, as seconds since 1970 (365.2425-day years are precise enough for freshness).
        let midYear = (Double(year - 1970) + 0.5) * 365.2425 * EngineTime.day
        return max(0, EngineTime.days(from: midYear, to: now))
    }
}
