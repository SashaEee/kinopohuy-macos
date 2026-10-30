import Foundation

/// Personalized PageRank by deterministic power iteration (§4.5): r ← α·s + (1 − α)·Pᵀr, for a fixed number of
/// iterations or until ‖Δ‖₁ < 1e−9. Nodes are pushed in ascending order and sums are plain Doubles, so the result
/// is bit-for-bit the same on every run (and in the JS port, which follows the same order). Mass that reaches a
/// node without out-edges returns to the seeds, so r always sums to 1.
enum PersonalizedPageRank {
    static let tolerance = 1e-9

    /// `seeds`: (node, weight); non-positive weights are ignored. Returns r per node (all zeros without seeds).
    static func run(graph: TitleGraph, seeds: [(node: Int, weight: Double)], alpha: Double, iterations: Int) -> [Double] {
        let n = graph.nodeCount
        var teleport = [Double](repeating: 0, count: n)
        var total: Double = 0
        for seed in seeds where seed.weight > 0 && seed.node >= 0 && seed.node < n {
            teleport[seed.node] += seed.weight
            total += seed.weight
        }
        guard total > 0 else { return [Double](repeating: 0, count: n) }
        var seedNodes: [Int] = []
        for node in 0..<n where teleport[node] > 0 {
            teleport[node] /= total
            seedNodes.append(node)
        }

        var rank = teleport
        var next = [Double](repeating: 0, count: n)
        let damping = 1 - alpha
        let rowStart = graph.rowStart
        let target = graph.target
        let probability = graph.probability
        for _ in 0..<max(1, iterations) {
            for i in 0..<n { next[i] = 0 }
            var dangling: Double = 0
            for u in 0..<n {
                let mass = rank[u]
                if mass == 0 { continue }
                let start = rowStart[u]
                let end = rowStart[u + 1]
                if start == end {
                    dangling += mass
                    continue
                }
                let spread = damping * mass
                for edge in start..<end {
                    next[target[edge]] += spread * probability[edge]
                }
            }
            let restart = alpha + damping * dangling
            for node in seedNodes {
                next[node] += restart * teleport[node]
            }
            var delta: Double = 0
            for i in 0..<n { delta += abs(next[i] - rank[i]) }
            swap(&rank, &next)
            if delta < tolerance { break }
        }
        return rank
    }
}
