#if DEBUG
    import Foundation
    import RecommenderCore

    /// Debug builds check the recommender's readings of the site's text once at start (the app has no test target;
    /// the same checks run standalone too). A failed one is printed with what came out instead.
    enum RecSelfCheck {
        static func report() {
            let failures = failures()
            if !failures.isEmpty {
                print("RecSelfCheck: \(failures.count) failed\n" + failures.joined(separator: "\n"))
            }
        }

        static func failures() -> [String] {
            var failures: [String] = []
            func check<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
                if actual != expected { failures.append("✗ \(label): \(actual) ≠ \(expected)") }
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            func day(_ year: Int, _ month: Int, _ day: Int) -> Date? {
                calendar.date(from: DateComponents(year: year, month: month, day: day))
            }
            let now = day(2026, 10, 30) ?? Date(timeIntervalSince1970: 1_793_318_400)

            // Card captions
            let simple = CardCaptionParser.parse("2019, США, Драмы")
            check(simple.year, 2019, "caption year")
            check(simple.countries, ["США"], "caption countries")
            check(simple.genre, "Драмы", "caption genre")
            let running = CardCaptionParser.parse("2011 - ..., Великобритания, США, Драмы")
            check(running.year, 2011, "running year")
            check(running.isOngoing, true, "running ongoing")
            check(running.endYear, nil, "running end")
            check(running.countries, ["Великобритания", "США"], "running countries")
            let finished = CardCaptionParser.parse("2011-2019, Россия, Комедии")
            check(finished.endYear, 2019, "finished end")
            check(finished.isOngoing, false, "finished ongoing")
            check(CardCaptionParser.parse("2019, Комедии").genre, "Комедии", "year and genre")
            check(CardCaptionParser.parse("2019, Комедии").countries, [], "year and genre: no country")
            check(CardCaptionParser.parse("2019, США").countries, ["США"], "year and country")
            check(CardCaptionParser.parse("2019, США").genre, nil, "year and country: no genre")
            check(CardCaptionParser.parse("США, Драмы").year, nil, "no year")
            check(CardCaptionParser.parse("США, Драмы").countries, ["США"], "no year: country")
            check(CardCaptionParser.parse("1995, Южная Корея, Документальные").genre, "Документальные", "adjective genre")
            check(CardCaptionParser.parse(nil), .empty, "nil caption")
            check(CardCaptionParser.parse("  "), .empty, "blank caption")

            // Paths
            check(RecParsing.titleId(fromPath: "films/drama/12345-name.html"), "12345", "title id")
            check(RecParsing.titleId(fromPath: "series/comedy/678-x-y.html"), "678", "series id")
            check(RecParsing.titleId(fromPath: "films/drama/"), nil, "no title id in a genre path")
            check(RecParsing.titleId(fromPath: "films/drama/name-12.html"), nil, "no number first")
            check(RecParsing.kind(fromPath: "animation/x/1-a.html"), .anime, "anime kind")
            check(RecParsing.kind(fromPath: "cartoons/x/1-a.html"), .cartoon, "cartoon kind")
            check(RecParsing.kind(fromPath: "show/x/1-a.html"), .show, "show kind")
            check(RecParsing.genreSlug(fromPath: "films/drama/1-a.html"), "drama", "genre slug")
            check(RecParsing.genreSlug(fromGenreLink: "films/drama/"), "drama", "genre link slug")
            check(RecParsing.personKey(fromPath: "person/12345-ivan-ivanov/"), "12345-ivan-ivanov", "person key")

            // Numbers
            check(RecParsing.count("1.2M"), 1_200_000, "votes M")
            check(RecParsing.count("12.3K"), 12300, "votes K")
            check(RecParsing.count("12 345"), 12345, "votes spaced")
            check(RecParsing.count("987"), 987, "votes plain")
            check(RecParsing.count("1B"), 1_000_000_000, "votes B")
            check(RecParsing.count(""), nil, "votes empty")
            check(RecParsing.age("18+"), 18, "age 18")
            check(RecParsing.age("0+"), 0, "age 0")
            check(RecParsing.age(nil), nil, "age none")
            check(RecParsing.year("15 октября 2019 года"), 2019, "year in a date")
            check(RecParsing.episodesLeft("смотреть ещё 12 серий в 2 сезоне"), 12, "episodes left")
            check(RecParsing.minutes("2 ч 5 мин"), 125, "hours and minutes")
            check(RecParsing.minutes("120 мин."), 120, "minutes")

            // External ids
            check(RecParsing.kinopoiskId(fromLink: "https://www.kinopoisk.ru/film/326/"), 326, "kp film")
            check(RecParsing.kinopoiskId(fromLink: "https://www.kinopoisk.ru/series/464963/"), 464_963, "kp series")
            check(RecParsing.kinopoiskId(fromLink: "https://www.kinopoisk.ru/name/1/"), nil, "kp person")
            check(RecParsing.imdbId(fromLink: "https://www.imdb.com/title/tt0111161/"), "tt0111161", "imdb")

            // Dates
            check(RecParsing.date("15 октября 2019 года", now: now, calendar: calendar), day(2019, 10, 15), "date words")
            check(RecParsing.date("3 мая 2020", now: now, calendar: calendar), day(2020, 5, 3), "date May")
            check(RecParsing.date("3 марта 2020", now: now, calendar: calendar), day(2020, 3, 3), "date March")
            check(RecParsing.date("15.10.2019", now: now, calendar: calendar), day(2019, 10, 15), "date dots")
            check(RecParsing.date("2019-10-15", now: now, calendar: calendar), day(2019, 10, 15), "date ISO")
            check(RecParsing.date("сегодня", now: now, calendar: calendar), calendar.startOfDay(for: now), "today")
            check(RecParsing.date("вчера, 12:00", now: now, calendar: calendar), day(2026, 10, 29), "yesterday")
            check(RecParsing.date("скоро", now: now, calendar: calendar), nil, "no date")

            let schedule = RecParsing.schedule([
                ("1 сезон 1 серия", "1 января 2020"),
                ("1 сезон 2 серия", "8 января 2020"),
                ("2 сезон 1 серия", "1 января 2099"),
            ], now: now, calendar: calendar)
            check(schedule?.released, 2, "schedule released")
            check(schedule?.seasons, 1, "schedule seasons")
            check(schedule?.lastEpisodeAt, day(2020, 1, 8), "schedule last")
            check(RecParsing.schedule([("Спецвыпуск", "1 января 2020")], now: now, calendar: calendar), nil, "no schedule")

            // Names
            check(RecParsing.normalized("Мост (2011)"), "мост 2011", "normalized")
            check(RecParsing.normalized("Ёлки"), "елки", "normalized ё")
            check(RecParsing.ftsQuery("Мост, 2"), "\"мост\"* \"2\"*", "fts query")
            check(RecParsing.ftsQuery("«»"), nil, "fts empty")
            check(RecParsing.stem("Нолана"), "нолан", "stem")
            check(RecParsing.stem("Ди"), "ди", "short stem")
            check(RecParsing.fnv1a(""), 0xCBF2_9CE4_8422_2325, "fnv empty")
            check(RecParsing.fnv1a("a"), 0xAF63_DC4C_8601_EC8C, "fnv a")

            return failures
        }
    }
#endif
