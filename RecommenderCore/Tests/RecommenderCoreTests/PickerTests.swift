import Foundation
import Testing
@testable import RecommenderCore

/// «Выбери за меня» (§4.9): hard rules hold, nothing repeats, the session is reproducible, and when nothing fits the
/// picker says what it dropped instead of returning nothing.
@Suite("Picker")
struct PickerTests {
    typealias F = PickFixtures

    private func ids(_ result: PickResult) -> [String] {
        ([result.main] + result.alternatives).compactMap { $0?.titleId }
    }

    @Test func sameSeedSamePick() {
        let context = F.catalogueContext()
        let first = Picker.pick(F.request(seed: 9), in: context)
        let second = Picker.pick(F.request(seed: 9), in: context)
        #expect(first.main != nil)
        #expect(ids(first) == ids(second))
    }

    @Test func shownTitlesNeverComeBack() {
        let context = F.catalogueContext()
        var shown: [String] = []
        for skip in 0..<8 {
            let result = Picker.pick(F.request(shown: shown, skips: skip), in: context)
            guard let main = result.main?.titleId else { break }
            #expect(!shown.contains(main), "«\(main)» shown twice")
            shown.append(main)
        }
        #expect(shown.count >= 5)
    }

    @Test func familyNightHasNoHorrorOrAdultTitles() {
        let intent = F.sure(WatchIntent(company: .family))
        let context = F.catalogueContext()
        var shown: [String] = []
        for _ in 0..<6 {
            let result = Picker.pick(F.request(intent, shown: shown), in: context)
            for id in ids(result) {
                let title = context.titles[id]
                #expect(title?.genres.contains("Ужасы") == false, "\(id) is horror")
                #expect((title?.age ?? 0) <= 12, "\(id) is \(title?.age ?? 0)+")
            }
            guard let main = result.main?.titleId else { break }
            shown.append(main)
        }
    }

    @Test func timeBudgetIsRespected() {
        let intent = F.sure(WatchIntent(kinds: [.film], time: .maxMinutes(100)))
        let result = Picker.pick(F.request(intent), in: F.catalogueContext())
        let main = result.main.flatMap { F.catalogueContext().titles[$0.titleId] }
        #expect(main != nil)
        #expect((main?.durationMin ?? .max) <= 100)
        #expect(main?.isSeries == false)
        #expect(result.relaxed.isEmpty)
    }

    @Test func impossibleRequestIsRelaxedAndSaysSo() {
        // No film is ten minutes long: something has to give, and the user hears what.
        let intent = F.sure(WatchIntent(kinds: [.film], time: .maxMinutes(10)))
        let result = Picker.pick(F.request(intent), in: F.catalogueContext())
        #expect(result.main != nil)
        #expect(!result.relaxed.isEmpty)
        #expect(result.relaxed.allSatisfy { !$0.label.isEmpty })
    }

    @Test func gridAfterThreeSkipsAndRefineAfterFive() {
        let context = F.catalogueContext()
        #expect(!Picker.pick(F.request(skips: 2), in: context).showGrid)
        let grid = Picker.pick(F.request(skips: 3), in: context)
        #expect(grid.showGrid)
        #expect(ids(grid).count == 3)
        #expect(!grid.suggestRefine)
        #expect(Picker.pick(F.request(skips: 5), in: context).suggestRefine)
    }

    @Test func ownPoolPicksFromOwn() {
        let own = ["drama3", "korean1", "hunt"]
        let context = F.catalogueContext(own: own)
        let result = Picker.pick(F.request(pool: .own), in: context)
        #expect(result.main.map { own.contains($0.titleId) } == true)
    }

    @Test func excludedGenreFromSettingsNeverPicked() {
        var settings = RecommenderSettings()
        settings.excludedGenres = ["Ужасы"]
        let context = F.catalogueContext(settings: settings)
        var shown: [String] = []
        for _ in 0..<10 {
            guard let main = Picker.pick(F.request(shown: shown), in: context).main?.titleId else { break }
            #expect(context.titles[main]?.genres.contains("Ужасы") == false)
            shown.append(main)
        }
    }

    @Test func neverInventsTitles() {
        let context = F.catalogueContext()
        for seed in UInt64(0)..<30 {
            let result = Picker.pick(F.request(seed: seed), in: context)
            #expect(ids(result).allSatisfy { context.titles[$0] != nil })
        }
    }
}
