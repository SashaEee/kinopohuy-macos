import Foundation
@testable import RecommenderCore

/// A tiny synthetic catalogue for the picker's tests: no site data, just enough variety (kinds, lengths, ages,
/// genres, countries, ratings, links) to exercise every rule.
enum PickFixtures {
    /// Friday 30 October 2026, 21:00.
    static let now: Double = 1_793_394_000
    static let engineContext = EngineContext(now: now, weekday: 5, hour: 21, minute: 0)

    static func title(
        _ id: String, _ kind: TitleKind = .film, name: String? = nil, genres: [String] = [], minutes: Int? = nil,
        age: Int? = nil, year: Int? = 2018, countries: [String] = ["США"], kp: Double? = 7.0, imdb: Double? = nil,
        series: Bool? = nil, watchAlso: [String] = [], boards: [BoardRef] = [], franchise: String? = nil,
        directors: [PersonRef] = [], actors: [PersonRef] = [], votes: Int? = nil
    ) -> TitleFeatures {
        TitleFeatures(
            id: id, path: "/t/\(id)", level: .page, kind: kind, name: name ?? "Тайтл \(id)", year: year, genres: genres,
            countries: countries, durationMin: minutes, age: age, directors: directors, actors: actors, kpRating: kp,
            kpVotes: votes, imdbRating: imdb, boards: boards, franchiseId: franchise, watchAlso: watchAlso,
            isSeries: series ?? (kind == .series || kind == .show), fetchedAt: now,
        )
    }

    static func rec(_ id: String, _ score: Double) -> Recommendation {
        Recommendation(
            titleId: id, score: score, contributions: [],
            reason: Reason(kind: .featureCombo, short: "Ваше сочетание", long: "Ваше сочетание", evidence: Evidence()),
            tags: [],
        )
    }

    /// Ranked by the given scores (best first), with optional own and discovery pools.
    static func context(
        _ titles: [TitleFeatures], scores: [String: Double], own: [String] = [], discover: [String] = [],
        impressions: [Impression] = [], settings: RecommenderSettings = RecommenderSettings(), extraRanked: [String] = []
    ) -> PickContext {
        let ranked = (titles.map(\.id) + extraRanked)
            .map { rec($0, scores[$0] ?? 0.5) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.titleId < $1.titleId }
        return PickContext(
            ranked: ranked, titles: Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) }),
            ownPool: own.map { rec($0, scores[$0] ?? 0.5) }, discoverPool: discover.map { rec($0, scores[$0] ?? 0.5) },
            titleWeights: [:], impressions: impressions, context: engineContext, settings: settings, weights: .default,
        )
    }

    static let nolan = PersonRef(id: "p-nolan", name: "Кристофер Нолан")
    static let hardy = PersonRef(id: "p-hardy", name: "Том Харди")

    /// Thirty titles across kinds and moods, with a graph: «Мост» links to «Убийство» and «Охота»; «Дюна» has a sequel.
    static let catalogue: [TitleFeatures] = [
        title("comedy1", genres: ["Комедии"], minutes: 92, age: 12, year: 2021, kp: 7.4),
        title("comedy2", genres: ["Комедии", "Мелодрамы"], minutes: 105, age: 16, year: 2015, kp: 7.1),
        title("comedy3", genres: ["Комедии"], minutes: 140, age: 18, year: 2012, kp: 6.8),
        title("family1", genres: ["Семейные", "Приключения"], minutes: 98, age: 6, year: 2019, kp: 7.6),
        title("cartoon1", .cartoon, genres: ["Мультфильмы", "Комедии"], minutes: 88, age: 0, year: 2020, kp: 7.9),
        title("cartoonSeries", .cartoon, genres: ["Мультфильмы"], minutes: 22, age: 6, year: 2017, series: true),
        title("horror1", genres: ["Ужасы"], minutes: 95, age: 18, year: 2022, kp: 6.9),
        title("horror2", genres: ["Ужасы", "Мистика"], minutes: 110, age: 18, year: 2016, kp: 7.2),
        title("thriller1", genres: ["Триллеры"], minutes: 125, age: 18, year: 2014, kp: 8.1),
        title("thriller2", genres: ["Триллеры", "Детективы"], minutes: 100, age: 16, year: 2023, kp: 7.0),
        title("drama1", genres: ["Драмы"], minutes: 135, age: 16, year: 2010, countries: ["Франция"], kp: 7.8),
        title("drama2", genres: ["Драмы", "Военные"], minutes: 150, age: 16, year: 1998, countries: ["Россия"], kp: 8.3),
        title("soviet1", genres: ["Комедии"], minutes: 88, age: 0, year: 1973, countries: ["СССР"], kp: 8.6),
        title("scifi1", name: "Интерстеллар", genres: ["Фантастика", "Драмы"], minutes: 169, age: 16, year: 2014,
              kp: 8.6, directors: [nolan]),
        title("scifi2", name: "Начало", genres: ["Фантастика", "Боевики"], minutes: 148, age: 12, year: 2010, kp: 8.7,
              directors: [nolan], actors: [hardy]),
        title("action1", genres: ["Боевики"], minutes: 115, age: 18, year: 2015, kp: 7.6, actors: [hardy]),
        title("dune1", name: "Дюна", genres: ["Фантастика"], minutes: 155, age: 12, year: 2021, kp: 7.7, franchise: "dune"),
        title("dune2", name: "Дюна 2", genres: ["Фантастика"], minutes: 166, age: 12, year: 2024, kp: 8.0, franchise: "dune"),
        title("short1", genres: ["Драмы"], minutes: 70, age: 12, year: 2020, kp: 7.0),
        title("bridge", .series, name: "Мост", genres: ["Детективы", "Криминал"], minutes: 58, age: 18, year: 2011,
              countries: ["Швеция", "Дания"], kp: 8.0, watchAlso: ["killing", "hunt"],
              boards: [BoardRef(id: "noir", kind: .collection, name: "Северный нуар")]),
        title("killing", .series, name: "Убийство", genres: ["Детективы", "Драмы"], minutes: 55, age: 16, year: 2007,
              countries: ["Дания"], kp: 7.9, boards: [BoardRef(id: "noir", kind: .collection, name: "Северный нуар")]),
        title("hunt", .series, name: "Охота", genres: ["Детективы"], minutes: 50, age: 16, year: 2015, countries: ["Норвегия"],
              kp: 7.3),
        title("sitcom1", .series, genres: ["Комедии", "Ситкомы"], minutes: 22, age: 12, year: 2016, kp: 8.0),
        title("sitcom2", .series, genres: ["Комедии"], minutes: 25, age: 16, year: 2019, kp: 7.5),
        title("drama3", .series, genres: ["Драмы"], minutes: 48, age: 16, year: 2021, kp: 7.7),
        title("korean1", .series, genres: ["Драмы", "Мелодрамы"], minutes: 65, age: 12, year: 2022,
              countries: ["Корея Южная"], kp: 7.6),
        title("anime1", .anime, genres: ["Аниме", "Фэнтези"], minutes: 24, age: 12, year: 2020, countries: ["Япония"],
              kp: 8.2, series: true),
        title("show1", .show, genres: ["Реалити-шоу"], minutes: 45, age: 16, year: 2023, kp: 6.0),
        title("doc1", genres: ["Документальные"], minutes: 90, age: 12, year: 2021, kp: 7.5),
        title("zombie1", name: "Зомби по имени Шон", genres: ["Комедии", "Ужасы"], minutes: 99, age: 18, year: 2004,
              countries: ["Великобритания"], kp: 7.6),
    ]

    /// Scores for the catalogue: the ranking deliberately puts what a mood or company must avoid near the top.
    static let scores: [String: Double] = [
        "horror1": 1.00, "thriller1": 0.98, "comedy3": 0.96, "drama1": 0.94, "scifi1": 0.93, "zombie1": 0.92,
        "bridge": 0.91, "action1": 0.90, "drama2": 0.88, "horror2": 0.87, "scifi2": 0.86, "dune2": 0.85,
        "dune1": 0.84, "comedy2": 0.80, "thriller2": 0.79, "killing": 0.78, "drama3": 0.77, "hunt": 0.76,
        "korean1": 0.75, "sitcom1": 0.74, "comedy1": 0.72, "anime1": 0.71, "soviet1": 0.70, "family1": 0.68,
        "cartoon1": 0.66, "sitcom2": 0.64, "short1": 0.62, "doc1": 0.60, "cartoonSeries": 0.55, "show1": 0.50,
    ]

    static func catalogueContext(
        own: [String] = [], discover: [String] = [], impressions: [Impression] = [],
        settings: RecommenderSettings = RecommenderSettings()
    ) -> PickContext {
        context(catalogue, scores: scores, own: own, discover: discover, impressions: impressions, settings: settings)
    }

    static func request(_ intent: WatchIntent = .empty, pool: PickPool = .mix, shown: [String] = [], skips: Int = 0,
                        seed: UInt64 = 42, asked: Bool = false) -> PickRequest {
        PickRequest(intent: intent, pool: pool, shown: shown, skips: skips, seed: seed, askedQuestion: asked)
    }

    /// An intent the user typed: every set field is sure (so the clarifying question stays out of the way unless
    /// a test wants it).
    static func sure(_ intent: WatchIntent) -> WatchIntent {
        var result = intent
        for field in WatchIntent.Field.allCases { result.confidence[field] = 0.9 }
        return result
    }
}
