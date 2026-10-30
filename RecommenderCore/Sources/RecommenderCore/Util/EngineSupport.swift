import Foundation

/// Time arithmetic shared by the stages: every age is measured in days, every timestamp in seconds since 1970.
enum EngineTime {
    static let day: Double = 86_400

    /// The user's offset from UTC, read from the context (its local hour against the clock), rounded to 15 minutes.
    /// The core never asks the system for a time zone, so a run is the same on any Mac and on the TV server.
    static func utcOffset(_ context: EngineContext) -> Double {
        var utcSecondsOfDay = context.now.truncatingRemainder(dividingBy: day)
        if utcSecondsOfDay < 0 { utcSecondsOfDay += day }
        var diff = Double(context.hour * 3600 + context.minute * 60) - utcSecondsOfDay
        while diff <= -12 * 3600 { diff += day }
        while diff > 14 * 3600 { diff -= day }
        return (diff / 900).rounded() * 900
    }

    /// The local calendar day a moment falls on (for «≥3 серий в день»).
    static func localDay(_ time: Double, offset: Double) -> Int {
        Int(((time + offset) / day).rounded(.down))
    }

    static func days(from time: Double, to now: Double) -> Double {
        (now - time) / day
    }
}

/// Deterministic hashing and uniform numbers. Swift's `Hasher` is seeded per process, so it must never decide
/// anything the user sees: these give the same value on every run and in the JS port.
enum StableHash {
    /// FNV-1a over UTF-8.
    static func of(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// SplitMix64's finaliser: spreads any 64-bit input evenly.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform number in [0, 1) for a seed and a key (the same pair always gives the same number).
    static func unit(seed: UInt64, key: String) -> Double {
        let bits = mix(seed ^ mix(of(key)))
        return Double(bits >> 11) / Double(UInt64(1) << 53)
    }
}

/// How text is compared: feature values, folder names and settings all go through the same key.
enum TextKey {
    /// Lowercased, «ё» → «е», trimmed, inner whitespace collapsed.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// The fixed order of titles (node order in the graph, the final tie-break everywhere): numeric ids compare as
/// numbers, others as text, numbers first. Fixed order is what makes two runs, and the Swift and JS ports, agree.
enum TitleOrder {
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let lhsNumeric = isNumeric(lhs)
        let rhsNumeric = isNumeric(rhs)
        if lhsNumeric, rhsNumeric {
            let lhsCount = lhs.utf8.count
            let rhsCount = rhs.utf8.count
            if lhsCount != rhsCount { return lhsCount < rhsCount }
            return lhs < rhs
        }
        if lhsNumeric != rhsNumeric { return lhsNumeric }
        return lhs < rhs
    }

    private static func isNumeric(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }
}

/// Sorted integer arrays: membership and intersection without building sets.
enum SortedInts {
    static func contains(_ array: [Int], _ value: Int) -> Bool {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low < array.count && array[low] == value
    }

    static func intersection(_ lhs: [Int], _ rhs: [Int]) -> [Int] {
        var result: [Int] = []
        var i = 0
        var j = 0
        while i < lhs.count, j < rhs.count {
            if lhs[i] == rhs[j] {
                result.append(lhs[i])
                i += 1
                j += 1
            } else if lhs[i] < rhs[j] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }

    static func intersectionCount(_ lhs: [Int], _ rhs: [Int]) -> Int {
        var count = 0
        var i = 0
        var j = 0
        while i < lhs.count, j < rhs.count {
            if lhs[i] == rhs[j] {
                count += 1
                i += 1
                j += 1
            } else if lhs[i] < rhs[j] {
                i += 1
            } else {
                j += 1
            }
        }
        return count
    }
}

/// Small numeric helpers (namespaced so they never clash with other parts of the package).
enum EngineMath {
    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(high, max(low, value)) }

    /// The mean of a list, 0 when empty.
    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
