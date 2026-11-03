import Foundation

/// The taste stack (§2.1, branch A): up to 12 of the user's own titles worth a quick «Не моё / Нравится / Обожаю».
/// Half are uncertain (a film stopped at 30–85 %, «watched» on the site with nothing local, a film or a barely begun
/// series played elsewhere, a series dropped after one or two episodes), half confidently finished or far in (to find
/// the «Обожаю»). Picked for variety by MMR, at most one
/// part of a franchise, never a title already rated or marked «не я».
enum OnboardingStack {
    static func titles(core: EngineCore, similarity: TitleSimilarity, count: Int) -> [String] {
        guard count > 0 else { return [] }
        var uncertain: [(title: Int, relevance: Double)] = []
        var confident: [(title: Int, relevance: Double)] = []
        for signal in core.orderedSignals where signal.explicitLevel == nil && !signal.notMe && signal.exclusion == nil {
            guard let index = core.titleIndex[signal.titleId] else { continue }
            let item = core.titles[index]
            let quietDays = signal.lastActivity.map { max(0, EngineTime.days(from: $0, to: core.now)) } ?? 365
            let recency = 1 / (1 + quietDays / 90)
            if signal.inAccountList, signal.finished, !signal.hasLocalData {
                // «Просмотрено» on the site with nothing local: watched on the TV, or just marked?
                uncertain.append((index, recency))
            } else if signal.inAccountList, !signal.hasLocalData, signal.state == .started {
                // Played from «Досмотреть» elsewhere (the TV, the site): a series far in is a sure one to ask about,
                // a film or a series barely begun is the question «и как оно?».
                let deep = (signal.resume?.season ?? 0) >= 2 || (signal.resume?.episode ?? 0) >= 5
                if item.isSeries, deep {
                    confident.append((index, signal.weight + 0.2 * recency))
                } else {
                    uncertain.append((index, recency))
                }
            } else if item.isSeries {
                guard signal.hasLocalData else { continue }
                if signal.state == .started, signal.episodesWatched <= 2, quietDays >= 14 {
                    uncertain.append((index, recency))
                } else if signal.finished || signal.episodesWatched >= 3 {
                    confident.append((index, signal.weight + 0.2 * recency))
                }
            } else if let fraction = signal.filmFraction {
                if fraction >= 0.3, fraction < 0.85 {
                    uncertain.append((index, recency))
                } else if fraction >= 0.85 {
                    confident.append((index, signal.weight + 0.2 * recency))
                }
            }
        }
        let half = count / 2
        var chosenFranchises = Set<String>()
        var chosen: [Int] = []
        let pickedUncertain = diverse(uncertain, count: half, chosen: &chosen, franchises: &chosenFranchises, core: core, similarity: similarity)
        let pickedConfident = diverse(confident, count: count - pickedUncertain.count, chosen: &chosen, franchises: &chosenFranchises, core: core, similarity: similarity)
        var extra: [Int] = []
        if pickedUncertain.count + pickedConfident.count < count {
            extra = diverse(uncertain, count: count - pickedUncertain.count - pickedConfident.count, chosen: &chosen, franchises: &chosenFranchises, core: core, similarity: similarity)
        }
        // Alternate, starting with a confident one: an easy «Обожаю» first.
        var result: [Int] = []
        var confidentQueue = pickedConfident[...]
        var uncertainQueue = (pickedUncertain + extra)[...]
        while !confidentQueue.isEmpty || !uncertainQueue.isEmpty {
            if let next = confidentQueue.popFirst() { result.append(next) }
            if let next = uncertainQueue.popFirst() { result.append(next) }
        }
        return result.prefix(count).map { core.titles[$0].id }
    }

    /// MMR (λ 0.7) over the group, skipping titles already chosen and second parts of a franchise.
    private static func diverse(
        _ group: [(title: Int, relevance: Double)], count: Int, chosen: inout [Int], franchises: inout Set<String>,
        core: EngineCore, similarity: TitleSimilarity,
    ) -> [Int] {
        guard count > 0, !group.isEmpty else { return [] }
        let low = group.map(\.relevance).min() ?? 0
        let high = group.map(\.relevance).max() ?? 0
        let span = high - low
        var remaining = group.sorted { $0.relevance != $1.relevance ? $0.relevance > $1.relevance : $0.title < $1.title }
        var picked: [Int] = []
        while picked.count < count, !remaining.isEmpty {
            var bestIndex: Int?
            var bestValue = -Double.infinity
            for (i, candidate) in remaining.enumerated() {
                if let franchise = core.titles[candidate.title].franchiseId, franchises.contains(franchise) { continue }
                if chosen.contains(candidate.title) { continue }
                let relevance = span > 0 ? (candidate.relevance - low) / span : 1
                let redundancy = chosen.map { similarity.similarity($0, candidate.title) }.max() ?? 0
                let value = 0.7 * relevance - 0.3 * redundancy
                if value > bestValue {
                    bestValue = value
                    bestIndex = i
                }
            }
            guard let bestIndex else { break }
            let title = remaining.remove(at: bestIndex).title
            picked.append(title)
            chosen.append(title)
            if let franchise = core.titles[title].franchiseId, !franchise.isEmpty { franchises.insert(franchise) }
        }
        return picked
    }
}
