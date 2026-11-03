import Foundation
import Testing
@testable import RecommenderCore

@Suite("Taste profile (§4.3)")
struct ProfileTests {
    /// A title whose only features are its genres (and a director), so affinities can be checked by hand.
    func bare(_ id: String, genres: [String], directors: [PersonRef] = []) -> TitleFeatures {
        TitleFeatures(id: id, path: "/\(id)", level: .page, kind: nil, name: "Т\(id)", genres: genres, directors: directors, fetchedAt: 0)
    }

    func core(_ titles: [TitleFeatures], _ signals: UserSignals, settings: RecommenderSettings = RecommenderSettings()) -> EngineCore {
        var timings: [String: Double] = [:]
        return EngineCore.build(Fixture.input(titles: titles, signals: signals, settings: settings), timings: &timings)
    }

    func affinity(_ core: EngineCore, _ key: FeatureKey) -> Double {
        core.profile.affinity(of: core.table.id(of: key))
    }

    @Test func smoothedAffinity() {
        let titles = [bare("1", genres: ["Детективы"]), bare("2", genres: ["Детективы"]), bare("3", genres: ["Ужасы"]), bare("4", genres: ["Ужасы", "Детективы"])]
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0), Fixture.watched("2", daysAgo: 0)]
        signals.ratings = [ExplicitRating(titleId: "3", level: -2, source: .app, createdAt: Fixture.now)]
        let core = core(titles, signals)
        // A = Σw / (Σ|w| + 2)
        #expect(abs(affinity(core, FeatureKey(.genre, "Детективы")) - 1.6 / 3.6) < 1e-12)
        #expect(abs(affinity(core, FeatureKey(.genre, "ужасы")) - (-2.0 / 4.0)) < 1e-12)
        // Unknown features have no affinity.
        #expect(affinity(core, FeatureKey(.genre, "Мюзиклы")) == 0)
    }

    @Test func idfAndTitleAffinity() throws {
        let titles = [bare("1", genres: ["Детективы"]), bare("2", genres: ["Детективы"]), bare("3", genres: ["Ужасы"]), bare("4", genres: ["Ужасы", "Детективы"])]
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0), Fixture.watched("2", daysAgo: 0)]
        signals.ratings = [ExplicitRating(titleId: "3", level: -2, source: .app, createdAt: Fixture.now)]
        let core = core(titles, signals)
        let detective = try #require(core.table.id(of: FeatureKey(.genre, "детективы")))
        let horror = try #require(core.table.id(of: FeatureKey(.genre, "ужасы")))
        // Detectives on 3 of 4 titles, horror on 2.
        #expect(abs(core.table.idf[detective] - (log(5.0 / 4.0) + 1)) < 1e-12)
        #expect(abs(core.table.idf[horror] - (log(5.0 / 3.0) + 1)) < 1e-12)
        // aff(t): the genres as one group with g = 1 — 0.6·best + 0.4·idf-weighted mean — over (g + c).
        let mixed = try #require(core.titleIndex["4"])
        let a = core.profile.affinity
        let c = Weights.default.affinityTitleSmoothing
        let mean = (core.table.idf[detective] * a[detective] + core.table.idf[horror] * a[horror])
            / (core.table.idf[detective] + core.table.idf[horror])
        let best = max(a[detective], a[horror])
        #expect(abs(core.profile.titleAffinity[mixed] - (0.6 * best + 0.4 * mean) / (1 + c)) < 1e-12)
        let single = try #require(core.titleIndex["1"])
        #expect(abs(core.profile.titleAffinity[single] - a[detective] / (1 + c)) < 1e-12)
    }

    /// A fully read page lists people and collections the user never met: they mustn't drag its match below a bare
    /// card with the same liked genre.
    @Test func unknownFeaturesDontDilute() throws {
        let stranger = Fixture.person("x", "Незнакомый режиссёр")
        let titles = [
            bare("1", genres: ["Детективы"]), bare("2", genres: ["Детективы"]),
            bare("card", genres: ["Детективы"]),
            bare("page", genres: ["Детективы"], directors: [stranger]),
        ]
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0), Fixture.watched("2", daysAgo: 0)]
        let core = core(titles, signals)
        let card = try #require(core.titleIndex["card"])
        let page = try #require(core.titleIndex["page"])
        #expect(core.profile.titleAffinity[card] > 0)
        #expect(abs(core.profile.titleAffinity[page] - core.profile.titleAffinity[card]) < 1e-12)
    }

    @Test func personNeedsTwoDislikesToSinkBelowFloor() {
        let director = Fixture.person("p1", "Режиссёр Один")
        let other = Fixture.person("p2", "Режиссёр Два")
        let titles = [
            bare("1", genres: ["Драмы"], directors: [director]),
            bare("2", genres: ["Драмы"], directors: [other]), bare("3", genres: ["Драмы"], directors: [other]),
        ]
        var signals = UserSignals()
        signals.ratings = [
            ExplicitRating(titleId: "1", level: -2, source: .app, createdAt: Fixture.now),
            ExplicitRating(titleId: "2", level: -2, source: .app, createdAt: Fixture.now),
            ExplicitRating(titleId: "3", level: -2, source: .app, createdAt: Fixture.now),
        ]
        let core = core(titles, signals)
        #expect(affinity(core, FeatureKey(.director, "p1")) == -0.2)
        #expect(abs(affinity(core, FeatureKey(.director, "p2")) - (-4.0 / 6.0)) < 1e-12)
    }

    @Test func overrides() throws {
        let titles = [bare("1", genres: ["Драмы"]), bare("2", genres: ["Комедии"]), bare("3", genres: ["Ужасы"]), bare("4", genres: ["Мюзиклы"]), bare("5", genres: ["Вестерны"])]
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0)]
        signals.overrides = [
            TasteOverride(feature: FeatureKey(.genre, "Драмы"), mode: .mute, until: Fixture.now + 60 * Fixture.day),
            TasteOverride(feature: FeatureKey(.genre, "КОМЕДИИ"), mode: .pin),
            TasteOverride(feature: FeatureKey(.genre, "Ужасы"), mode: .exclude),
            TasteOverride(feature: FeatureKey(.genre, "Мюзиклы"), mode: .more),
            // Expired: ignored.
            TasteOverride(feature: FeatureKey(.genre, "Вестерны"), mode: .pin, until: Fixture.now - 1),
        ]
        let core = core(titles, signals)
        #expect(affinity(core, FeatureKey(.genre, "Драмы")) == -0.5)
        #expect(affinity(core, FeatureKey(.genre, "Комедии")) == 0.7)
        #expect(affinity(core, FeatureKey(.genre, "Мюзиклы")) == 0.5)
        #expect(affinity(core, FeatureKey(.genre, "Вестерны")) == 0)
        let horror = try #require(core.titleIndex["3"])
        #expect(core.filterReason[horror] == .excludedFeature)
    }

    @Test func anchorsAndSeeds() {
        let titles = (1...8).map { bare("\($0)", genres: ["Драмы"]) }
        var signals = UserSignals()
        signals.sessions = (1...3).map { Fixture.watched("\($0)", daysAgo: 0) }
        // An old completion: positive but below the anchor threshold.
        signals.sessions.append(Fixture.watched("4", daysAgo: 400))
        signals.ratings = [
            ExplicitRating(titleId: "5", level: 2, source: .app, createdAt: Fixture.now),
            ExplicitRating(titleId: "6", level: -2, source: .app, createdAt: Fixture.now),
        ]
        signals.feedback = [Feedback(titleId: "3", kind: .notSeed, createdAt: Fixture.now)]
        let core = core(titles, signals)
        #expect(core.profile.anchors.map(\.id) == ["5", "1", "2"])
        #expect(core.profile.negativeAnchors.map(\.id) == ["6"])
        // Fewer than five anchors: every positive title seeds the graph, old taste included.
        #expect(core.profile.seeds.map(\.id) == ["5", "1", "2", "4"])
    }

    @Test func summaryNamesAndShares() {
        let titles = [
            Fixture.film("1", genres: ["Детективы"], countries: ["Швеция"], year: 2014),
            Fixture.film("2", genres: ["Детективы"], countries: ["Швеция"], year: 2016),
            Fixture.series("3", genres: ["Детективы"], countries: ["Дания"], year: 2012),
            Fixture.film("4", genres: ["Ужасы"], countries: ["США"], year: 1999),
            Fixture.film("5", genres: ["Ужасы"], countries: ["США"], year: 1998),
        ]
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0), Fixture.watched("2", daysAgo: 0)]
        signals.accountList = [AccountListItem(titleId: "3", watched: true, lastActivityAt: Fixture.now)]
        signals.ratings = [
            ExplicitRating(titleId: "4", level: -2, source: .app, createdAt: Fixture.now),
            ExplicitRating(titleId: "5", level: -2, source: .app, createdAt: Fixture.now),
        ]
        let summary = core(titles, signals).profile.summary
        let names = summary.top.map(\.name)
        #expect(names.first == "Детективы")
        #expect(names.contains("2010-е"))
        #expect(names.contains("Швеция"))
        #expect(summary.disliked.map(\.name).contains("Ужасы"))
        #expect(summary.positiveCount == 3)
        #expect(summary.negativeCount == 2)
        #expect(abs(summary.seriesShare - 1.0 / 3.0) < 1e-12)
    }

    @Test func featureExtraction() throws {
        let title = Fixture.film(
            "1", genres: ["Драмы", "Драмы", "Криминал", "Зарубежные"], countries: ["Франция"], year: 1994, minutes: 133,
            directors: [Fixture.person("d", "Люк Бессон")], actors: (1...7).map { Fixture.person("a\($0)", "Актёр \($0)") },
            boards: [BoardRef(id: "c1", kind: .collection, name: "Нуар"), BoardRef(id: "l1", kind: .list, name: "Топ", rank: 3)],
        )
        let table = FeatureTable(titles: [title], weights: .default)
        let keys = Set(table.ofTitle[0].map { table.keys[$0] })
        #expect(keys.contains(FeatureKey(.genre, "драмы")))
        // «Зарубежные» is a section of the site's catalogue, not a genre of taste.
        #expect(!keys.contains(FeatureKey(.genre, "зарубежные")))
        #expect(keys.contains(FeatureKey(.decade, "1990")))
        #expect(keys.contains(FeatureKey(.duration, "f150")))
        #expect(keys.contains(FeatureKey(.kind, "film")))
        #expect(keys.contains(FeatureKey(.collection, "c1")))
        #expect(keys.contains(FeatureKey(.list, "l1")))
        // Top five actors only, and genres once.
        #expect(keys.filter { $0.group == .actor }.count == 5)
        #expect(keys.filter { $0.group == .genre }.count == 2)
        let decade = try #require(table.id(of: FeatureKey(.decade, "1990")))
        #expect(table.names[decade] == "1990-е")
        #expect(table.primaryGenre[0] == table.id(of: FeatureKey(.genre, "Драмы")))
    }
}
