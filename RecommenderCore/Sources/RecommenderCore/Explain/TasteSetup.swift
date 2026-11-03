import Foundation

/// What «Уточнить вкус» needs from the engine: the bubbles of «Что вам близко», the next titles to rate after a liked
/// one (as Spotify offers related artists), and how well the taste is known so far.
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

    /// After «Нравится» or «Обожаю» on a title: well-known titles next to it on the site (watch-also, its franchise and
    /// collections) the user is likely to have seen too and hasn't rated, most voted first. The deck slips them in, so
    /// each answer steers the next questions.
    public func rateNext(after titleId: String, excluding: Set<String>, limit: Int = 3) -> [String] {
        guard let title = core.titleIndex[titleId] else { return [] }
        let graph = core.graph
        var near = Set(graph.watchAlso[title])
        for board in graph.titleBoards[title] {
            let kind = graph.board(board).kind
            guard kind == .franchise || kind == .collection else { continue }
            near.formUnion(graph.boardMembers[board].prefix(60))
        }
        near.remove(title)

        func votes(_ index: Int) -> Int {
            let t = core.titles[index]
            return [t.kpVotes, t.imdbVotes, t.siteVotes].compactMap(\.self).max() ?? 0
        }
        return near
            .filter { index in
                let t = core.titles[index]
                return !excluding.contains(t.id) && t.poster != nil && !t.comingSoon
                    && core.signal(index).map { $0.weight == 0 && $0.explicitLevel == nil } ?? true
            }
            .sorted { votes($0) != votes($1) ? votes($0) > votes($1) : core.titles[$0].id < core.titles[$1].id }
            .prefix(limit)
            .map { core.titles[$0].id }
    }

    /// How well the taste is known, 0…1, for «Вкус изучен на 60 %»: what was watched gets it a third of the way (it says
    /// what you play, not what you thought of it); the user's own ratings carry it the rest.
    public func tasteConfidence() -> Double {
        let watched = min(1, Double(core.profile.positiveCount) / 40)
        let rated = Set(input.signals.ratings.map(\.titleId)).count
        let explicit = min(1, Double(rated) / 20)
        return min(1, 0.35 * watched + 0.65 * explicit)
    }
}
