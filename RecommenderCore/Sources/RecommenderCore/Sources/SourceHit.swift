import Foundation

/// One candidate from one source: the title, how strongly the source wants it, and the proof.
struct SourceHit: Sendable {
    var title: Int
    var score: Double
    var evidence: Evidence
}

/// A source's candidates, best first, with 1-based ranks for fusion.
struct SourceRanking: Sendable {
    let kind: SourceKind
    let hits: [SourceHit]
    let rankOf: [Int: Int]

    init(kind: SourceKind, hits: [SourceHit], limit: Int? = nil) {
        self.kind = kind
        var sorted = hits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
        if let limit, sorted.count > limit { sorted = Array(sorted.prefix(limit)) }
        self.hits = sorted
        var rankOf: [Int: Int] = [:]
        rankOf.reserveCapacity(sorted.count)
        for (position, hit) in sorted.enumerated() where rankOf[hit.title] == nil {
            rankOf[hit.title] = position + 1
        }
        self.rankOf = rankOf
    }

    func hit(for title: Int) -> SourceHit? {
        guard let rank = rankOf[title] else { return nil }
        return hits[rank - 1]
    }
}

/// The candidate sources (§4.5): each turns the core into ranked hits for eligible titles only, so a source's rank
/// counts only what can actually be shown.
enum CandidateSources {
    static func all(_ core: EngineCore) -> [SourceRanking] {
        [
            GraphSource.ranking(core),
            ViewersSource.ranking(core),
            ContinuationSource.ranking(core),
            IntentSource.ranking(core),
            AffinitySource.ranking(core),
            PeopleSource.ranking(core),
            QualityFreshSource.ranking(core),
            ExplorationSource.ranking(core),
        ]
    }
}
