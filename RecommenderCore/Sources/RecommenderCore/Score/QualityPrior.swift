import Foundation

/// How good a title is, with few votes pulled toward the average (§4.6): (v·r + m·C) / (v + m) for Kinopoisk
/// (m 3000, C 6.6) and IMDb (m 8000, C 6.5), averaged; critics (RT, Metacritic) add 20 % when known; the site's
/// own rating is the last fallback. A card's badge without a vote count still counts, at half the prior's weight.
public enum QualityPrior {
    /// The shrunk rating on the 10-point scale, nil when nothing is known.
    static func rating(_ title: TitleFeatures, weights: Weights) -> Double? {
        func shrink(_ rating: Double?, _ votes: Int?, priorVotes: Double, priorMean: Double) -> Double? {
            guard let rating, rating > 0 else { return nil }
            let v = votes.map { Double(max(0, $0)) } ?? priorVotes * weights.unknownVotesShare
            return (v * rating + priorVotes * priorMean) / (v + priorVotes)
        }
        var parts: [Double] = []
        if let kp = shrink(title.kpRating, title.kpVotes, priorVotes: weights.kpPriorVotes, priorMean: weights.kpPriorMean) {
            parts.append(kp)
        }
        if let imdb = shrink(title.imdbRating, title.imdbVotes, priorVotes: weights.imdbPriorVotes, priorMean: weights.imdbPriorMean) {
            parts.append(imdb)
        }
        var base: Double? = parts.isEmpty ? nil : EngineMath.mean(parts)
        if base == nil {
            base = shrink(title.siteRating, title.siteVotes, priorVotes: weights.sitePriorVotes, priorMean: weights.sitePriorMean)
        }
        var critics: [Double] = []
        if let rt = title.rtCritic { critics.append(Double(rt) / 10) }
        if let mc = title.metacritic { critics.append(Double(mc) / 10) }
        let criticScore: Double? = critics.isEmpty ? nil : EngineMath.mean(critics)
        switch (base, criticScore) {
        case let (base?, critic?): return (1 - weights.criticsShare) * base + weights.criticsShare * critic
        case let (base?, nil): return base
        case let (nil, critic?): return critic
        case (nil, nil): return nil
        }
    }

    /// (Q − 5) / 4 in [0, 1]; unknown quality counts as the prior average.
    static func normalized(_ rating: Double?, weights: Weights) -> Double {
        EngineMath.clamp(((rating ?? weights.imdbPriorMean) - 5) / 4, 0, 1)
    }

    /// Reads a vote count as the site shows it: «1.2M», «12K», «1 234», «12,5 тыс.», «(1,2 млн)». Nil when there is
    /// no number in it. Separators are thousands unless a «K/тыс/M/млн» suffix makes the number a fraction.
    public static func parseVotes(_ text: String) -> Int? {
        let scalars = Array(text.lowercased().unicodeScalars)
        func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 48 && scalar.value <= 57 }
        guard var position = scalars.firstIndex(where: isDigit) else { return nil }
        var raw = ""
        while position < scalars.count {
            let scalar = scalars[position]
            if isDigit(scalar) {
                raw.unicodeScalars.append(scalar)
            } else if scalar == "." || scalar == "," {
                raw.append(",")
            } else if scalar == " " || scalar == "\u{00A0}" || scalar == "\u{2009}" || scalar == "\u{202F}" {
                raw.append(" ")
            } else {
                break
            }
            position += 1
        }
        let rest = String(String.UnicodeScalarView(scalars[position...])).trimmingCharacters(in: .whitespaces)
        let multiplier: Double = if rest.hasPrefix("m") || rest.hasPrefix("млн") || rest.hasPrefix("м") {
            1_000_000
        } else if rest.hasPrefix("k") || rest.hasPrefix("к") || rest.hasPrefix("тыс") {
            1000
        } else {
            1
        }
        if multiplier == 1 {
            return Int(raw.filter(\.isNumber))
        }
        var number = ""
        var separated = false
        for character in raw where character != " " {
            if character == "," {
                if !separated { number.append(".") }
                separated = true
            } else {
                number.append(character)
            }
        }
        guard let value = Double(number) else { return nil }
        return Int((value * multiplier).rounded())
    }
}
