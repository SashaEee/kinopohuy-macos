import Foundation

/// S1: the site's graph, personalised PageRank from anchors+ (§4.5). The score is PageRank relative to the best
/// candidate plus +0.05 for every extra anchor that reaches the title within two hops, so «Похоже на «Мост» и
/// «Убийство»» outranks a title only one anchor points to.
enum GraphSource {
    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .graph, hits: hits(core))
    }

    static func hits(_ core: EngineCore) -> [SourceHit] {
        let seeds = Set(core.profile.seeds.map(\.title))
        var candidates: [(title: Int, rank: Double)] = []
        for title in 0..<core.titles.count where core.isEligible(title) && !seeds.contains(title) {
            let rank = core.rankForYou[title]
            if rank > 0 { candidates.append((title, rank)) }
        }
        candidates.sort { $0.rank != $1.rank ? $0.rank > $1.rank : $0.title < $1.title }
        candidates = Array(candidates.prefix(core.weights.graphCandidateLimit))
        guard let top = candidates.first?.rank, top > 0 else { return [] }

        let anchors = core.profile.anchors.isEmpty ? core.profile.seeds : core.profile.anchors
        return candidates.map { candidate in
            let links = GraphEvidence.links(to: candidate.title, anchors: anchors, graph: core.graph)
            let extra = min(core.weights.extraAnchorBonusCap, max(0, links.count - 1))
            let score = candidate.rank / top + core.weights.extraAnchorBonus * Double(extra)
            return SourceHit(title: candidate.title, score: score, evidence: evidence(links, candidate: candidate.title, core: core))
        }
    }

    static func evidence(_ links: [GraphLink], candidate: Int, core: EngineCore) -> Evidence {
        guard let best = links.first else { return Evidence() }
        return Evidence(
            anchorIds: links.prefix(3).map(\.anchor.id),
            path: GraphEvidence.path(best, candidate: candidate, titles: core.titles, graph: core.graph),
            board: best.board.map { core.graph.board($0) },
            count: links.count,
        )
    }

    /// Far links for «Открытия»: titles the wide walk (α 0.15) reaches that no anchor reaches within two hops.
    static func farHits(_ core: EngineCore, limit: Int = 100) -> [SourceHit] {
        let seeds = Set(core.profile.seeds.map(\.title))
        let anchors = core.profile.anchors.isEmpty ? core.profile.seeds : core.profile.anchors
        var candidates: [(title: Int, rank: Double)] = []
        for title in 0..<core.titles.count where core.isEligible(title) && !seeds.contains(title) {
            let rank = core.rankDiscover[title]
            if rank > 0 { candidates.append((title, rank)) }
        }
        candidates.sort { $0.rank != $1.rank ? $0.rank > $1.rank : $0.title < $1.title }
        var result: [SourceHit] = []
        guard let top = candidates.first?.rank, top > 0 else { return [] }
        for candidate in candidates {
            if result.count >= limit { break }
            guard GraphEvidence.links(to: candidate.title, anchors: anchors, graph: core.graph).isEmpty else { continue }
            result.append(SourceHit(title: candidate.title, score: candidate.rank / top, evidence: Evidence()))
        }
        return result
    }
}
