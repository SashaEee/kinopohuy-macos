import Foundation

/// S7: exploration (§4.5) — highly rated titles in a genre or country the user has barely seen (|A| < 0.1, at most
/// one title of theirs), never in anything they dislike. «Что-то новое: корейское кино, КП 8,0».
enum ExplorationSource {
    static let limit = 200

    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .exploration, hits: hits(core), limit: limit)
    }

    static func hits(_ core: EngineCore) -> [SourceHit] {
        let weights = core.weights
        var hits: [SourceHit] = []
        for title in 0..<core.titles.count where core.isEligible(title) {
            let quality = core.quality[title]
            guard quality >= weights.explorationMinQuality, core.qualityRating[title] != nil else { continue }
            let novel = novelFeatures(of: title, core: core)
            guard !novel.isEmpty else { continue }
            hits.append(SourceHit(
                title: title, score: quality + 0.05 * Double(novel.count),
                evidence: Evidence(features: novel.map { core.table.keys[$0] }),
            ))
        }
        return hits
    }

    /// The title's main genre and countries that are new to the user; empty if any of its genres or countries is
    /// disliked (something new shouldn't be something they avoid).
    static func novelFeatures(of title: Int, core: EngineCore) -> [Int] {
        let weights = core.weights
        var novel: [Int] = []
        for feature in core.table.ofTitle[title] {
            let group = core.table.keys[feature].group
            guard group == .genre || group == .country else { continue }
            let affinity = core.profile.affinity[feature]
            if affinity <= -weights.explorationMaxAffinity { return [] }
            if abs(affinity) < weights.explorationMaxAffinity, core.profile.support[feature] <= 1 {
                if group == .country || feature == core.table.primaryGenre[title] { novel.append(feature) }
            }
        }
        return novel
    }
}
