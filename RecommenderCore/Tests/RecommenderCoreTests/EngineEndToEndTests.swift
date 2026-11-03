import Foundation
import Testing
@testable import RecommenderCore

/// The whole pipeline on a synthetic catalogue: what Home gets must be stable, honest and fast.
@Suite("Engine end to end")
struct EngineEndToEndTests {
    static let input = SyntheticCatalog.input(titles: 2_000, signals: 120)

    /// Every title Home shows, hero first.
    private func pageIds(_ output: EngineOutput) -> [String] {
        var ids: [String] = []
        if let hero = output.page.hero { ids += [hero.main.titleId] + hero.alternatives.map(\.titleId) }
        for row in output.page.rows { ids += row.items.map(\.titleId) }
        return ids
    }

    @Test func sameInputSamePage() {
        let first = Recommender.run(Self.input)
        let second = Recommender.run(Self.input)
        #expect(first.ranked.map(\.titleId) == second.ranked.map(\.titleId))
        #expect(pageIds(first) == pageIds(second))
        #expect(first.page.rows.map(\.title) == second.page.rows.map(\.title))
    }

    @Test func pageShowsEachTitleOnceWithinLimits() {
        let output = Recommender.run(Self.input)
        #expect(!output.isColdStart)
        #expect(!output.page.rows.isEmpty)
        let ids = pageIds(output)
        #expect(ids.count == Set(ids).count, "a title appears twice on Home")
        let weights = Weights.default
        #expect(output.page.rows.count <= weights.maxPersonalRows)
        for row in output.page.rows {
            #expect(row.items.count >= weights.rowMinItems, "row «\(row.title)» is too short")
            #expect(!row.title.isEmpty)
        }
        let known = Set(Self.input.titles.map(\.id))
        #expect(ids.allSatisfy(known.contains))
    }

    @Test func dislikedHiddenAndWatchedStayOut() {
        var input = Self.input
        let pages = input.titles.filter { $0.level == .page && !$0.isSeries }
        let disliked = pages[0].id
        let hidden = pages[1].id
        let watched = pages[2].id
        input.signals.ratings.append(ExplicitRating(titleId: disliked, level: -2, source: .app, createdAt: Fixture.now))
        input.signals.feedback.append(Feedback(titleId: hidden, kind: .hidden, createdAt: Fixture.now))
        input.signals.sessions.append(Fixture.watched(watched, daysAgo: 1, minutes: Double(pages[2].durationMin ?? 100)))

        let output = Recommender.run(input)
        let shown = Set(pageIds(output) + output.ranked.map(\.titleId))
        #expect(!shown.contains(disliked))
        #expect(!shown.contains(hidden))
        #expect(!shown.contains(watched))
    }

    @Test func notTodayComesBackAfterItsWeek() {
        var input = Self.input
        let top = Recommender.run(input).ranked.first?.titleId
        guard let top else { Issue.record("nothing ranked"); return }
        input.signals.feedback.append(Feedback(titleId: top, kind: .notToday, createdAt: Fixture.now, until: Fixture.now + 7 * Fixture.day))
        #expect(!Recommender.run(input).ranked.map(\.titleId).contains(top))

        var later = input
        later.context = Fixture.context(now: Fixture.now + 8 * Fixture.day)
        #expect(Recommender.run(later).ranked.map(\.titleId).contains(top))
    }

    @Test func reasonsNameOnlyRealAnchors() {
        let output = Recommender.run(Self.input)
        let names = Dictionary(uniqueKeysWithValues: Self.input.titles.map { ($0.id, $0.name) })
        for recommendation in output.ranked.prefix(200) {
            let reason = recommendation.reason
            #expect(!reason.short.isEmpty)
            #expect(!reason.long.isEmpty)
            guard reason.kind == .becauseWatched || reason.kind == .loved || reason.kind == .similarToMany else { continue }
            #expect(!reason.evidence.anchorIds.isEmpty)
            for anchor in reason.evidence.anchorIds {
                // «Потому что вы досмотрели «X»» only for a title that really weighs that much.
                #expect((output.titleWeights[anchor] ?? 0) >= Weights.default.reasonAnchorMinWeight, "weak anchor \(anchor) in «\(reason.long)»")
                if let name = names[anchor], reason.evidence.anchorIds.count == 1 {
                    #expect(reason.long.contains(name))
                }
            }
        }
    }

    @Test func noSignalsIsColdStart() {
        let input = Fixture.input(titles: Self.input.titles, signals: UserSignals())
        let output = Recommender.run(input)
        #expect(output.isColdStart)
        #expect(output.profile.positiveCount == 0)
    }

    @Test func pickExplainAndFitStayWithinTheCatalogue() {
        let engine = Recommender.prepare(Self.input)
        let known = Set(Self.input.titles.map(\.id))
        let result = engine.pick(PickRequest(intent: .empty, seed: 7))
        let main = try? #require(result.main)
        #expect(main.map { known.contains($0.titleId) } == true)
        #expect(result.alternatives.allSatisfy { known.contains($0.titleId) })
        #expect(engine.pick(PickRequest(intent: .empty, seed: 7)).main?.titleId == main?.titleId)

        if let top = engine.output.ranked.first {
            let explanation = engine.explain(top.titleId)
            #expect(explanation?.lines.isEmpty == false)
            #expect(engine.fit(top.titleId) != nil)
        }
        #expect(engine.onboardingStack().count <= 12)
        #expect(engine.onboardingStack().allSatisfy(known.contains))
    }

    /// The real catalogue grows to about 8k titles; Home must still rebuild in well under a second on a Mac (this runs
    /// unoptimised, hence the generous bound).
    @Test func eightThousandTitlesInTime() {
        let input = SyntheticCatalog.input(titles: 8_000, signals: 300)
        let start = Date()
        let output = Recommender.run(input)
        let elapsed = Date().timeIntervalSince(start)
        #expect(!output.ranked.isEmpty)
        #expect(elapsed < 8, "took \(elapsed) s")
    }
}

/// «Уточнить вкус»: bubbles, the next titles after a liked one, the confidence meter.
@Suite("Taste setup")
struct TasteSetupTests {
    @Test func bubblesStartWithWhatIsLikedAndSkipSiteSections() {
        let engine = Recommender.prepare(EngineEndToEndTests.input)
        let bubbles = engine.tasteBubbles(limit: 18)
        #expect(bubbles.count <= 18)
        #expect(!bubbles.isEmpty)
        #expect(bubbles.first.map { $0.affinity > 0 } == true)
        #expect(Set(bubbles.map(\.feature)).count == bubbles.count)
        #expect(!bubbles.contains { $0.name.lowercased() == "зарубежные" })
    }

    @Test func interestGridIsUnseenAndVaried() {
        let input = EngineEndToEndTests.input
        let engine = Recommender.prepare(input)
        let grid = engine.interestGrid(count: 12)
        let touched = Set(input.signals.sessions.map(\.titleId) + input.signals.accountList.map(\.titleId) + input.signals.ratings.map(\.titleId))
        #expect(grid.count <= 12)
        #expect(Set(grid).count == grid.count)
        #expect(grid.allSatisfy { !touched.contains($0) })
        #expect(grid == engine.interestGrid(count: 12))
    }

    /// Most accounts play from «Досмотреть» on the TV or the site and mark nothing: those titles still make a deck.
    @Test func stackFromTitlesPlayedElsewhere() {
        let titles = (1...6).map { Fixture.film("f\($0)") } + (1...6).map { Fixture.series("s\($0)") }
        var signals = UserSignals()
        signals.accountList = titles.enumerated().map { offset, title in
            AccountListItem(
                titleId: title.id, watched: false, lastActivityAt: Fixture.now - Double(offset) * Fixture.day,
                season: title.isSeries ? 2 : nil, episode: title.isSeries ? 3 : nil,
            )
        }
        let stack = Recommender.prepare(Fixture.input(titles: titles, signals: signals)).onboardingStack(count: 12)
        #expect(stack.count >= 10)
        #expect(stack.contains { $0.hasPrefix("s") })
        #expect(stack.contains { $0.hasPrefix("f") })
    }

    @Test func confidenceGrowsWithRatings() {
        var input = EngineEndToEndTests.input
        input.signals.ratings = []
        let before = Recommender.prepare(input).tasteConfidence()
        input.signals.ratings = input.titles.prefix(10).map { ExplicitRating(titleId: $0.id, level: 1, source: .onboarding, createdAt: Fixture.now) }
        let after = Recommender.prepare(input).tasteConfidence()
        #expect(before <= 0.35 + 1e-9)
        #expect(after > before)
        #expect(after <= 1)
    }
}
