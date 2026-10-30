import Foundation
import Testing
@testable import RecommenderCore

@Suite("Candidate sources S1–S7 (§4.5)")
struct SourceTests {
    func core(_ titles: [TitleFeatures], _ signals: UserSignals, settings: RecommenderSettings = RecommenderSettings()) -> EngineCore {
        var timings: [String: Double] = [:]
        return EngineCore.build(Fixture.input(titles: titles, signals: signals, settings: settings), timings: &timings)
    }

    func ids(_ hits: [SourceHit], _ core: EngineCore) -> [String] { hits.map { core.titles[$0.title].id } }

    static func franchise(_ ids: [String]) -> (id: String, parts: [FranchisePart]) {
        ("f1", ids.enumerated().map { FranchisePart(titleId: $1, name: "Дюна \($0 + 1)", year: 2000 + $0, position: $0 + 1, isCurrent: false) })
    }

    @Test func graphSourceRanksNeighboursOfAnchors() throws {
        let titles = [
            Fixture.film("1", "Мост", watchAlso: ["2", "3"]), Fixture.film("2", "Убийство", watchAlso: ["4"]),
            Fixture.film("3", "Охота"), Fixture.film("4", "Далеко"), Fixture.film("5", "Чужой"),
            Fixture.film("6", "Второй", watchAlso: ["2"]),
        ]
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0), Fixture.watched("6", daysAgo: 0)]
        let core = core(titles, signals)
        let hits = GraphSource.hits(core)
        let order = ids(hits, core)
        // «Убийство» is linked from both anchors: it leads and earns the extra-anchor bonus.
        #expect(order.first == "2")
        #expect(!order.contains("1") && !order.contains("6"))
        #expect(!order.contains("5"))
        let top = try #require(hits.first)
        #expect(top.evidence.anchorIds.count == 2)
        #expect(top.evidence.path.count == 3)
    }

    @Test func nextFranchisePart() throws {
        let parts = Self.franchise(["1", "2", "3"])
        let titles = ["1", "2", "3"].map { Fixture.film($0, "Дюна", franchise: parts) }
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0)]
        let core = core(titles, signals)
        let hits = ContinuationSource.nextParts(core)
        #expect(ids(hits, core) == ["2"])
        let hit = try #require(hits.first)
        #expect(hit.evidence.anchorIds == ["1"])
        #expect(hit.evidence.board?.kind == .franchise)

        // «Не моё» on part one stops the franchise.
        var disliked = UserSignals()
        disliked.ratings = [ExplicitRating(titleId: "1", level: -2, source: .app, createdAt: Fixture.now)]
        #expect(ContinuationSource.nextParts(self.core(titles, disliked)).isEmpty)
    }

    @Test func newSeasonOfWatchedSeriesComesBack() throws {
        let titles = [Fixture.series("s", episodes: 30, seasons: 3, lastEpisodeAt: Fixture.now - 5 * Fixture.day)]
        var signals = UserSignals()
        signals.accountList = [AccountListItem(titleId: "s", watched: true, lastActivityAt: Fixture.now - 200 * Fixture.day, season: 2, episode: 10)]
        let core = core(titles, signals)
        #expect(core.newSeasons[0] == .some(2))
        // Watched, yet eligible: the new season is the exception to «watched».
        #expect(core.isEligible(0))
        let hit = try #require(ContinuationSource.newSeasonHits(core).first)
        #expect(hit.evidence.count == 2)

        // A season that came out before the user's last activity is old news.
        var recent = UserSignals()
        recent.accountList = [AccountListItem(titleId: "s", watched: true, lastActivityAt: Fixture.now - Fixture.day, season: 2)]
        #expect(self.core(titles, recent).newSeasons.isEmpty)
    }

    @Test func intentSourceUsesFoldersAndAccountList() throws {
        let titles = ["1", "2", "3", "4"].map { Fixture.film($0) } + [Fixture.series("5")]
        var signals = UserSignals()
        signals.bookmarks = [BookmarkItem(titleId: "1", folder: "Посмотреть позже"), BookmarkItem(titleId: "1", folder: "На выходные")]
        signals.accountList = [
            AccountListItem(titleId: "2", watched: false, lastActivityAt: Fixture.now - 3 * Fixture.day),
            AccountListItem(titleId: "3", watched: true, lastActivityAt: Fixture.now),
        ]
        signals.followed = ["5"]
        signals.sessions = [Fixture.partial("4", fraction: 0.4, daysAgo: 1)]
        signals.bookmarks.append(BookmarkItem(titleId: "4", folder: "На выходные"))
        let core = core(titles, signals)
        let hits = IntentSource.hits(core)
        let byId = Dictionary(uniqueKeysWithValues: hits.map { (core.titles[$0.title].id, $0) })
        #expect(byId["1"]?.evidence.folder == "На выходные")
        #expect(byId["1"]?.evidence.origin == .bookmark)
        #expect(byId["2"]?.evidence.origin == .accountList)
        #expect(byId["5"]?.evidence.origin == .followed)
        // Watched and started titles are not «можно начать».
        #expect(byId["3"] == nil)
        #expect(byId["4"] == nil)
    }

    @Test func affinityAndPeople() throws {
        let fincher = Fixture.person("f", "Дэвид Финчер")
        let titles = [
            Fixture.film("1", genres: ["Триллеры"], directors: [fincher]),
            Fixture.film("2", genres: ["Триллеры"], directors: [fincher]),
            Fixture.film("3", genres: ["Триллеры"], directors: [fincher]),
            Fixture.film("4", genres: ["Триллеры"]),
            Fixture.film("5", genres: ["Мелодрамы"], countries: ["Франция"]),
        ]
        var signals = UserSignals()
        signals.ratings = [
            ExplicitRating(titleId: "1", level: 1, source: .app, createdAt: Fixture.now),
            ExplicitRating(titleId: "2", level: 1, source: .app, createdAt: Fixture.now),
        ]
        let core = core(titles, signals)
        let affinity = ids(AffinitySource.hits(core), core)
        #expect(affinity.first == "3")
        #expect(affinity.contains("4"))
        #expect(!affinity.contains("5"))
        let favourites = PeopleSource.favourites(core)
        #expect(favourites.first?.person.id == "f")
        #expect(favourites.first?.positiveTitles == 2)
        let people = PeopleSource.hits(core)
        #expect(ids(people, core) == ["3"])
        #expect(people.first?.evidence.board?.kind == .director)

        // One liked film isn't a pattern: no person source.
        var once = UserSignals()
        once.ratings = [ExplicitRating(titleId: "1", level: 2, source: .app, createdAt: Fixture.now)]
        #expect(PeopleSource.favourites(self.core(titles, once)).isEmpty)
    }

    @Test func qualityFreshListsAndNewReleases() throws {
        let list = BoardRef(id: "l", kind: .list, name: "Лучшие триллеры", size: 50)
        var ranked = list
        ranked.rank = 3
        let titles = [
            Fixture.film("1", genres: ["Триллеры"]), Fixture.film("2", genres: ["Триллеры"]),
            Fixture.film("3", genres: ["Триллеры"], boards: [ranked]),
            Fixture.film("4", genres: ["Триллеры"], year: 2026, releasedAt: Fixture.now - 20 * Fixture.day),
            Fixture.film("5", genres: ["Мелодрамы"], boards: [ranked]),
        ]
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0), Fixture.watched("2", daysAgo: 0)]
        let core = core(titles, signals)
        let hits = QualityFreshSource.hits(core)
        let byId = Dictionary(uniqueKeysWithValues: hits.map { (core.titles[$0.title].id, $0) })
        #expect(byId["3"]?.evidence.board?.rank == 3)
        #expect(byId["4"] != nil)
        // The list alone isn't enough: the title must fit the taste.
        #expect(byId["5"] == nil)
    }

    @Test func coldStartFallsBackToPopular() {
        let titles = [Fixture.film("1", kpVotes: 500_000), Fixture.film("2", kpVotes: 50)]
        let core = core(titles, UserSignals())
        let hits = QualityFreshSource.hits(core)
        #expect(ids(hits.sorted { $0.score > $1.score }, core).first == "1")
    }

    @Test func explorationFindsNewTerritory() {
        let titles = [
            Fixture.film("1", genres: ["Драмы"], countries: ["США"]), Fixture.film("2", genres: ["Драмы"], countries: ["США"]),
            Fixture.film("3", genres: ["Драмы"], countries: ["Южная Корея"], kp: 8.4, kpVotes: 200_000),
            Fixture.film("4", genres: ["Ужасы"], countries: ["Япония"], kp: 8.4, kpVotes: 200_000),
            Fixture.film("5", genres: ["Ужасы"], countries: ["США"]),
            Fixture.film("6", genres: ["Драмы"], countries: ["Индия"], kp: 6.0, kpVotes: 1000),
        ]
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0), Fixture.watched("2", daysAgo: 0)]
        signals.ratings = [ExplicitRating(titleId: "5", level: -2, source: .app, createdAt: Fixture.now)]
        let core = core(titles, signals)
        let found = ids(ExplorationSource.hits(core), core)
        // Korea is new and well rated; horror is disliked; the Indian drama isn't rated well enough.
        #expect(found == ["3"])
    }
}
