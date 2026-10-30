import Foundation
@testable import RecommenderCore

/// Hand-made titles and signals for small, readable scenarios. Times are relative to `Fixture.now`.
enum Fixture {
    /// Friday 30 October 2026, 21:00 UTC (the context below says 21:00 local, so the offset is 0).
    static let now: Double = 1_793_394_000
    static let day: Double = 86400

    static func context(weekday: Int = 5, hour: Int = 21, minute: Int = 0, now: Double = now) -> EngineContext {
        let utcSeconds = now.truncatingRemainder(dividingBy: day)
        let localSeconds = Double(hour * 3600 + minute * 60)
        return EngineContext(now: now + (localSeconds - utcSeconds), weekday: weekday, hour: hour, minute: minute)
    }

    static func film(
        _ id: String, _ name: String? = nil, genres: [String] = ["Драмы"], countries: [String] = ["США"],
        year: Int = 2015, minutes: Int = 100, directors: [PersonRef] = [], actors: [PersonRef] = [],
        boards: [BoardRef] = [], watchAlso: [String] = [], kp: Double? = 7.0, kpVotes: Int? = 20000,
        imdb: Double? = nil, imdbVotes: Int? = nil, franchise: (id: String, parts: [FranchisePart])? = nil,
        age: Int? = 16, level: TitleLevel = .page, kind: TitleKind = .film, releasedAt: Double? = nil,
    ) -> TitleFeatures {
        TitleFeatures(
            id: id, path: "/film/\(id)", level: level, kind: kind, name: name ?? "Фильм \(id)", year: year,
            genres: genres, countries: countries, durationMin: minutes, age: age, directors: directors,
            actors: actors, kpRating: kp, kpVotes: kpVotes, imdbRating: imdb, imdbVotes: imdbVotes, boards: boards,
            franchiseId: franchise?.id, franchise: franchise?.parts ?? [], watchAlso: watchAlso, releasedAt: releasedAt,
            fetchedAt: now - 10 * day,
        )
    }

    static func series(
        _ id: String, _ name: String? = nil, genres: [String] = ["Детективы"], countries: [String] = ["Швеция"],
        year: Int = 2018, episodeMinutes: Int = 50, episodes: Int? = 10, seasons: Int? = 1,
        directors: [PersonRef] = [], actors: [PersonRef] = [], boards: [BoardRef] = [], watchAlso: [String] = [],
        kp: Double? = 7.5, kpVotes: Int? = 30000, lastEpisodeAt: Double? = nil, ended: Bool? = nil, age: Int? = 16,
    ) -> TitleFeatures {
        TitleFeatures(
            id: id, path: "/series/\(id)", level: .page, kind: .series, name: name ?? "Сериал \(id)", year: year,
            genres: genres, countries: countries, durationMin: episodeMinutes, age: age, directors: directors,
            actors: actors, kpRating: kp, kpVotes: kpVotes, boards: boards, watchAlso: watchAlso, isSeries: true,
            releasedEpisodes: episodes, seasons: seasons, ended: ended, lastEpisodeAt: lastEpisodeAt,
            fetchedAt: now - 10 * day,
        )
    }

    /// A finished film session `daysAgo` days ago.
    static func watched(_ id: String, daysAgo: Double = 3, minutes: Double = 100) -> WatchSession {
        let end = now - daysAgo * day
        return WatchSession(
            titleId: id, season: nil, episode: nil, startedAt: end - minutes * 60, endedAt: end, fromPosition: 0,
            toPosition: minutes * 60, duration: minutes * 60, completed: true,
        )
    }

    /// A film session that stopped at `fraction`.
    static func partial(_ id: String, fraction: Double, daysAgo: Double = 3, minutes: Double = 100) -> WatchSession {
        let end = now - daysAgo * day
        let played = minutes * 60 * fraction
        return WatchSession(
            titleId: id, season: nil, episode: nil, startedAt: end - played, endedAt: end, fromPosition: 0,
            toPosition: played, duration: minutes * 60, completed: false,
        )
    }

    /// A finished episode.
    static func episode(_ id: String, season: Int, episode: Int, daysAgo: Double, minutes: Double = 50) -> WatchSession {
        let end = now - daysAgo * day
        return WatchSession(
            titleId: id, season: String(season), episode: String(episode), startedAt: end - minutes * 60, endedAt: end,
            fromPosition: 0, toPosition: minutes * 60, duration: minutes * 60, completed: true,
        )
    }

    static func input(
        titles: [TitleFeatures], signals: UserSignals, settings: RecommenderSettings = RecommenderSettings(),
        context: EngineContext = context(), weights: Weights = .default, seed: UInt64 = 42,
    ) -> EngineInput {
        EngineInput(context: context, titles: titles, signals: signals, settings: settings, weights: weights, seed: seed)
    }

    static func person(_ id: String, _ name: String) -> PersonRef { PersonRef(id: id, name: name) }
}

/// A large, deterministic synthetic catalogue with the shape of the real one: kinds, genres with a long tail, people
/// shared across titles, ranked lists, collections, franchises, «Смотрите также», a third of titles card-only.
enum SyntheticCatalog {
    struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func int(_ range: Range<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }

        mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }

        /// Skewed toward the start (popular genres, busy actors).
        mutating func skewed(_ count: Int) -> Int {
            min(count - 1, Int(Double(count) * pow(unit(), 2.2)))
        }
    }

    static let genres = [
        "Драмы", "Комедии", "Триллеры", "Детективы", "Боевики", "Фантастика", "Мелодрамы", "Криминал", "Ужасы",
        "Приключения", "Фэнтези", "Мультфильмы", "Документальные", "Военные", "Исторические", "Семейные",
        "Биографии", "Вестерны", "Мюзиклы", "Аниме",
    ]
    static let countries = [
        "США", "Россия", "Великобритания", "Франция", "Германия", "Южная Корея", "Япония", "Швеция", "Испания",
        "Италия", "Дания", "Норвегия", "Индия", "Китай", "Канада", "СССР",
    ]

    static func titles(count: Int, seed: UInt64 = 7) -> [TitleFeatures] {
        var random = Generator(state: seed)
        let directors = (0..<max(50, count / 4)).map { Fixture.person("d\($0)", "Режиссёр \($0)") }
        let actors = (0..<max(100, count)).map { Fixture.person("a\($0)", "Актёр \($0)") }
        let lists = (0..<max(10, count / 40)).map { index in
            BoardRef(id: "l\(index)", kind: .list, name: "Лучшие подборка \(index)", size: 50)
        }
        let collections = (0..<max(10, count / 60)).map { index in
            BoardRef(id: "c\(index)", kind: .collection, name: "Подборка \(index)", size: 40)
        }
        var result: [TitleFeatures] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let id = String(100_000 + index)
            let isSeries = random.unit() < 0.35
            let isCard = random.unit() < 0.33
            let genreCount = isCard ? 1 : 1 + random.int(0..<3)
            var titleGenres: [String] = []
            for _ in 0..<genreCount {
                let genre = genres[random.skewed(genres.count)]
                if !titleGenres.contains(genre) { titleGenres.append(genre) }
            }
            let country = countries[random.skewed(countries.count)]
            let year = 1960 + random.int(0..<67)
            var boards: [BoardRef] = []
            if random.unit() < 0.5 {
                var list = lists[random.int(0..<lists.count)]
                list.rank = 1 + random.int(0..<50)
                boards.append(list)
            }
            if !isCard, random.unit() < 0.4 { boards.append(collections[random.int(0..<collections.count)]) }
            let kp = 5 + random.unit() * 3.8
            let votes = Int(pow(10, 2 + random.unit() * 4.5))
            if isCard {
                result.append(TitleFeatures(
                    id: id, path: "/t/\(id)", level: .card, kind: isSeries ? .series : .film, name: "Тайтл \(index)",
                    year: year, genres: titleGenres, countries: [country], kpRating: (kp * 10).rounded() / 10,
                    boards: boards, isSeries: isSeries, fetchedAt: Fixture.now - 30 * Fixture.day,
                ))
                continue
            }
            var watchAlso: [String] = []
            for _ in 0..<random.int(3..<9) {
                watchAlso.append(String(100_000 + random.int(0..<count)))
            }
            let titleActors = (0..<5).map { _ in actors[random.skewed(actors.count)] }
            result.append(TitleFeatures(
                id: id, path: "/t/\(id)", level: .page, kind: isSeries ? .series : .film, name: "Тайтл \(index)",
                year: year, genres: titleGenres, countries: [country],
                durationMin: isSeries ? 20 + random.int(0..<45) : 80 + random.int(0..<80), age: [0, 6, 12, 16, 18][random.int(0..<5)],
                directors: [directors[random.skewed(directors.count)]], actors: titleActors,
                kpRating: (kp * 10).rounded() / 10, kpVotes: votes, imdbRating: ((kp - 0.2) * 10).rounded() / 10,
                imdbVotes: votes / 2, boards: boards, watchAlso: watchAlso, isSeries: isSeries,
                releasedEpisodes: isSeries ? 6 + random.int(0..<30) : nil, seasons: isSeries ? 1 + random.int(0..<5) : nil,
                releasedAt: year >= 2026 ? Fixture.now - Double(random.int(0..<300)) * Fixture.day : nil,
                fetchedAt: Fixture.now - 30 * Fixture.day,
            ))
        }
        return result
    }

    /// About `count` signals over page-level titles: finished films and series, partial views, «Досмотреть» items,
    /// bookmarks, a few ratings and some impressions.
    static func signals(for titles: [TitleFeatures], count: Int, seed: UInt64 = 11) -> UserSignals {
        var random = Generator(state: seed)
        let pages = titles.filter { $0.level == .page }
        guard !pages.isEmpty else { return UserSignals() }
        var signals = UserSignals()
        // Taste: the user favours two genres, so the profile has something to find.
        let favourite = pages.filter { $0.genres.contains("Детективы") || $0.genres.contains("Триллеры") }
        for i in 0..<count {
            let pool = i % 3 == 0 || favourite.isEmpty ? pages : favourite
            let title = pool[random.int(0..<pool.count)]
            let daysAgo = Double(random.int(1..<700))
            switch i % 6 {
            case 0, 1:
                if title.isSeries {
                    for episode in 1...min(6, title.releasedEpisodes ?? 6) {
                        signals.sessions.append(Fixture.episode(title.id, season: 1, episode: episode, daysAgo: daysAgo))
                    }
                } else {
                    signals.sessions.append(Fixture.watched(title.id, daysAgo: daysAgo, minutes: Double(title.durationMin ?? 100)))
                }
            case 2:
                signals.sessions.append(Fixture.partial(title.id, fraction: 0.2 + random.unit() * 0.6, daysAgo: daysAgo))
            case 3:
                signals.accountList.append(AccountListItem(
                    titleId: title.id, watched: random.unit() < 0.7, lastActivityAt: Fixture.now - daysAgo * Fixture.day,
                ))
            case 4:
                signals.bookmarks.append(BookmarkItem(titleId: title.id, folder: random.unit() < 0.5 ? "На выходные" : "Любимое"))
            default:
                signals.ratings.append(ExplicitRating(
                    titleId: title.id, level: [2, 1, -2, 1][random.int(0..<4)], source: .app,
                    createdAt: Fixture.now - daysAgo * Fixture.day,
                ))
            }
            if i % 10 == 0 {
                signals.impressions.append(Impression(
                    titleId: pages[random.int(0..<pages.count)].id, surface: "home", shownAt: Fixture.now - Fixture.day,
                    opened: false,
                ))
            }
        }
        return signals
    }

    static func input(titles count: Int, signals signalCount: Int, seed: UInt64 = 42) -> EngineInput {
        let titles = titles(count: count)
        return Fixture.input(titles: titles, signals: signals(for: titles, count: signalCount), seed: seed)
    }
}
