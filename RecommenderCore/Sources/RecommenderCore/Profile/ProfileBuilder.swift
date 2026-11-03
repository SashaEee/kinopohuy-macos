import Foundation

/// A title the user's taste rests on, with its weight.
struct Anchor: Sendable, Hashable {
    let title: Int
    let id: String
    let weight: Double
}

/// The taste (§4.3): smoothed feature affinities, every title's affinity, anchors, exclusions and the genre mix.
struct TasteProfile: Sendable {
    /// A(f) ∈ [−1, 1] per feature, after the person floor and the user's overrides.
    let affinity: [Double]
    /// Titles with a nonzero weight that have the feature, and those with a positive one.
    let support: [Int]
    let positiveSupport: [Int]
    /// aff(t) per title.
    let titleAffinity: [Double]
    /// The title shares something the user actually likes (a genre, a country, a person, a collection or list), not
    /// only being a film of the same decade and length: what taste-based sources need before they offer it.
    let tasteMatch: [Bool]
    /// Anchors+: the top titles with w > 0.3 (best first). Anchors−: w < −0.3.
    let anchors: [Anchor]
    let negativeAnchors: [Anchor]
    /// What seeds the graph: anchors+, or every positive title when there are too few anchors.
    let seeds: [Anchor]
    /// «Исключить» on a feature: titles with it are filtered out.
    let excludedFeatures: Set<Int>
    /// Main genre (feature id) → its share among positive titles.
    let genreShare: [Int: Double]
    let positiveCount: Int
    let negativeCount: Int
    let summary: ProfileSummary

    /// The affinity of a feature, 0 when it isn't in the table.
    func affinity(of feature: Int?) -> Double {
        guard let feature, feature < affinity.count else { return 0 }
        return affinity[feature]
    }
}

enum ProfileBuilder {
    /// Builds the taste from title weights. `ordered` is every signal in the fixed title order, so sums don't depend
    /// on dictionary order.
    static func build(
        table: FeatureTable, titles: [TitleFeatures], titleIndex: [String: Int], ordered: [TitleSignal],
        overrides: [TasteOverride], weights: Weights, now: Double,
    ) -> TasteProfile {
        let featureCount = table.count
        var numerator = [Double](repeating: 0, count: featureCount)
        var denominator = [Double](repeating: 0, count: featureCount)
        var support = [Int](repeating: 0, count: featureCount)
        var positiveSupport = [Int](repeating: 0, count: featureCount)
        var dislikedSupport = [Int](repeating: 0, count: featureCount)

        var weighted: [(index: Int, signal: TitleSignal)] = []
        for signal in ordered {
            guard let index = titleIndex[signal.titleId] else { continue }
            weighted.append((index, signal))
        }
        weighted.sort { $0.index < $1.index }

        for (index, signal) in weighted where signal.weight != 0 {
            let w = signal.weight
            for feature in table.ofTitle[index] {
                numerator[feature] += w
                denominator[feature] += abs(w)
                support[feature] += 1
                if w > 0 { positiveSupport[feature] += 1 }
                if signal.isDisliked { dislikedSupport[feature] += 1 }
            }
        }

        // A(f) = Σ wᵢ / (Σ |wᵢ| + 2): one strong title says less than several agreeing ones.
        var affinity = [Double](repeating: 0, count: featureCount)
        for feature in 0..<featureCount where denominator[feature] > 0 {
            var value = numerator[feature] / (denominator[feature] + weights.affinitySmoothing)
            // A person turns «нелюбимый» only after two disliked titles with them: one bad film isn't a verdict.
            let group = table.keys[feature].group
            if group == .director || group == .actor, value < weights.personDislikeFloor, dislikedSupport[feature] < 2 {
                value = weights.personDislikeFloor
            }
            affinity[feature] = value
        }

        // «Закрепить / Приглушить / Исключить / Больше такого», while in force.
        var excluded = Set<Int>()
        let activeOverrides = overrides.filter { ($0.until ?? .infinity) > now }
            .sorted { ($0.feature, $0.mode.rawValue) < ($1.feature, $1.mode.rawValue) }
        for override in activeOverrides {
            guard let feature = table.id(of: override.feature) else { continue }
            switch override.mode {
            case .exclude: excluded.insert(feature)
            case .mute: affinity[feature] = min(affinity[feature], weights.muteAffinity)
            case .pin: affinity[feature] = max(affinity[feature], weights.pinAffinity)
            case .more: affinity[feature] = max(affinity[feature], weights.moreAffinity)
            }
        }

        // aff(t) = Σ G·v / (Σ G + c) over the title's feature groups that hold a feature the user has met (support > 0),
        // G being the group's weight and v its value: genres and countries by 0.6·best + 0.4·idf-weighted mean (a bare card
        // knows only its main genre, a page all of them: the best one keeps them comparable, the mean still marks a
        // thriller-drama as less of a thriller); decade, kind and length have one each; people, collections and lists by
        // the strongest match (one favourite
        // actor is a match, an unknown cast isn't a miss; with no liked one, the most disliked counts). Features nobody
        // watched say nothing either way, so a fully read page isn't diluted below a bare card with one matching genre.
        // The constant keeps one lucky feature from making a perfect match.
        // A country alone is too coarse to call a title «in taste» (most of anyone's films are American); it counts
        // only for a bare card whose genres aren't known yet.
        let tasteGroups: Set<FeatureKey.Group> = [.genre, .director, .actor, .collection, .list]
        let allGroups = FeatureKey.Group.allCases
        let groupIndex = Dictionary(uniqueKeysWithValues: allGroups.enumerated().map { ($1, $0) })
        let featureGroup = table.keys.map { groupIndex[$0.group] ?? 0 }
        let averaged = allGroups.map { [.genre, .country, .decade, .kind, .duration].contains($0) }
        var titleAffinity = [Double](repeating: 0, count: titles.count)
        var tasteMatch = [Bool](repeating: false, count: titles.count)
        var groupWeight = [Double](repeating: 0, count: allGroups.count)
        var groupSum = groupWeight
        var groupNorm = groupWeight
        var groupBest = groupWeight
        var groupWorst = groupWeight
        var groupSeen = [Bool](repeating: false, count: allGroups.count)
        for index in 0..<titles.count {
            for g in 0..<allGroups.count {
                groupSeen[g] = false
                groupSum[g] = 0
                groupNorm[g] = 0
                groupBest[g] = -.infinity
                groupWorst[g] = .infinity
            }
            let matchGroups = titles[index].genres.isEmpty ? tasteGroups.union([.country]) : tasteGroups
            for feature in table.ofTitle[index] {
                guard support[feature] > 0 else { continue }
                let g = featureGroup[feature]
                let value = affinity[feature]
                groupSeen[g] = true
                groupWeight[g] = table.groupWeight[feature]
                if averaged[g] {
                    groupSum[g] += table.idf[feature] * value
                    groupNorm[g] += table.idf[feature]
                }
                groupBest[g] = max(groupBest[g], value)
                groupWorst[g] = min(groupWorst[g], value)
                if value > weights.tasteMatchMinAffinity, matchGroups.contains(table.keys[feature].group) {
                    tasteMatch[index] = true
                }
            }
            var sum: Double = 0
            var norm: Double = 0
            for g in 0..<allGroups.count where groupSeen[g] {
                let mean = groupNorm[g] > 0 ? groupSum[g] / groupNorm[g] : 0
                let value = averaged[g]
                    ? 0.6 * groupBest[g] + 0.4 * mean
                    : (groupBest[g] > 0 ? groupBest[g] : groupWorst[g])
                sum += groupWeight[g] * value
                norm += groupWeight[g]
            }
            // A card is three facts about a title: what it says is less certain than a page.
            let certainty = titles[index].level == .card ? weights.cardAffinityCertainty : 1
            titleAffinity[index] = norm > 0 ? certainty * sum / (norm + weights.affinityTitleSmoothing) : 0
        }

        let inPool = weighted.filter { !$0.signal.notSeed }
        let byWeightDesc: ((index: Int, signal: TitleSignal), (index: Int, signal: TitleSignal)) -> Bool = {
            $0.signal.weight != $1.signal.weight ? $0.signal.weight > $1.signal.weight : $0.index < $1.index
        }
        let anchors = inPool.filter { $0.signal.weight > weights.anchorMinWeight }
            .sorted(by: byWeightDesc)
            .prefix(weights.anchorCount)
            .map { Anchor(title: $0.index, id: $0.signal.titleId, weight: $0.signal.weight) }
        let negativeAnchors = inPool.filter { $0.signal.weight < weights.negativeAnchorMaxWeight }
            .sorted { $0.signal.weight != $1.signal.weight ? $0.signal.weight < $1.signal.weight : $0.index < $1.index }
            .map { Anchor(title: $0.index, id: $0.signal.titleId, weight: $0.signal.weight) }
        let seeds: [Anchor] = if anchors.count >= weights.minSeedAnchors {
            Array(anchors)
        } else {
            inPool.filter { $0.signal.weight > 0 }
                .sorted(by: byWeightDesc)
                .prefix(weights.anchorCount)
                .map { Anchor(title: $0.index, id: $0.signal.titleId, weight: $0.signal.weight) }
        }

        let positives = ordered.filter { $0.weight > 0 }
        let negatives = ordered.filter { $0.weight < 0 }

        // The genre mix of positive titles, by main genre (for the genre cap).
        var genreCounts: [Int: Int] = [:]
        var genreTotal = 0
        for (index, signal) in weighted where signal.weight > 0 {
            guard let genre = table.primaryGenre[index] else { continue }
            genreCounts[genre, default: 0] += 1
            genreTotal += 1
        }
        let genreShare = genreTotal > 0 ? genreCounts.mapValues { Double($0) / Double(genreTotal) } : [:]

        let seriesPositives = weighted.filter { $0.signal.weight > 0 && titles[$0.index].isSeries }.count
        let positivesInPool = weighted.filter { $0.signal.weight > 0 }.count
        let summary = summarize(
            table: table, affinity: affinity, support: support, positiveSupport: positiveSupport,
            positiveCount: positives.count, negativeCount: negatives.count,
            seriesShare: positivesInPool > 0 ? Double(seriesPositives) / Double(positivesInPool) : 0,
        )

        return TasteProfile(
            affinity: affinity, support: support, positiveSupport: positiveSupport, titleAffinity: titleAffinity,
            tasteMatch: tasteMatch, anchors: Array(anchors), negativeAnchors: negativeAnchors, seeds: seeds, excludedFeatures: excluded,
            genreShare: genreShare, positiveCount: positives.count, negativeCount: negatives.count, summary: summary,
        )
    }

    /// The taste in brief for chips and settings: the strongest liked features (genres, countries, decades, people,
    /// kinds) backed by at least two titles, and the clearly disliked ones.
    static func summarize(
        table: FeatureTable, affinity: [Double], support: [Int], positiveSupport: [Int], positiveCount: Int,
        negativeCount: Int, seriesShare: Double,
    ) -> ProfileSummary {
        let shown: Set<FeatureKey.Group> = [.genre, .country, .decade, .director, .actor, .kind]
        var liked: [(feature: Int, rank: Double)] = []
        var disliked: [(feature: Int, rank: Double)] = []
        for feature in 0..<table.count where shown.contains(table.keys[feature].group) {
            let a = affinity[feature]
            if a > 0.05, positiveSupport[feature] >= 2 {
                // The group weight orders equally backed features: a genre reads before a decade.
                liked.append((feature, a * log2(1 + Double(positiveSupport[feature])) * table.groupWeight[feature]))
            } else if a < -0.1, support[feature] >= 2 {
                disliked.append((feature, a))
            }
        }
        liked.sort { $0.rank != $1.rank ? $0.rank > $1.rank : table.keys[$0.feature] < table.keys[$1.feature] }
        disliked.sort { $0.rank != $1.rank ? $0.rank < $1.rank : table.keys[$0.feature] < table.keys[$1.feature] }
        func item(_ feature: Int) -> FeatureAffinity {
            FeatureAffinity(
                feature: table.keys[feature], name: table.names[feature], affinity: affinity[feature],
                support: support[feature],
            )
        }
        return ProfileSummary(
            top: liked.prefix(12).map { item($0.feature) }, disliked: disliked.prefix(6).map { item($0.feature) },
            positiveCount: positiveCount, negativeCount: negativeCount, seriesShare: seriesShare,
        )
    }
}
