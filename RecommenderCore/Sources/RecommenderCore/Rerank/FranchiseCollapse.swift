import Foundation

/// One title per franchise (§4.7 step 2): the next unwatched part; if the user has seen none, the first part (or the
/// best rated when the first is clearly weaker). The representative carries the franchise's best score and the
/// strongest member's sources, so a franchise isn't demoted for being represented by its first part.
enum FranchiseCollapse {
    static func collapse(_ scored: [ScoredTitle], core: EngineCore, nextParts: Set<Int>) -> [ScoredTitle] {
        var groups: [String: [Int]] = [:]
        for (position, candidate) in scored.enumerated() {
            guard let franchise = core.titles[candidate.title].franchiseId, !franchise.isEmpty else { continue }
            groups[franchise, default: []].append(position)
        }
        guard groups.values.contains(where: { $0.count > 1 }) else { return scored }

        var seenFranchises = Set<String>()
        for (index, title) in core.titles.enumerated() where core.signal(index)?.state == .seen {
            if let franchise = title.franchiseId, groups[franchise] != nil { seenFranchises.insert(franchise) }
        }
        var replace: [Int: ScoredTitle] = [:]
        var drop = Set<Int>()
        for franchise in groups.keys.sorted() {
            guard let positions = groups[franchise], positions.count > 1 else { continue }
            let members = positions.map { scored[$0] }
            let representative = representative(
                members, seenAny: seenFranchises.contains(franchise), core: core, nextParts: nextParts,
            )
            guard let best = members.max(by: { $0.score != $1.score ? $0.score < $1.score : $0.title > $1.title }),
                  let repPosition = positions.first(where: { scored[$0].title == representative.title })
            else { continue }
            var merged = representative
            if best.title != representative.title {
                merged.score = best.score
                merged.contributions = mergedContributions(representative.contributions, best.contributions)
            }
            replace[repPosition] = merged
            for position in positions where position != repPosition { drop.insert(position) }
        }
        var result: [ScoredTitle] = []
        result.reserveCapacity(scored.count)
        for (position, candidate) in scored.enumerated() where !drop.contains(position) {
            result.append(replace[position] ?? candidate)
        }
        return result.sorted { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
    }

    static func representative(
        _ members: [ScoredTitle], seenAny: Bool, core: EngineCore, nextParts: Set<Int>,
    ) -> ScoredTitle {
        if let next = members.first(where: { nextParts.contains($0.title) }) { return next }
        let byPosition = members.sorted {
            let lhs = core.graph.franchisePosition[$0.title] ?? Int.max
            let rhs = core.graph.franchisePosition[$1.title] ?? Int.max
            return lhs != rhs ? lhs < rhs : $0.title < $1.title
        }
        guard let first = byPosition.first else { return members[0] }
        if seenAny { return first }
        // Nothing seen yet: start from the beginning unless the first part is clearly weaker than the best rated.
        guard let bestRated = members.max(by: { $0.quality != $1.quality ? $0.quality < $1.quality : $0.title > $1.title })
        else { return first }
        return first.quality >= bestRated.quality - 0.1 ? first : bestRated
    }

    /// Per source, the stronger of the two contributions.
    static func mergedContributions(_ lhs: [SourceContribution], _ rhs: [SourceContribution]) -> [SourceContribution] {
        var bySource: [SourceKind: SourceContribution] = [:]
        for contribution in lhs + rhs {
            if let existing = bySource[contribution.source], existing.value >= contribution.value { continue }
            bySource[contribution.source] = contribution
        }
        return bySource.values.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.source.listOrder < $1.source.listOrder
        }
    }
}
