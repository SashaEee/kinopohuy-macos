import Foundation

/// A candidate with its final score and every part of it (for reasons, «Почему это?» and the debug view).
struct ScoredTitle: Sendable {
    let title: Int
    var score: Double
    /// norm(fused) ∈ [0, 1].
    var fused: Double
    var affinity: Double
    var quality: Double
    var freshness: Double
    var negProximity: Double
    var fatigue: Double
    /// Each source's share of norm(fused), largest first.
    var contributions: [SourceContribution]

    var sourceCount: Int { contributions.count }

    func contribution(_ source: SourceKind) -> SourceContribution? {
        contributions.first { $0.source == source }
    }
}

/// Weighted reciprocal rank fusion (§4.6, Cormack 2009): fused(t) = Σₛ πₛ / (60 + rankₛ(t)).
enum Fusion {
    struct Fused {
        var value: Double
        var contributions: [SourceContribution]
    }

    static func fuse(_ rankings: [SourceRanking], weights: Weights) -> [Int: Fused] {
        var fused: [Int: Fused] = [:]
        for ranking in rankings {
            let prior = weights.prior(ranking.kind)
            guard prior > 0 else { continue }
            for (position, hit) in ranking.hits.enumerated() where ranking.rankOf[hit.title] == position + 1 {
                let value = prior / (weights.rrfK + Double(position + 1))
                var entry = fused[hit.title] ?? Fused(value: 0, contributions: [])
                entry.value += value
                entry.contributions.append(
                    SourceContribution(source: ranking.kind, rank: position + 1, value: value, evidence: hit.evidence),
                )
                fused[hit.title] = entry
            }
        }
        return fused
    }
}

/// The final score (§4.6): norm(fused) + 0.25·aff + 0.15·Q + 0.05·fresh + 0.05·(sources − 1) − 0.3·negProx − fatigue.
enum Scorer {
    static func score(_ rankings: [SourceRanking], core: EngineCore) -> [ScoredTitle] {
        let weights = core.weights
        let fused = Fusion.fuse(rankings, weights: weights)
        let maxFused = fused.values.map(\.value).max() ?? 0
        let extraShows = Fatigue.extraShows(core.impressions, now: core.now, weights: weights)
        var result: [ScoredTitle] = []
        result.reserveCapacity(fused.count)
        for title in fused.keys.sorted() {
            guard let entry = fused[title] else { continue }
            let norm = maxFused > 0 ? entry.value / maxFused : 0
            let contributions = entry.contributions
                .map { contribution -> SourceContribution in
                    var scaled = contribution
                    scaled.value = maxFused > 0 ? contribution.value / maxFused : 0
                    return scaled
                }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.source.listOrder < $1.source.listOrder }
            result.append(make(
                title: title, fused: norm, contributions: contributions, core: core,
                extraShows: extraShows[core.titles[title].id] ?? 0,
            ))
        }
        return result.sorted { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
    }

    /// Scores one title from its parts (also used for titles no source produced, e.g. «Своё»'s next episodes).
    static func make(
        title: Int, fused: Double, contributions: [SourceContribution], core: EngineCore, extraShows: Int,
    ) -> ScoredTitle {
        let weights = core.weights
        let affinity = core.profile.titleAffinity[title]
        let quality = core.quality[title]
        let freshness = core.freshness[title]
        let negProximity = core.negProximity[title]
        var base = fused
            + weights.scoreAffinity * affinity
            + weights.scoreQuality * quality
            + weights.scoreFresh * freshness
            + weights.scoreMultiSource * Double(max(0, contributions.count - 1))
            - weights.scoreNegProximity * negProximity
        base -= voiceOverPenalty(core.titles[title], core: core)
        let fatigue = Fatigue.penalty(base: base, extraShows: extraShows, weights: weights)
        return ScoredTitle(
            title: title, score: base - fatigue, fused: fused, affinity: affinity, quality: quality,
            freshness: freshness, negProximity: negProximity, fatigue: fatigue, contributions: contributions,
        )
    }

    /// A preferred voice-over that the page lists as absent lowers the title a little (it may still be the best
    /// choice); unknown voice-overs (cards) cost nothing.
    static func voiceOverPenalty(_ title: TitleFeatures, core: EngineCore) -> Double {
        guard let preferred = core.settings.preferredVoiceOver.map(TextKey.normalized), !preferred.isEmpty,
              !title.voiceOvers.isEmpty
        else { return 0 }
        let has = title.voiceOvers.contains { TextKey.normalized($0).contains(preferred) }
        return has ? 0 : core.weights.voiceOverPenalty
    }
}

/// Fatigue (§4.7): every show without an opening beyond the second in 14 days multiplies the score by 0.85.
/// Expressed as a subtraction, so a negative score sinks instead of rising.
enum Fatigue {
    /// title id → shows beyond the free ones in the window (0 when it was opened there).
    static func extraShows(_ impressions: [Impression], now: Double, weights: Weights) -> [String: Int] {
        let windowStart = now - weights.fatigueWindowDays * EngineTime.day
        var shows: [String: Int] = [:]
        var opened = Set<String>()
        for impression in impressions where impression.shownAt >= windowStart && impression.shownAt <= now {
            shows[impression.titleId, default: 0] += 1
            if impression.opened { opened.insert(impression.titleId) }
        }
        var result: [String: Int] = [:]
        for (id, count) in shows where !opened.contains(id) {
            let extra = count - weights.fatigueFreeShows
            if extra > 0 { result[id] = extra }
        }
        return result
    }

    static func penalty(base: Double, extraShows: Int, weights: Weights) -> Double {
        guard extraShows > 0 else { return 0 }
        return abs(base) * (1 - pow(weights.fatigueFactor, Double(extraShows)))
    }
}

extension SourceKind {
    /// The order sources are listed in (S1…S7), the tie-break between equal contributions.
    var listOrder: Int {
        switch self {
        case .graph: 0
        case .continuation: 1
        case .intent: 2
        case .affinity: 3
        case .people: 4
        case .qualityFresh: 5
        case .exploration: 6
        }
    }
}
