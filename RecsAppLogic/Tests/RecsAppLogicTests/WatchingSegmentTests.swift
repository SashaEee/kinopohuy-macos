import Foundation
import Testing
@testable import RecsAppLogic

@Suite("Сегменты «Досмотреть»")
struct WatchingSegmentTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .gmt
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 21)) ?? .distantPast
    }

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86400)
    }

    private func series(season: Int?, episode: Int?, daysAgo days: Int?, playedHere: Bool = false) -> WatchingFacts {
        WatchingFacts(watched: false, lastActivity: days.map(daysAgo), isSeries: true, season: season, episode: episode, filmFraction: nil, playedHere: playedHere)
    }

    private func film(fraction: Double?, daysAgo days: Int?) -> WatchingFacts {
        WatchingFacts(watched: false, lastActivity: days.map(daysAgo), isSeries: false, season: nil, episode: nil, filmFraction: fraction, playedHere: fraction != nil)
    }

    @Test func watchedWinsOverEverything() {
        var facts = series(season: 1, episode: 1, daysAgo: 400)
        facts.watched = true
        facts.isSetAside = true
        #expect(WatchingSegment.classify(facts, now: now) == .watched)
    }

    @Test func nothingStartedCanStart() {
        #expect(WatchingSegment.classify(series(season: 1, episode: 1, daysAgo: 3), now: now) == .canStart)
        #expect(WatchingSegment.classify(series(season: nil, episode: nil, daysAgo: nil), now: now) == .canStart)
        #expect(WatchingSegment.classify(film(fraction: nil, daysAgo: 100), now: now) == .canStart)
    }

    @Test func firstEpisodePlayedHereIsStarted() {
        #expect(WatchingSegment.classify(series(season: 1, episode: 1, daysAgo: 3, playedHere: true), now: now) == .continueWatching)
    }

    @Test func recentActivityContinues() {
        #expect(WatchingSegment.classify(series(season: 2, episode: 5, daysAgo: 12), now: now) == .continueWatching)
        #expect(WatchingSegment.classify(film(fraction: 0.3, daysAgo: 30), now: now) == .continueWatching)
    }

    @Test func longQuietAndBarelyStartedLooksAbandoned() {
        #expect(WatchingSegment.classify(series(season: 1, episode: 3, daysAgo: 61), now: now) == .abandoned)
        #expect(WatchingSegment.classify(film(fraction: 0.4, daysAgo: 90), now: now) == .abandoned)
    }

    @Test func farIntoItIsNeverAbandoned() {
        // Three episodes behind, or most of a film: a pause, not a drop.
        #expect(WatchingSegment.classify(series(season: 1, episode: 4, daysAgo: 200), now: now) == .continueWatching)
        #expect(WatchingSegment.classify(series(season: 3, episode: 1, daysAgo: 200), now: now) == .continueWatching)
        #expect(WatchingSegment.classify(film(fraction: 0.8, daysAgo: 200), now: now) == .continueWatching)
    }

    @Test func betweenThirtyAndSixtyDaysStillContinues() {
        #expect(WatchingSegment.classify(series(season: 1, episode: 2, daysAgo: 45), now: now) == .continueWatching)
    }

    @Test func noDateGivesTheBenefitOfTheDoubt() {
        #expect(WatchingSegment.classify(series(season: 1, episode: 2, daysAgo: nil), now: now) == .continueWatching)
    }

    @Test func newEpisodeBringsItBack() {
        var facts = series(season: 1, episode: 2, daysAgo: 300)
        facts.hasNewEpisode = true
        #expect(WatchingSegment.classify(facts, now: now) == .continueWatching)
    }

    @Test func setAsideLeavesEverySegmentButWatched() {
        var facts = series(season: 1, episode: 2, daysAgo: 300)
        facts.isSetAside = true
        #expect(WatchingSegment.classify(facts, now: now) == nil)
    }

    @Test func titlesAreTheTVsPills() {
        #expect(WatchingSegment.allCases.map(\.title) == ["Продолжить", "Можно начать", "Похоже, бросили?", "Досмотрено"])
    }

    @Test func parsesTheSitesDates() throws {
        let date = try #require(ActivityDate.parse("12-10-2026", now: now, calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2026, month: 10, day: 12))
        #expect(ActivityDate.parse("12.10.2026", now: now, calendar: calendar) == date)
        #expect(ActivityDate.parse(" 12-10-26 ", now: now, calendar: calendar) == date)
    }

    @Test func parsesTodayAndYesterday() {
        #expect(ActivityDate.parse("Сегодня", now: now, calendar: calendar) == calendar.startOfDay(for: now))
        #expect(ActivityDate.parse("вчера, 21:40", now: now, calendar: calendar) == calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
    }

    @Test(arguments: ["", "просмотрено", "32-10-2026", "12-13-2026", "12-10", "1-1-1800"])
    func rejectsWhatIsNotADate(text: String) {
        #expect(ActivityDate.parse(text, now: now, calendar: calendar) == nil)
    }
}
