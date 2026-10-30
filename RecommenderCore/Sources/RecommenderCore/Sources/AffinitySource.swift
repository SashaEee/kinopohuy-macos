import Foundation

/// S4: taste affinity over features, aff(t), across the whole pool including cards (§4.5). The evidence names the
/// two features that contribute most, with the real count of the user's titles that share them.
enum AffinitySource {
    static let limit = 400

    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .affinity, hits: hits(core), limit: limit)
    }

    static func hits(_ core: EngineCore) -> [SourceHit] {
        var scored: [(title: Int, score: Double)] = []
        for title in 0..<core.titles.count where core.isEligible(title) {
            let affinity = core.profile.titleAffinity[title]
            if affinity > 0 { scored.append((title, affinity)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
        return scored.prefix(limit).map { item in
            SourceHit(title: item.title, score: item.score, evidence: evidence(for: item.title, core: core))
        }
    }

    /// The title's strongest liked features (genre, country, decade, people, kind) and how many positive titles of the
    /// user have all of them.
    static func evidence(for title: Int, core: EngineCore) -> Evidence {
        let features = topFeatures(of: title, core: core, limit: 2)
        guard !features.isEmpty else { return Evidence() }
        return Evidence(
            count: sharedPositiveCount(features, core: core),
            features: features.map { core.table.keys[$0] },
        )
    }

    /// Features of a title by g·idf·A, liked ones only (A > 0.1), skipping lists and duration buckets that don't read
    /// as taste.
    static func topFeatures(of title: Int, core: EngineCore, limit: Int) -> [Int] {
        let readable: Set<FeatureKey.Group> = [.genre, .country, .decade, .director, .actor, .kind, .collection]
        var ranked: [(feature: Int, value: Double)] = []
        for feature in core.table.ofTitle[title] {
            let affinity = core.profile.affinity[feature]
            guard affinity > 0.1, readable.contains(core.table.keys[feature].group) else { continue }
            ranked.append((feature, core.table.groupWeight[feature] * core.table.idf[feature] * affinity))
        }
        ranked.sort { $0.value != $1.value ? $0.value > $1.value : $0.feature < $1.feature }
        return ranked.prefix(limit).map(\.feature)
    }

    /// How many of the user's positive titles have every one of these features.
    static func sharedPositiveCount(_ features: [Int], core: EngineCore) -> Int {
        var count = 0
        for signal in core.orderedSignals where signal.weight > 0 {
            guard let title = core.titleIndex[signal.titleId] else { continue }
            let own = core.table.ofTitle[title]
            if features.allSatisfy({ SortedInts.contains(own, $0) }) { count += 1 }
        }
        return count
    }
}
