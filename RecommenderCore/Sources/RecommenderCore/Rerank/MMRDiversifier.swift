import Foundation

/// What one row may hold (§4.7 step 5): a main genre takes at most max(40 %, its share in the history + 10 pp) of
/// the row, one anchor or one person at most two titles.
struct RowCaps: Sendable {
    /// Main genre feature → its share in the history.
    var genreShare: [Int: Double]
    var genreCapMin: Double
    var genreCapSlack: Double
    /// Titles per anchor or person.
    var perKeyCap: Int
    /// The anchor and person keys each title counts against.
    var keysOf: [Int: [String]]

    func genreLimit(_ genre: Int, rowSize: Int) -> Int {
        let share = max(genreCapMin, (genreShare[genre] ?? 0) + genreCapSlack)
        return max(1, Int((share * Double(rowSize)).rounded(.down)))
    }
}

/// Maximal marginal relevance (§4.7 step 4, λ = 0.7) with the row caps: each next title maximises
/// λ·relevance − (1 − λ)·(its highest similarity to what's already chosen). A title that would break a cap waits;
/// waiting titles are used only to reach the row's minimum, so a row isn't dropped for being too uniform.
enum MMRDiversifier {
    static func select(
        candidates: [Int], relevance: [Double], count: Int, minCount: Int, lambda: Double,
        similarity: TitleSimilarity, primaryGenre: [Int?], caps: RowCaps?,
    ) -> [Int] {
        let n = min(candidates.count, relevance.count)
        guard n > 0, count > 0 else { return [] }
        let low = relevance.prefix(n).min() ?? 0
        let high = relevance.prefix(n).max() ?? 0
        let span = high - low
        let normalized = relevance.prefix(n).map { span > 0 ? ($0 - low) / span : 1 }

        var maxSimilarity = [Double](repeating: 0, count: n)
        var taken = [Bool](repeating: false, count: n)
        var waiting: [Int] = []
        var selected: [Int] = []
        var genreCount: [Int: Int] = [:]
        var keyCount: [String: Int] = [:]
        let rowSize = max(count, 1)

        func violates(_ i: Int) -> Bool {
            guard let caps else { return false }
            let title = candidates[i]
            if let genre = primaryGenre[title], (genreCount[genre] ?? 0) >= caps.genreLimit(genre, rowSize: rowSize) {
                return true
            }
            for key in caps.keysOf[title] ?? [] where (keyCount[key] ?? 0) >= caps.perKeyCap {
                return true
            }
            return false
        }

        func take(_ i: Int) {
            taken[i] = true
            let title = candidates[i]
            selected.append(title)
            if let genre = primaryGenre[title] { genreCount[genre, default: 0] += 1 }
            for key in caps?.keysOf[title] ?? [] { keyCount[key, default: 0] += 1 }
            for j in 0..<n where !taken[j] {
                maxSimilarity[j] = max(maxSimilarity[j], similarity.similarity(title, candidates[j]))
            }
        }

        while selected.count < count {
            var best: Int?
            var bestValue = -Double.infinity
            for i in 0..<n where !taken[i] {
                let value = lambda * normalized[i] - (1 - lambda) * maxSimilarity[i]
                if value > bestValue {
                    bestValue = value
                    best = i
                }
            }
            guard let best else { break }
            if violates(best) {
                taken[best] = true
                waiting.append(best)
                continue
            }
            take(best)
        }
        // Too few under the caps: top up from the waiting ones, in the order they would have come.
        for i in waiting where selected.count < min(minCount, count) {
            selected.append(candidates[i])
        }
        return selected
    }
}

/// The exploration slot in «Для вас» (§4.7 step 6): «Своё» 0, «Микс» 1, «Открытия» 3 of every 8, by the familiarity
/// slider (0 familiar … 1 discoveries).
enum ExplorationSlot {
    static func slotsPerEight(familiarity: Double) -> Int {
        switch familiarity {
        case ..<0.15: 0
        case ..<0.55: 1
        case ..<0.75: 2
        default: 3
        }
    }

    /// Positions (0-based) inside a block of eight where discoveries go.
    static func positions(slots: Int) -> [Int] {
        switch slots {
        case ...0: []
        case 1: [4]
        case 2: [3, 6]
        default: [2, 4, 6]
        }
    }

    /// Weaves discoveries into a row at the slot positions, without duplicates, keeping the row's length.
    static func weave(_ discoveries: [Int], into row: [Int], familiarity: Double, rowSize: Int) -> [Int] {
        let slots = positions(slots: slotsPerEight(familiarity: familiarity))
        guard !slots.isEmpty else { return Array(row.prefix(rowSize)) }
        var pending = discoveries.filter { !row.contains($0) }
        var result: [Int] = []
        var rest = row[...]
        while result.count < rowSize, !(rest.isEmpty && pending.isEmpty) {
            let inBlock = result.count % 8
            if slots.contains(inBlock), !pending.isEmpty {
                result.append(pending.removeFirst())
            } else if let next = rest.first {
                result.append(next)
                rest = rest.dropFirst()
            } else if !pending.isEmpty {
                // The row ran out: the rest stays familiar-only rather than all discoveries.
                break
            }
        }
        return result
    }
}
