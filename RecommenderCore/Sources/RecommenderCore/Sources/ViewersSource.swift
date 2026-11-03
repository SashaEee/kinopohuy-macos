import Foundation

/// S8: «кому понравилось X, понравилось и Y» — what viewers who liked the user's anchors liked too, from MovieLens's
/// neighbour lists in the data pack (titles matched by IMDb id). Each anchor's neighbours count by the anchor's weight
/// times their score; the evidence names the anchors that brought a title, strongest first. Collaborative: it finds
/// what genres can't (the same tone, the same audience), but only among titles MovieLens knows.
enum ViewersSource {
    static let limit = 400

    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .viewers, hits: hits(core.viewerNeighbours, core), limit: limit)
    }

    static func hits(_ core: EngineCore) -> [SourceHit] {
        hits(core.viewerNeighbours, core)
    }

    /// Each seed's neighbours (by viewers or by plot) by the seed's weight times their score.
    static func hits(_ lists: [Int: [(title: Int, score: Double)]], _ core: EngineCore) -> [SourceHit] {
        guard !lists.isEmpty else { return [] }
        var score: [Int: Double] = [:]
        var from: [Int: [(anchor: Int, value: Double)]] = [:]
        // Every liked title counts by its weight (old ones already weigh less): the strong anchors alone are too few
        // when the user's history is mostly what the site's lists know.
        for signal in core.orderedSignals where signal.weight > 0 && !signal.notSeed {
            guard let anchor = core.titleIndex[signal.titleId], let neighbours = lists[anchor] else { continue }
            for neighbour in neighbours where core.isEligible(neighbour.title) {
                let value = signal.weight * neighbour.score
                score[neighbour.title, default: 0] += value
                from[neighbour.title, default: []].append((anchor, value))
            }
        }
        let ranked = score.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit)
        return ranked.map { title, value in
            let anchors = (from[title] ?? []).sorted { $0.value != $1.value ? $0.value > $1.value : $0.anchor < $1.anchor }
            return SourceHit(
                title: title, score: value,
                evidence: Evidence(anchorIds: anchors.prefix(3).map { core.titles[$0.anchor].id }, count: anchors.count),
            )
        }
    }
}

/// S9: close by plot — the descriptions of the user's anchors and the candidates, compared by meaning (on-device
/// embeddings, centred). Finds the same story in another genre's clothes; only among titles whose page was read.
enum PlotSource {
    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .plot, hits: ViewersSource.hits(core.plotNeighbours, core), limit: ViewersSource.limit)
    }
}
