import Foundation

/// S6: quality and freshness (§4.5) — titles from the site's ranked lists that fit the taste (aff > 0), by their
/// place; new releases in the user's genres. With no taste yet (a guest, a fresh account) it becomes the diverse
/// popular fallback: well-rated titles with many votes, still within the user's exclusions.
enum QualityFreshSource {
    static let limit = 400

    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .qualityFresh, hits: hits(core), limit: limit)
    }

    static func hits(_ core: EngineCore) -> [SourceHit] {
        let cold = core.profile.positiveCount == 0
        var best: [Int: SourceHit] = [:]
        func offer(_ hit: SourceHit) {
            if let existing = best[hit.title], existing.score >= hit.score { return }
            best[hit.title] = hit
        }
        for title in 0..<core.titles.count where core.isEligible(title) {
            let affinity = core.profile.titleAffinity[title]
            guard cold ? affinity >= 0 : affinity > 0 && core.profile.tasteMatch[title] else { continue }
            let quality = core.quality[title]

            // Ranked lists: the best place across the title's lists.
            var bestPlace: (board: Int, value: Double)?
            for board in core.graph.titleBoards[title] where core.graph.board(board).kind == .list {
                guard let rank = rank(of: title, in: board, core: core) else { continue }
                // The catalogue rarely holds a whole list: an unknown length counts as the site's usual 50, and one
                // year's list says less than an all-time one.
                let ref = core.graph.board(board)
                let size = max(core.graph.boardSize[board], ref.size ?? 50, rank)
                let yearly = ref.id.range(of: "(19|20)\\d\\d", options: .regularExpression) != nil
                let value = (1 - Double(rank - 1) / Double(max(1, size))) * (yearly ? 0.6 : 1)
                if let current = bestPlace, current.value >= value { continue }
                bestPlace = (board, value)
            }
            if let bestPlace {
                var ref = core.graph.board(bestPlace.board)
                ref.rank = rank(of: title, in: bestPlace.board, core: core)
                offer(SourceHit(
                    title: title, score: 0.6 * bestPlace.value + 0.4 * quality + 0.3 * affinity,
                    evidence: Evidence(board: ref),
                ))
            }

            // New releases in the user's taste.
            if let age = Freshness.ageDays(core.titles[title], now: core.now), age < core.weights.newReleaseDays {
                let fresh = core.freshness[title]
                let genre = core.table.primaryGenre[title]
                offer(SourceHit(
                    title: title, score: fresh * (0.5 + affinity) + 0.2 * quality,
                    evidence: Evidence(features: genre.map { [core.table.keys[$0]] } ?? []),
                ))
            }

            // No taste yet: popular and well rated.
            if cold, let votes = popularity(core.titles[title]), votes > 0 {
                offer(SourceHit(
                    title: title, score: 0.5 * quality + 0.5 * min(1, log10(1 + Double(votes)) / 6),
                    evidence: Evidence(count: votes),
                ))
            }
        }
        return best.keys.sorted().compactMap { best[$0] }
    }

    /// The title's place in a ranked list, as its page says.
    static func rank(of title: Int, in board: Int, core: EngineCore) -> Int? {
        let key = core.graph.board(board).key
        return core.titles[title].boards.first { $0.key == key }?.rank
    }

    /// The most votes any rating shows (the site's popularity proxy).
    static func popularity(_ title: TitleFeatures) -> Int? {
        [title.siteVotes, title.kpVotes, title.imdbVotes].compactMap(\.self).max()
    }
}
