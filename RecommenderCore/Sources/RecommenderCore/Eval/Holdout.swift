import Foundation

/// The offline test (§8.3): hide the last N titles the user finished, run the engine on what's left, and see whether
/// it finds them. The hidden titles stay in the pool; every signal about them goes (sessions, positions, the
/// «Досмотреть» entry, bookmarks, follows, ratings, feedback, impressions), so nothing leaks.
public enum Holdout {
    public struct Split: Sendable {
        public var train: EngineInput
        /// The hidden titles, most recently finished first.
        public var heldOut: [String]
    }

    public static func split(_ input: EngineInput, count: Int) -> Split {
        let poolIds = Set(input.titles.map(\.id))
        let titles = Dictionary(input.titles.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let signals = SignalWeighter.weigh(
            input.signals, titles: titles, settings: input.settings, weights: input.weights, context: input.context,
        )
        let finished = signals.values
            .compactMap { signal -> (id: String, at: Double)? in
                guard signal.finished, poolIds.contains(signal.titleId), let at = signal.completedAt else { return nil }
                return (signal.titleId, at)
            }
            .sorted { $0.at != $1.at ? $0.at > $1.at : TitleOrder.precedes($0.id, $1.id) }
        let hidden = Array(finished.prefix(max(0, count)).map(\.id))
        let hiddenSet = Set(hidden)

        var train = input
        var userSignals = input.signals
        userSignals.sessions.removeAll { hiddenSet.contains($0.titleId) }
        userSignals.progress.removeAll { hiddenSet.contains($0.titleId) }
        userSignals.accountList.removeAll { hiddenSet.contains($0.titleId) }
        userSignals.bookmarks.removeAll { hiddenSet.contains($0.titleId) }
        userSignals.followed.removeAll { hiddenSet.contains($0) }
        userSignals.ratings.removeAll { hiddenSet.contains($0.titleId) }
        userSignals.feedback.removeAll { hiddenSet.contains($0.titleId) }
        userSignals.impressions.removeAll { hiddenSet.contains($0.titleId) }
        train.signals = userSignals
        return Split(train: train, heldOut: hidden)
    }
}

/// Ranking quality for one list against the hidden titles.
public enum RankingMetrics {
    /// Share of the hidden titles found in the top K.
    public static func recall(_ ranking: [String], relevant: Set<String>, k: Int) -> Double {
        guard !relevant.isEmpty else { return 0 }
        let hits = ranking.prefix(k).filter(relevant.contains).count
        return Double(hits) / Double(relevant.count)
    }

    /// Binary NDCG@K: hits near the top count more.
    public static func ndcg(_ ranking: [String], relevant: Set<String>, k: Int) -> Double {
        guard !relevant.isEmpty, k > 0 else { return 0 }
        var dcg: Double = 0
        for (position, id) in ranking.prefix(k).enumerated() where relevant.contains(id) {
            dcg += 1 / log2(Double(position) + 2)
        }
        var ideal: Double = 0
        for position in 0..<min(k, relevant.count) { ideal += 1 / log2(Double(position) + 2) }
        return ideal > 0 ? dcg / ideal : 0
    }

    /// Coverage: the share of hidden titles the method can produce at all, anywhere in its list (a source that
    /// never reaches them adds nothing, whatever its order).
    public static func coverage(_ ranking: [String], relevant: Set<String>) -> Double {
        guard !relevant.isEmpty else { return 0 }
        return Double(Set(ranking).intersection(relevant).count) / Double(relevant.count)
    }

    /// Mean self-information of the top K, −log₂ p(t), with p from vote counts: higher = less obvious picks.
    public static func novelty(_ ranking: [String], popularity: [String: Double], k: Int) -> Double {
        let total = popularity.values.reduce(0) { $0 + $1 + 1 }
        guard total > 0 else { return 0 }
        let top = ranking.prefix(k)
        guard !top.isEmpty else { return 0 }
        let bits = top.map { -log2(((popularity[$0] ?? 0) + 1) / total) }
        return bits.reduce(0, +) / Double(top.count)
    }

    /// Intra-list diversity of the top K: the mean of 1 − similarity over all pairs.
    public static func diversity(_ ranking: [String], k: Int, similarity: (String, String) -> Double) -> Double {
        let top = Array(ranking.prefix(k))
        guard top.count >= 2 else { return 0 }
        var sum: Double = 0
        var pairs = 0
        for i in 0..<top.count {
            for j in (i + 1)..<top.count {
                sum += 1 - similarity(top[i], top[j])
                pairs += 1
            }
        }
        return sum / Double(pairs)
    }
}
