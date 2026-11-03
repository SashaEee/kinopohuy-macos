import Foundation
import RecommenderCore

/// The small readings the recommender makes of what the site shows: a title's number and kind from its path, vote
/// counts («1.2M»), the age badge, the Kinopoisk and IMDb ids in the rating links, Russian dates, the release
/// schedule. Pure functions: the same text always gives the same answer (they're checked in `RecSelfCheck`).
enum RecParsing {
    // MARK: Paths

    /// «films/drama/12345-name.html» → «12345» (the number the player, the history and the site's lists use).
    static func titleId(fromPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 3, let last = parts.last, last.hasSuffix(".html") else { return nil }
        let number = last.prefix { $0 != "-" && $0 != "." }
        guard !number.isEmpty, number.allSatisfy(\.isASCIIDigit) else { return nil }
        return String(number)
    }

    /// «films/…» → film, «series/…» → series, «cartoons/…» → cartoon, «animation/…» → anime, «show/…» → show.
    static func kind(fromPath path: String) -> TitleKind? {
        guard let first = path.split(separator: "/", omittingEmptySubsequences: true).first else { return nil }
        return switch first {
        case "films": .film
        case "series": .series
        case "cartoons": .cartoon
        case "animation": .anime
        case "show": .show
        default: nil
        }
    }

    /// «films/drama/12345-name.html» → «drama»: the primary genre's slug, named once a page or a card shows it.
    static func genreSlug(fromPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }
        return String(parts[1])
    }

    /// A genre's own link («films/drama/») → «drama».
    static func genreSlug(fromGenreLink link: String) -> String? {
        let parts = link.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, let last = parts.last, !last.allSatisfy(\.isASCIIDigit) else { return nil }
        return String(last)
    }

    /// «person/12345-ivan-ivanov/» → «12345-ivan-ivanov» (what the person's page is opened by).
    static func personKey(fromPath path: String) -> String? {
        let key = path
            .replacingOccurrences(of: "person/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !key.isEmpty, !key.contains("/") else { return nil }
        return key
    }

    // MARK: Numbers

    /// «1.2M» → 1 200 000, «12.3K» → 12 300, «12 345» → 12 345, «987» → 987; nil for anything without a number.
    static func count(_ text: String?) -> Int? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let upper = text.uppercased()
        let multiplier: Double = if upper.hasSuffix("B") || upper.hasSuffix("МЛРД") { 1_000_000_000 }
            else if upper.hasSuffix("M") || upper.hasSuffix("МЛН") { 1_000_000 }
            else if upper.hasSuffix("K") || upper.hasSuffix("К") || upper.hasSuffix("ТЫС") || upper.hasSuffix("ТЫС.") { 1000 }
            else { 1 }
        if multiplier == 1 {
            let digits = text.filter(\.isASCIIDigit)
            return digits.isEmpty ? nil : Int(digits)
        }
        let number = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isASCIIDigit || $0 == "." }
        guard let value = Double(number) else { return nil }
        return Int((value * multiplier).rounded())
    }

    /// «18+» → 18, «0+» → 0.
    static func age(_ text: String?) -> Int? {
        guard let text, let match = text.firstMatch(of: #/(\d{1,2})\s*\+/#) else { return nil }
        return Int(match.1)
    }

    /// The first year in a text («2019», «15 октября 2019 года», «(2011 - ...)»).
    static func year(_ text: String?) -> Int? {
        guard let text, let match = text.firstMatch(of: #/(?:19|20)\d\d/#) else { return nil }
        return Int(match.output)
    }

    /// «смотреть ещё 12 серий в 2 сезоне» → 12.
    static func episodesLeft(_ text: String?) -> Int? {
        guard let text, let match = text.lowercased().firstMatch(of: #/ещ[её]\s+(\d+)/#) else { return nil }
        return Int(match.1)
    }

    /// The film length from «Время» («120 мин.» comes in as 120 already; «2 ч 5 мин» is read too).
    static func minutes(_ text: String?) -> Int? {
        guard let text else { return nil }
        if let match = text.firstMatch(of: #/(\d+)\s*ч\D*(\d+)?/#) {
            return (Int(match.1) ?? 0) * 60 + (match.2.flatMap { Int($0) } ?? 0)
        }
        return Int(text.filter(\.isASCIIDigit))
    }

    // MARK: External ids

    /// The Kinopoisk id in its link: «…/film/326/» or «…/series/464963/».
    static func kinopoiskId(fromLink link: String?) -> Int? {
        guard let link, let match = link.firstMatch(of: #/\/(?:film|series)\/(\d+)/#) else { return nil }
        return Int(match.1)
    }

    /// The IMDb id in its link: «…/title/tt0111161/».
    static func imdbId(fromLink link: String?) -> String? {
        guard let link, let match = link.firstMatch(of: #/tt\d{5,10}/#) else { return nil }
        return String(match.output)
    }

    // MARK: Dates

    private static let months = ["январ", "феврал", "март", "апрел", "ма", "июн", "июл", "август", "сентябр", "октябр", "ноябр", "декабр"]

    /// «15 октября 2019 года», «26 ноября 2025», «15.10.2019», «15-10-2019», «2019-10-15», «сегодня», «вчера» → the
    /// start of that day in `calendar`; nil for anything else.
    static func date(_ text: String?, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let raw = text?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        if raw.hasPrefix("сегодня") { return today }
        if raw.hasPrefix("вчера") { return calendar.date(byAdding: .day, value: -1, to: today) }

        if let match = raw.firstMatch(of: #/(\d{1,2})\s+([а-яё]+)\s+(\d{4})/#),
           let day = Int(match.1), let year = Int(match.3)
        {
            let word = String(match.2)
            // «мая» and «март» both start with «ма»: the longer stems are tried first.
            let month = months.enumerated()
                .sorted { $0.element.count > $1.element.count }
                .first { word.hasPrefix($0.element) }?.offset
            if let month { return makeDay(year, month + 1, day, calendar) }
        }
        if let match = raw.firstMatch(of: #/(\d{1,2})[.\-\/](\d{1,2})[.\-\/](\d{4})/#),
           let day = Int(match.1), let month = Int(match.2), let year = Int(match.3)
        {
            return makeDay(year, month, day, calendar)
        }
        if let match = raw.firstMatch(of: #/(\d{4})-(\d{1,2})-(\d{1,2})/#),
           let year = Int(match.1), let month = Int(match.2), let day = Int(match.3)
        {
            return makeDay(year, month, day, calendar)
        }
        return nil
    }

    private static func makeDay(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) -> Date? {
        guard (1 ... 12).contains(month), (1 ... 31).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    // MARK: Schedule

    /// What a series' release schedule says so far: episodes out by today, the last season out, and when the
    /// latest and the first episode came.
    struct ScheduleSummary: Equatable, Sendable {
        var released: Int
        var seasons: Int?
        var lastEpisodeAt: Date?
        var firstEpisodeAt: Date?
    }

    /// Reads «1 сезон 4 серия» with its date («26 ноября 2025»); an episode without a date that the site lists
    /// before dated ones counts as out.
    static func schedule(_ items: [(title: String, date: String)], now: Date = .now, calendar: Calendar = .current) -> ScheduleSummary? {
        let today = calendar.startOfDay(for: now)
        var episodes: [String: (season: Int, day: Date?)] = [:]
        for item in items {
            guard let match = item.title.lowercased().firstMatch(of: #/(\d+)\s*сезон\s*(\d+)\s*серия/#),
                  let season = Int(match.1), let episode = Int(match.2)
            else { continue }
            episodes["\(season)-\(episode)"] = (season, date(item.date, now: now, calendar: calendar))
        }
        guard !episodes.isEmpty else { return nil }

        let aired = episodes.values.filter { ($0.day ?? .distantPast) <= today }
        let days = aired.compactMap(\.day)
        return ScheduleSummary(
            released: aired.count,
            seasons: aired.map(\.season).max(),
            lastEpisodeAt: days.max(),
            firstEpisodeAt: days.min(),
        )
    }

    // MARK: Names

    /// For matching names typed by the user against the catalogue: lower case, «ё» as «е», no quotes or punctuation,
    /// single spaces («Мост (2011)» → «мост 2011»).
    static func normalized(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        var scalars = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                scalars.append(" ")
                lastWasSpace = true
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    /// An FTS5 query for a typed name: every word must start a word of the title («мост» finds «Мост», «Мосты
    /// округа Мэдисон»). Each word is quoted, so nothing the user types can be read as FTS syntax.
    static func ftsQuery(_ text: String) -> String? {
        let words = normalized(text).split(separator: " ").prefix(8)
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// A Russian word without its case ending, for matching «Нолана» to «Нолан», «Ди Каприо» to «ДиКаприо»: short
    /// words stay whole.
    static func stem(_ word: String) -> String {
        let word = normalized(word)
        guard word.count > 4 else { return word }
        for ending in ["ами", "ями", "ого", "ему", "ому", "ыми", "ими", "ой", "ей", "ом", "ем", "ым", "им", "ую", "юю", "ая", "яя", "ов", "ев", "а", "я", "у", "ю", "е", "ы", "и"] where word.hasSuffix(ending) && word.count - ending.count >= 3 {
            return String(word.dropLast(ending.count))
        }
        return word
    }

    // MARK: Hashing

    /// FNV-1a: a stable 64-bit hash (Swift's own `Hasher` changes between launches), for the day's seed and the
    /// cached page's profile key.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func fnv1a(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
