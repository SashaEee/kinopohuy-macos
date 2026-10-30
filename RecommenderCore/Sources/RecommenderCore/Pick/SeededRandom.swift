import Foundation

/// SplitMix64: a tiny, well-mixed generator, so «Выбери за меня» gives the same pick for the same session and step
/// (going back shows the same card) on the Mac and the TV alike.
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Standard normal (Box–Muller).
    mutating func nextGaussian() -> Double {
        let u1 = max(nextUnit(), .leastNonzeroMagnitude)
        let u2 = nextUnit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// A per-title stream: the noise a title gets depends on the session seed, the step and the title only, not on
    /// which other titles happen to be in the shortlist.
    static func forTitle(_ titleId: String, seed: UInt64, step: Int) -> SplitMix64 {
        var mixer = SplitMix64(seed: seed ^ (UInt64(truncatingIfNeeded: step) &* 0xD1B5_4A32_D192_ED03) ^ fnv1a(titleId))
        return SplitMix64(seed: mixer.next())
    }

    /// FNV-1a over UTF-8: stable across runs and platforms (Swift's `hashValue` is not).
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
