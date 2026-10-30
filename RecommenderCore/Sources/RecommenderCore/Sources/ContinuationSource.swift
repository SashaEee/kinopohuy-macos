import Foundation

/// S2: what comes next in something the user watched — the next unwatched part of a franchise, a new season of a
/// watched or loved series (§4.5).
enum ContinuationSource {
    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .continuation, hits: nextParts(core) + newSeasonHits(core))
    }

    /// The first unwatched part after the furthest watched one, when its page is in the pool. A disliked part stops
    /// the franchise: «Не моё» on part one doesn't push part two.
    static func nextParts(_ core: EngineCore) -> [SourceHit] {
        // franchise id → position → title
        var parts: [String: [Int: Int]] = [:]
        for (index, title) in core.titles.enumerated() {
            guard let franchiseId = title.franchiseId, !franchiseId.isEmpty else { continue }
            if let position = core.graph.franchisePosition[index] { parts[franchiseId, default: [:]][position] = index }
            for part in title.franchise {
                guard let id = part.titleId, let partIndex = core.titleIndex[id] else { continue }
                if parts[franchiseId]?[part.position] == nil { parts[franchiseId, default: [:]][part.position] = partIndex }
            }
        }
        var hits: [SourceHit] = []
        for franchiseId in parts.keys.sorted() {
            guard let byPosition = parts[franchiseId] else { continue }
            let positions = byPosition.keys.sorted()
            var furthest: (position: Int, title: Int)?
            for position in positions {
                guard let title = byPosition[position], core.signal(title)?.state == .seen else { continue }
                furthest = (position, title)
            }
            guard let furthest, core.weight(of: furthest.title) > -0.1 else { continue }
            guard let nextPosition = positions.first(where: { $0 > furthest.position }),
                  let next = byPosition[nextPosition], core.isEligible(next)
            else { continue }
            let previous = core.titles[furthest.title]
            let board = core.graph.boardIndex["franchise:\(franchiseId)"].map { core.graph.board($0) }
            hits.append(SourceHit(
                title: next,
                score: 1 + max(0, core.weight(of: furthest.title)) / 2,
                evidence: Evidence(
                    anchorIds: [previous.id],
                    path: [RussianText.quoted(previous.name), "следующая часть", RussianText.quoted(core.titles[next].name)],
                    board: board,
                ),
            ))
        }
        return hits
    }

    static func newSeasonHits(_ core: EngineCore) -> [SourceHit] {
        core.newSeasons.keys.sorted().compactMap { title in
            guard core.isEligible(title) else { return nil }
            let userSeason = core.newSeasons[title] ?? nil
            return SourceHit(
                title: title,
                score: 1.2 + max(0, core.weight(of: title)) / 2,
                evidence: Evidence(anchorIds: [core.titles[title].id], count: userSeason),
            )
        }
    }

    /// Series with a season that came out after the user last watched them: the user liked or finished it (w > 0),
    /// the site lists more seasons than the user reached, and the latest episode is recent.
    /// Returns title → the user's last season (nil when only «вышли новые серии» can be said).
    static func newSeasons(titles: [TitleFeatures], signalAt: [TitleSignal?], now: Double, weights: Weights) -> [Int: Int?] {
        var result: [Int: Int?] = [:]
        for (index, title) in titles.enumerated() where title.isSeries {
            guard let signal = signalAt[index], signal.state != .none, signal.weight > 0, !signal.notMe,
                  signal.exclusion == nil, let released = title.lastEpisodeAt,
                  EngineTime.days(from: released, to: now) <= weights.newSeasonWindowDays,
                  released > (signal.lastActivity ?? 0) + EngineTime.day
            else { continue }
            let seen = signal.state == .seen || signal.episodesWatched >= 3
            guard seen else { continue }
            if let seasons = title.seasons, let userSeason = signal.lastSeason {
                if seasons > userSeason { result[index] = .some(userSeason) }
            } else if signal.state == .seen {
                result[index] = .some(nil)
            }
        }
        return result
    }
}
