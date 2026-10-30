import Foundation

/// The site's release schedule, read for a title's page: an episode's name and date by its numbers («1 сезон 5
/// серия»), the next release, and the episodes announced but not out yet.
struct EpisodeSchedule: Equatable {
    struct Entry: Equatable {
        let season: Int
        let episode: Int
        /// «Пилот»; nil when the site gives none or only a generic one («Серия 4», «Episode #1.4»).
        let name: String?
        /// As the site writes it: «26 ноября 2025».
        let date: String
        let day: Date?
        /// «1 сезон 8 серия».
        let title: String
    }

    private let entries: [String: Entry]

    init(_ schedule: [SeriesScheduleGroup]?) {
        var entries: [String: Entry] = [:]
        for item in schedule?.flatMap(\.items) ?? [] {
            guard let match = item.title.firstMatch(of: #/(\d+)\s*сезон\s*(\d+)\s*серия/#.ignoresCase()),
                  let season = Int(match.1), let episode = Int(match.2)
            else { continue }
            let name = [item.russianEpisodeName, item.originalEpisodeName ?? ""]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && $0 != "-" && $0 != "—" && !Self.isGeneric($0) }
            let date = item.releaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
            entries["\(season)-\(episode)"] = Entry(season: season, episode: episode, name: name, date: date, day: Self.day(from: date), title: item.title)
        }
        self.entries = entries
    }

    /// The entry for an episode, its numbers as the site gives them («01» and «1» meet).
    func entry(season: String, episode: String) -> Entry? {
        guard let season = Int(season), let episode = Int(episode) else { return nil }
        return entries["\(season)-\(episode)"]
    }

    /// «Новая серия 26 ноября · 1 сезон 8 серия» («сегодня» for today's): the nearest dated entry from today on,
    /// leaving out one already out in the chosen voice-over (`season`: its episodes so far).
    func nextRelease(now: Date = .now, calendar: Calendar = .current, season: MovieSeason? = nil) -> String? {
        let today = calendar.startOfDay(for: now)
        let out = season.map { Self.lastEpisode(of: $0) }
        let upcoming = entries.values.compactMap { entry -> (day: Date, entry: Entry)? in
            if let season, let out, entry.season == Int(season.seasonId), entry.episode <= out { return nil }
            guard let day = entry.day, day >= today else { return nil }
            return (day, entry)
        }
        guard let next = upcoming.min(by: { ($0.day, $0.entry.season, $0.entry.episode) < ($1.day, $1.entry.season, $1.entry.episode) }) else { return nil }
        let when = next.day == today ? "сегодня" : Self.withoutYear(next.entry.date)
        return "Новая серия \(when) · \(next.entry.title)"
    }

    /// The season's episodes the schedule announces after its last one out, in order: dim tiles with their dates.
    /// Only upcoming ones and those aired in the last month (still on their way in this voice-over), not the ones
    /// a voice-over never got years ago.
    func announced(after season: MovieSeason, now: Date = .now, calendar: Calendar = .current) -> [Entry] {
        guard let seasonNumber = Int(season.seasonId) else { return [] }
        let last = Self.lastEpisode(of: season)
        let since = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now)) ?? now
        return entries.values
            .filter { $0.season == seasonNumber && $0.episode > last && ($0.day ?? .distantFuture) >= since }
            .sorted { $0.episode < $1.episode }
    }

    /// Whether an entry's day has come (it aired; the voice-over may still be on its way).
    static func hasAired(_ entry: Entry, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let day = entry.day else { return false }
        return day <= calendar.startOfDay(for: now)
    }

    private static func lastEpisode(of season: MovieSeason) -> Int {
        season.episodes.compactMap { Int($0.episodeId) }.max() ?? 0
    }

    /// «26 ноября 2025» without its year (and a trailing «г.»): «26 ноября».
    static func withoutYear(_ date: String) -> String {
        date.replacing(#/\s+\d{4}\s*(г\.?|года)?\s*$/#, with: "")
    }

    private static func isGeneric(_ name: String) -> Bool {
        name.range(of: #"^(\d+\s*)?(серия|episode)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || name.range(of: #"episode\s*#?\d"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    /// «26 ноября 2025» → that day; nil for anything else.
    private static func day(from text: String) -> Date? {
        guard let match = text.firstMatch(of: #/(\d{1,2})\s+([а-яё]+)\s+(\d{4})/#.ignoresCase()),
              let month = months.firstIndex(of: match.2.lowercased()),
              let day = Int(match.1), let year = Int(match.3)
        else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month + 1, day: day))
    }
}
