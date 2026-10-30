import Foundation

/// A list card's caption («2019, США, Драмы»), read into its parts: the recommender knows a card-only title by its
/// year, countries and primary genre, so «Похоже на…» and the taste profile work before its page is ever opened.
enum CardCaptionParser {
    struct Caption: Equatable, Sendable {
        /// The first year («2019»; for a series «2011 - ...» or «2011-2019» the first one).
        var year: Int?
        /// The last year of a finished run («2011-2019» → 2019), nil while it's still on or for a film.
        var endYear: Int?
        /// The run is still open («2011 - ...»).
        var isOngoing: Bool
        var countries: [String]
        /// The primary genre as the site writes it («Драмы»).
        var genre: String?

        static let empty = Caption(year: nil, endYear: nil, isOngoing: false, countries: [], genre: nil)
    }

    /// «2019, США, Драмы» → 2019 · [США] · Драмы; «2011 - ..., Великобритания, США, Драмы» → 2011, ongoing ·
    /// [Великобритания, США] · Драмы; «2019, Комедии» → 2019 · Комедии. Anything it can't place is left out rather
    /// than guessed.
    static func parse(_ text: String?) -> Caption {
        guard let text else { return .empty }
        let parts = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return .empty }

        var caption = Caption.empty
        var rest = parts[...]

        if let first = rest.first, let years = years(in: first) {
            caption.year = years.start
            caption.endYear = years.end
            caption.isOngoing = years.isOngoing
            rest = rest.dropFirst()
        }

        guard !rest.isEmpty else { return caption }

        // The genre closes the caption; the countries sit between it and the year. A lone word after the year is
        // a genre only when it reads like one (the site's genres are plural nouns or adjectives: «Драмы»,
        // «Документальные»), so «2019, США» doesn't make «США» a genre.
        if rest.count == 1 {
            let word = rest[rest.startIndex]
            if looksLikeGenre(word) {
                caption.genre = word
            } else {
                caption.countries = [word]
            }
            return caption
        }

        if let last = rest.last {
            caption.genre = last
            caption.countries = Array(rest.dropLast())
        }
        return caption
    }

    /// «2019» → 2019; «2011 - ...» → 2011, ongoing; «2011-2019» / «2011 – 2019» → 2011…2019. Nil when the part
    /// isn't a year at all.
    static func years(in part: String) -> (start: Int, end: Int?, isOngoing: Bool)? {
        let numbers = part.matches(of: #/(?:19|20)\d\d/#).compactMap { Int($0.output) }
        guard let start = numbers.first else { return nil }
        // Only a year (and a range's punctuation) may be in it: «12 обезьян» isn't a year.
        let leftover = part.replacing(#/(?:19|20)\d\d/#, with: "").trimmingCharacters(in: CharacterSet(charactersIn: " -–—.…"))
        guard leftover.isEmpty else { return nil }
        let isOngoing = part.contains("...") || part.contains("…")
        let end = numbers.count > 1 ? numbers.last : nil
        return (start, end, isOngoing)
    }

    /// The site's genre names that could be mistaken for anything else, and the endings its genre names share.
    private static let knownGenres: Set<String> = Set([
        "аниме", "биографические", "боевики", "вестерны", "военные", "детективы", "детские", "документальные", "драмы",
        "исторические", "комедии", "короткометражные", "криминал", "мелодрамы", "музыкальные", "мультфильмы", "мюзиклы",
        "приключения", "семейные", "спортивные", "триллеры", "ужасы", "фантастика", "фэнтези", "эротика", "арт-хаус",
        "зарубежные", "русские", "советские", "украинские", "сказки", "стендап", "реальное тв", "ток-шоу", "мистика",
        "кулинария", "путешествия", "познавательные", "развлекательные", "юмористические", "сёнэн", "сэйнэн", "меха",
        "кодомо", "сёдзё", "махо-сёдзё", "этти", "спорт", "образовательные", "полнометражные", "многосерийные",
        "фильмы-спектакли", "концерты", "церемонии", "передачи", "конкурсы",
    ].map { $0.replacingOccurrences(of: "ё", with: "е") })

    static func looksLikeGenre(_ word: String) -> Bool {
        let word = word.lowercased().replacingOccurrences(of: "ё", with: "е")
        if knownGenres.contains(word) { return true }
        return word.hasSuffix("ые") || word.hasSuffix("ие") || word.hasSuffix("ии")
    }
}
