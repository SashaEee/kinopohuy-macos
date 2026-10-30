import Foundation

/// One line of the offline report.
public struct EvalRow: Sendable, Hashable {
    public var name: String
    public var recall: Double
    public var ndcg: Double
    public var coverage: Double
    public var novelty: Double
    public var diversity: Double
    public var listSize: Int
}

/// The offline report: the blend, the page, each source alone and two baselines on the same holdout.
public struct EvalReport: Sendable {
    public var rows: [EvalRow]
    public var heldOut: [String]
    public var poolSize: Int
    public var recallK: Int
    public var ndcgK: Int
    /// The engine's own stage timings on the training input (milliseconds).
    public var timings: [String: Double]

    public func row(_ name: String) -> EvalRow? { rows.first { $0.name == name } }
}

/// Runs the holdout test (§8.3) and compares the blend with each source and with the baselines: the site's
/// popularity, and «Смотрите также» of the last finished title (how «Похоже на…» works today).
public enum Evaluator {
    public static let blend = "Смесь"
    public static let page = "Главная"
    public static let popularity = "Популярное"
    public static let watchAlso = "«Смотрите также» последнего"

    public static func evaluate(_ input: EngineInput, holdout: Int = 30, recallK: Int = 20, ndcgK: Int = 10) -> EvalReport {
        let split = Holdout.split(input, count: holdout)
        let engine = Recommender.prepare(split.train)
        let core = engine.core
        let relevant = Set(split.heldOut)

        var votes: [String: Double] = [:]
        for title in core.titles {
            votes[title.id] = Double(QualityFreshSource.popularity(title) ?? 0)
        }
        func similarity(_ lhs: String, _ rhs: String) -> Double {
            guard let l = core.titleIndex[lhs], let r = core.titleIndex[rhs] else { return 0 }
            return engine.similarity.similarity(l, r)
        }
        func row(_ name: String, _ ranking: [String]) -> EvalRow {
            EvalRow(
                name: name, recall: RankingMetrics.recall(ranking, relevant: relevant, k: recallK),
                ndcg: RankingMetrics.ndcg(ranking, relevant: relevant, k: ndcgK),
                coverage: RankingMetrics.coverage(ranking, relevant: relevant),
                novelty: RankingMetrics.novelty(ranking, popularity: votes, k: recallK),
                diversity: RankingMetrics.diversity(ranking, k: recallK, similarity: similarity),
                listSize: ranking.count,
            )
        }

        var rows: [EvalRow] = []
        rows.append(row(blend, engine.output.ranked.map(\.titleId)))
        rows.append(row(page, pageOrder(engine.output.page)))
        for kind in SourceKind.allCases {
            rows.append(row(sourceName(kind), engine.diagnostics.sources[kind] ?? []))
        }
        rows.append(row(Self.popularity, popularityBaseline(core)))
        rows.append(row(watchAlso, watchAlsoBaseline(core)))
        return EvalReport(
            rows: rows, heldOut: split.heldOut, poolSize: core.titles.count, recallK: recallK, ndcgK: ndcgK,
            timings: engine.diagnostics.timings,
        )
    }

    /// Home as the user sees it: the hero, then the rows top to bottom.
    static func pageOrder(_ page: PageLayout) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        let heroItems = page.hero.map { [$0.main] + $0.alternatives } ?? []
        for item in heroItems + page.rows.flatMap(\.items) where seen.insert(item.titleId).inserted {
            order.append(item.titleId)
        }
        return order
    }

    static func sourceName(_ kind: SourceKind) -> String {
        switch kind {
        case .graph: "S1 граф"
        case .continuation: "S2 продолжения"
        case .intent: "S3 намерение"
        case .affinity: "S4 аффинитет"
        case .people: "S5 люди"
        case .qualityFresh: "S6 качество"
        case .exploration: "S7 новое"
        }
    }

    /// Eligible titles by votes, most popular first.
    static func popularityBaseline(_ core: EngineCore) -> [String] {
        (0..<core.titles.count).filter(core.isEligible)
            .map { (index: $0, votes: QualityFreshSource.popularity(core.titles[$0]) ?? 0) }
            .sorted { $0.votes != $1.votes ? $0.votes > $1.votes : $0.index < $1.index }
            .map { core.titles[$0.index].id }
    }

    /// «Смотрите также» of the most recently finished title, eligible ones in the site's order.
    static func watchAlsoBaseline(_ core: EngineCore) -> [String] {
        let last = core.orderedSignals.filter { $0.finished && $0.completedAt != nil && core.titleIndex[$0.titleId] != nil }
            .max { ($0.completedAt ?? 0, $1.titleId) < ($1.completedAt ?? 0, $0.titleId) }
        guard let last, let index = core.titleIndex[last.titleId] else { return [] }
        return core.titles[index].watchAlso.filter { id in
            guard let other = core.titleIndex[id] else { return false }
            return core.isEligible(other)
        }
    }
}
