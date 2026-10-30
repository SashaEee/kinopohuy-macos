import Foundation

/// How old signals fade (§4.2). Implicit signals keep a long memory (70 %, half-life 180 days) and a short one (30 %,
/// 14 days): last week's binge counts more, yet years of taste still count. Explicit ratings fade slowly (2 years),
/// so «Обожаю» from two years ago is still a strong «Нравится».
enum Decay {
    /// 2^(−age / halfLife); a future date counts as now.
    static func halfLife(ageDays: Double, halfLifeDays: Double) -> Double {
        guard halfLifeDays > 0 else { return 1 }
        return pow(2, -max(0, ageDays) / halfLifeDays)
    }

    /// `0.7·w·2^(−Δ/180) + 0.3·w·2^(−Δ/14)`.
    static func implicit(_ weight: Double, ageDays: Double, weights: Weights) -> Double {
        let long = weights.longMemoryShare
        return long * weight * halfLife(ageDays: ageDays, halfLifeDays: weights.longHalfLifeDays)
            + (1 - long) * weight * halfLife(ageDays: ageDays, halfLifeDays: weights.shortHalfLifeDays)
    }

    static func explicit(_ level: Double, ageDays: Double, weights: Weights) -> Double {
        level * halfLife(ageDays: ageDays, halfLifeDays: weights.explicitHalfLifeDays)
    }
}
