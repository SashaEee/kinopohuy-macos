import Foundation

/// What «Уточнить вкус» needs from the engine: the bubbles of «Что вам близко», the grid of «Что хочется посмотреть?»,
/// and how well the taste is known so far.
extension PreparedEngine {
    /// «Что вам близко»: what the data says the user likes (pre-selected, strongest first), what they clearly don't
    /// (negative affinity), then the pool's most common genres and countries to choose from. Never the site's sections
    /// («Зарубежные»), which aren't taste.
    public func tasteBubbles(limit: Int = 18) -> [FeatureAffinity] {
        let summary = core.profile.summary
        var bubbles = Array(summary.top.filter { [.genre, .country, .director, .actor, .decade].contains($0.feature.group) }.prefix(limit / 2))
        bubbles += summary.disliked.filter { $0.feature.group == .genre }.prefix(3)
        var taken = Set(bubbles.map(\.feature))

        // The rest by how common they are in the pool (low idf first): the choices most titles carry.
        let table = core.table
        let common = (0..<table.count)
            .filter { [.genre, .country].contains(table.keys[$0].group) && !taken.contains(table.keys[$0]) }
            .sorted { table.idf[$0] != table.idf[$1] ? table.idf[$0] < table.idf[$1] : table.keys[$0] < table.keys[$1] }
        for feature in common where bubbles.count < limit {
            let key = table.keys[feature]
            // Genres first, a few countries: the bubbles read as tastes, not a map.
            if key.group == .country, bubbles.count(where: { $0.feature.group == .country }) >= 4 { continue }
            bubbles.append(FeatureAffinity(
                feature: key, name: table.names[feature], affinity: core.profile.affinity[feature],
                support: core.profile.support[feature],
            ))
            taken.insert(key)
        }
        return bubbles
    }

    /// How well the taste is known, 0…1, for «Вкус изучен на 60 %»: what was watched gets it a third of the way (it says
    /// what you play, not what you thought of it); the user's own ratings carry it the rest.
    public func tasteConfidence() -> Double {
        let watched = min(1, Double(core.profile.positiveCount) / 40)
        let rated = Set(input.signals.ratings.map(\.titleId)).count
        let explicit = min(1, Double(rated) / 20)
        return min(1, 0.35 * watched + 0.65 * explicit)
    }

    /// «Что хочется посмотреть?»: well-known titles the engine would recommend that the user hasn't seen or lined up,
    /// varied (no two alike), for a grid to tick. Ticking is interest, not a rating.
    public func interestGrid(count: Int = 12) -> [String] {
        func votes(_ index: Int) -> Int {
            let t = core.titles[index]
            return [t.kpVotes, t.imdbVotes, t.siteVotes].compactMap(\.self).max() ?? 0
        }
        let candidates = output.ranked.compactMap { core.titleIndex[$0.titleId] }.filter { index in
            core.titles[index].poster != nil && core.signal(index) == nil
        }
        // Known ones first (people recognise them from a poster), the rest after, each list in the engine's order.
        let known = candidates.filter { votes($0) >= 1000 }
        let rest = candidates.filter { votes($0) < 1000 }
        var chosen: [Int] = []
        for strictness in [0.55, 0.75, 1.01] {
            for index in known + rest where chosen.count < count && !chosen.contains(index) {
                // Varied: nothing too close to what's already in the grid (looser if the grid can't fill).
                if chosen.contains(where: { similarity.similarity($0, index) > strictness }) { continue }
                chosen.append(index)
            }
        }
        return chosen.map { core.titles[$0].id }
    }

    /// The liked titles, strongest first: what the data pack's viewer neighbours are asked about.
    public func tasteSeeds(limit: Int = 150) -> [(titleId: String, weight: Double)] {
        core.orderedSignals.filter { $0.weight > 0 && !$0.notSeed }
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.titleId < $1.titleId }
            .prefix(limit).map { ($0.titleId, $0.weight) }
    }
}
