import Foundation
import Testing
@testable import RecommenderCore

@Suite("Signals → weights (§4.2)")
struct SignalWeighterTests {
    let weights = Weights.default

    func weigh(
        _ signals: UserSignals, titles: [TitleFeatures], settings: RecommenderSettings = RecommenderSettings(),
    ) -> [String: TitleSignal] {
        SignalWeighter.weigh(
            signals, titles: Dictionary(titles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            settings: settings, weights: weights, context: Fixture.context(),
        )
    }

    func decay(_ days: Double) -> Double { Decay.implicit(1, ageDays: days, weights: weights) }

    @Test func dualMemoryDecay() {
        #expect(decay(0) == 1)
        // 0.7·2^(−180/180) + 0.3·2^(−180/14)
        #expect(abs(decay(180) - (0.35 + 0.3 * pow(2, -180.0 / 14))) < 1e-12)
        #expect(abs(decay(14) - (0.7 * pow(2, -14.0 / 180) + 0.15)) < 1e-12)
        // Long memory: a year on, taste still counts (≈ 17 %).
        #expect(decay(365) > 0.16 && decay(365) < 0.18)
        #expect(abs(Decay.explicit(2, ageDays: 730, weights: weights) - 1) < 1e-12)
        #expect(Decay.implicit(1, ageDays: -5, weights: weights) == 1)
    }

    @Test func filmCompletedMostlyAndDropped() throws {
        let titles = (1...5).map { Fixture.film("\($0)") }
        var signals = UserSignals()
        signals.sessions = [
            Fixture.watched("1", daysAgo: 0),
            Fixture.partial("2", fraction: 0.6, daysAgo: 0),
            Fixture.partial("3", fraction: 0.6, daysAgo: 1), Fixture.partial("3", fraction: 0.7, daysAgo: 0),
            Fixture.partial("4", fraction: 0.3, daysAgo: 0),
            Fixture.partial("5", fraction: 0.1, daysAgo: 20),
        ]
        let result = weigh(signals, titles: titles)
        let completed = try #require(result["1"])
        #expect(completed.weight == 0.8)
        #expect(completed.state == .seen)
        #expect(completed.finished)
        #expect(completed.completedAt == Fixture.now)
        #expect(try #require(result["2"]).weight == 0.3)
        #expect(try #require(result["2"]).state == .started)
        #expect(try #require(result["3"]).weight == 0.5)
        #expect(try #require(result["4"]).weight == 0)
        #expect(try #require(result["4"]).state == .started)
        let dropped = try #require(result["5"])
        #expect(abs(dropped.weight - (-0.4 * decay(20))) < 1e-12)
    }

    @Test func accidentalClickIsIgnored() {
        var signals = UserSignals()
        let end = Fixture.now
        signals.sessions = [WatchSession(
            titleId: "1", season: nil, episode: nil, startedAt: end - 60, endedAt: end, fromPosition: 0, toPosition: 60,
            duration: 6000, completed: false,
        )]
        let result = weigh(signals, titles: [Fixture.film("1")])
        #expect(result["1"]?.weight == 0)
        #expect(result["1"]?.hasLocalData == false)
        #expect(result["1"]?.state == WatchState.none)
    }

    @Test func rewatchAddsHalf() {
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 30), Fixture.watched("1", daysAgo: 0)]
        let result = weigh(signals, titles: [Fixture.film("1")])
        #expect(abs((result["1"]?.weight ?? 0) - 1.3) < 1e-12)
        // The same viewing logged twice within hours is not a rewatch.
        var twice = UserSignals()
        twice.sessions = [Fixture.watched("1", daysAgo: 0.05), Fixture.watched("1", daysAgo: 0)]
        #expect(weigh(twice, titles: [Fixture.film("1")])["1"]?.weight == 0.8)
    }

    @Test func seriesProgressBingeAndNextSeason() throws {
        let titles = [Fixture.series("s1", episodes: 10), Fixture.series("s2", episodes: 10), Fixture.series("s3", episodes: 20, seasons: 2)]
        var signals = UserSignals()
        // s1: six episodes, one a day — e = 0.6 → 0.5 + 0.3.
        signals.sessions += (1...6).map { Fixture.episode("s1", season: 1, episode: $0, daysAgo: Double(6 - $0)) }
        // s2: three episodes in one evening — +0.2 for the binge.
        signals.sessions += (1...3).map { Fixture.episode("s2", season: 1, episode: $0, daysAgo: 0.01 * Double(4 - $0)) }
        // s3: season one finished, season two begun — +0.3.
        signals.sessions += (1...3).map { Fixture.episode("s3", season: 1, episode: $0, daysAgo: Double(10 - $0)) }
        signals.sessions.append(Fixture.episode("s3", season: 2, episode: 1, daysAgo: 0))
        let result = weigh(signals, titles: titles)
        #expect(abs(try #require(result["s1"]).weight - 0.8) < 1e-12)
        let binge = try #require(result["s2"])
        #expect(abs(binge.weight - (0.5 + 0.5 * 0.3 + 0.2) * decay(0.01)) < 1e-9)
        let nextSeason = try #require(result["s3"])
        #expect(abs(nextSeason.weight - (0.5 + 0.5 * 0.2 + 0.3)) < 1e-12)
        #expect(nextSeason.lastSeason == 2)
        #expect(nextSeason.resume == EpisodeRef(season: 2, episode: 2, isNext: true))
        #expect(nextSeason.state == .started)
    }

    @Test func seriesDroppedAndMiniSeriesFinished() throws {
        let titles = [Fixture.series("drop", episodes: 10), Fixture.series("mini", episodes: 2)]
        var signals = UserSignals()
        signals.sessions = [
            Fixture.episode("drop", season: 1, episode: 1, daysAgo: 40),
            Fixture.episode("mini", season: 1, episode: 1, daysAgo: 1), Fixture.episode("mini", season: 1, episode: 2, daysAgo: 0),
        ]
        let result = weigh(signals, titles: titles)
        #expect(abs(try #require(result["drop"]).weight - (-0.4 * decay(40))) < 1e-12)
        let mini = try #require(result["mini"])
        #expect(mini.weight == 1.0)
        #expect(mini.state == .seen)
    }

    @Test func accountListWithoutLocalData() throws {
        let titles = [
            Fixture.film("w"), Fixture.film("r"), Fixture.series("stale"), Fixture.film("old"), Fixture.series("deep"),
            Fixture.series("queued"),
        ]
        var signals = UserSignals()
        signals.accountList = [
            AccountListItem(titleId: "w", watched: true, lastActivityAt: Fixture.now),
            AccountListItem(titleId: "r", watched: false, lastActivityAt: Fixture.now - 10 * Fixture.day),
            AccountListItem(titleId: "stale", watched: false, lastActivityAt: Fixture.now - 100 * Fixture.day, season: 1, episode: 2),
            AccountListItem(titleId: "old", watched: true, lastActivityAt: nil),
            AccountListItem(titleId: "deep", watched: false, lastActivityAt: Fixture.now - 200 * Fixture.day, season: 2, episode: 3),
            AccountListItem(titleId: "queued", watched: false, lastActivityAt: Fixture.now - 5 * Fixture.day),
        ]
        let result = weigh(signals, titles: titles)
        let watched = try #require(result["w"])
        #expect(watched.weight == 0.6)
        #expect(watched.state == .seen)
        #expect(watched.finished)
        // A film in «Досмотреть» was played: it counts toward taste and stays out of the recommendations.
        let recent = try #require(result["r"])
        #expect(abs(recent.weight - 0.45 * decay(10)) < 1e-12)
        #expect(!recent.accountListNoProgress)
        #expect(recent.state == .started)
        // A series with no place yet is waiting to be started: «Можно начать».
        let queued = try #require(result["queued"])
        #expect(queued.accountListNoProgress)
        #expect(queued.intent == 0.3)
        #expect(queued.state == WatchState.none)
        #expect(abs(try #require(result["deep"]).weight - 0.6 * decay(200)) < 1e-12)
        let stale = try #require(result["stale"])
        #expect(abs(stale.weight - (-0.2 * decay(100))) < 1e-12)
        #expect(stale.state == .started)
        #expect(stale.resume == EpisodeRef(season: 1, episode: 2, isNext: false))
        #expect(abs(try #require(result["old"]).weight - 0.6 * decay(180)) < 1e-12)
    }

    @Test func bookmarkFolderSemantics() throws {
        let titles = ["a", "b", "c"].map { Fixture.film($0) }
        var signals = UserSignals()
        signals.bookmarks = [
            BookmarkItem(titleId: "a", folder: "Любимые фильмы"),
            BookmarkItem(titleId: "b", folder: "Посмотреть потом"),
            BookmarkItem(titleId: "c", folder: "На выходные"),
        ]
        let result = weigh(signals, titles: titles)
        let loved = try #require(result["a"])
        #expect(loved.weight == 0.8)
        #expect(loved.inLovedFolder)
        #expect(loved.isLoved)
        #expect(loved.intent == 0.3)
        let later = try #require(result["b"])
        #expect(later.weight == 0)
        #expect(later.intent == 0.3)
        #expect(try #require(result["c"]).weight == 0.15)
        // Bookmarks off in settings: nothing.
        var off = RecommenderSettings()
        off.useBookmarks = false
        #expect(weigh(signals, titles: titles).count == 3)
        #expect(weigh(signals, titles: titles, settings: off).isEmpty)
    }

    @Test func followedSeries() throws {
        var signals = UserSignals()
        signals.followed = ["s"]
        let followed = try #require(weigh(signals, titles: [Fixture.series("s")])["s"])
        #expect(followed.weight == 0.3)
        #expect(followed.intent == 0.3)
        #expect(followed.followed)
    }

    @Test func notMeZeroesImplicitSignals() throws {
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0)]
        signals.feedback = [Feedback(titleId: "1", kind: .notMe, createdAt: Fixture.now)]
        let result = try #require(weigh(signals, titles: [Fixture.film("1")])["1"])
        #expect(result.weight == 0)
        #expect(result.state == WatchState.none)
        #expect(!result.finished)
        #expect(result.exclusion == nil)
    }

    @Test func droppedIsWeakMinusAndExcluded() throws {
        var signals = UserSignals()
        signals.feedback = [Feedback(titleId: "1", kind: .dropped, createdAt: Fixture.now - 2 * Fixture.day)]
        let result = try #require(weigh(signals, titles: [Fixture.film("1")])["1"])
        #expect(abs(result.weight - (-0.4 * decay(2))) < 1e-12)
        #expect(result.exclusion == .dropped)
    }

    @Test func explicitOverridesImplicitAndExcludesDislikes() throws {
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0), Fixture.watched("2", daysAgo: 0)]
        signals.ratings = [
            ExplicitRating(titleId: "1", level: 2, source: .app, createdAt: Fixture.now),
            ExplicitRating(titleId: "2", level: -2, source: .app, createdAt: Fixture.now),
            ExplicitRating(titleId: "3", level: 1, source: .kinopoisk, createdAt: Fixture.now - 730 * Fixture.day),
            // The latest rating wins.
            ExplicitRating(titleId: "4", level: -2, source: .app, createdAt: Fixture.now - 10),
            ExplicitRating(titleId: "4", level: 1, source: .app, createdAt: Fixture.now),
        ]
        let result = weigh(signals, titles: ["1", "2", "3", "4"].map { Fixture.film($0) })
        #expect(try #require(result["1"]).weight == 2)
        let disliked = try #require(result["2"])
        #expect(disliked.weight == -2)
        #expect(disliked.exclusion == .notForMe)
        #expect(disliked.isDisliked)
        let imported = try #require(result["3"])
        #expect(abs(imported.weight - 0.5) < 1e-12)
        #expect(imported.state == .seen)
        #expect(try #require(result["4"]).weight == 1)
        #expect(try #require(result["4"]).exclusion == nil)
    }

    @Test func weightIsClamped() throws {
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 1), Fixture.watched("1", daysAgo: 0)]
        signals.bookmarks = [BookmarkItem(titleId: "1", folder: "Шедевры")]
        signals.followed = ["1"]
        let result = try #require(weigh(signals, titles: [Fixture.film("1")])["1"])
        #expect(result.weight == 2)
    }

    @Test func onboardingGroupPickFades() throws {
        var signals = UserSignals()
        signals.ratings = [ExplicitRating(titleId: "1", level: 0.6, source: .onboarding, createdAt: Fixture.now - 30 * Fixture.day)]
        let result = try #require(weigh(signals, titles: [Fixture.film("1")])["1"])
        #expect(abs(result.weight - 0.3) < 1e-12)
        #expect(result.explicitLevel == nil)
        #expect(result.state == WatchState.none)
    }

    @Test func feedbackExpiry() throws {
        var signals = UserSignals()
        signals.feedback = [
            Feedback(titleId: "past", kind: .notToday, createdAt: Fixture.now - 10 * Fixture.day),
            Feedback(titleId: "now", kind: .notToday, createdAt: Fixture.now - Fixture.day),
            Feedback(titleId: "until", kind: .hidden, createdAt: Fixture.now - Fixture.day, until: Fixture.now - 1),
            Feedback(titleId: "seed", kind: .notSeed, createdAt: Fixture.now),
        ]
        signals.sessions = [Fixture.watched("seed", daysAgo: 0)]
        let result = weigh(signals, titles: ["past", "now", "until", "seed"].map { Fixture.film($0) })
        #expect(result["past"] == nil)
        #expect(try #require(result["now"]).exclusion == .notToday)
        #expect(result["until"] == nil)
        let seed = try #require(result["seed"])
        #expect(seed.weight == 0)
        #expect(seed.exclusion == .notSeed)
    }

    @Test func localHistoryCanBeOff() {
        var signals = UserSignals()
        signals.sessions = [Fixture.watched("1", daysAgo: 0)]
        var settings = RecommenderSettings()
        settings.useLocalHistory = false
        #expect(weigh(signals, titles: [Fixture.film("1")], settings: settings).isEmpty)
    }

    @Test func utcOffsetFromContext() {
        // 21:00 UTC read as 00:00 local: +3 h.
        let context = EngineContext(now: Fixture.now, weekday: 6, hour: 0, minute: 0)
        #expect(EngineTime.utcOffset(context) == 3 * 3600)
        #expect(EngineTime.utcOffset(EngineContext(now: Fixture.now, weekday: 5, hour: 21, minute: 0)) == 0)
        #expect(EngineTime.utcOffset(EngineContext(now: Fixture.now, weekday: 5, hour: 14, minute: 0)) == -7 * 3600)
    }
}
