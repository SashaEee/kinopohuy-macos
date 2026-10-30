import RecommenderCore
import Testing
@testable import RecsAppLogic

@Suite("Стопка вкуса")
struct OnboardingTests {
    @Test func offeredOnceSignedInWithEnoughTitles() {
        #expect(TasteOnboardingRules.shouldOffer(offered: false, signedIn: true, ownTitles: 5))
        #expect(!TasteOnboardingRules.shouldOffer(offered: true, signedIn: true, ownTitles: 12))
        #expect(!TasteOnboardingRules.shouldOffer(offered: false, signedIn: false, ownTitles: 12))
        #expect(!TasteOnboardingRules.shouldOffer(offered: false, signedIn: true, ownTitles: 4))
    }

    @Test func counterReadsLikeTheTV() {
        #expect(TasteOnboardingRules.counter(index: 3, total: 12) == "4 из 12")
        #expect(TasteOnboardingRules.counter(index: 12, total: 12) == "12 из 12")
    }

    @Test func keysChooseAsTheButtonsSay() {
        #expect(OnboardingChoice(key: "1") == .notForMe)
        #expect(OnboardingChoice(key: "2") == .like)
        #expect(OnboardingChoice(key: "3") == .love)
        #expect(OnboardingChoice(key: "0") == .dontRemember)
        #expect(OnboardingChoice(key: "4") == nil)
        for choice in OnboardingChoice.allCases {
            #expect(OnboardingChoice(key: choice.key) == choice)
        }
    }

    @Test func dontRememberRecordsNothing() {
        #expect(OnboardingChoice.dontRemember.tasteLevel == nil)
        #expect(OnboardingChoice.dontRemember.title == "Не помню")
        for level in TasteLevel.allCases {
            #expect(OnboardingChoice(level).tasteLevel == level)
        }
    }
}

@Suite("Чего не показывать")
struct ExclusionTests {
    @Test func chipsReadBackWhatIsStored() {
        let selected = ExclusionChip.selected(kinds: ["anime", "show"], genres: ["Ужасы", "Комедии"])
        #expect(selected == [.anime, .shows, .horror])
    }

    @Test func applyingKeepsWhatNoChipStandsFor() {
        let result = ExclusionChip.apply([.cartoons, .melodrama], kinds: ["anime", "series"], genres: ["Комедии", "Ужасы"])
        // «anime» and «Ужасы» are chips that are now off; «series» and «Комедии» were set elsewhere and stay.
        #expect(result.kinds == ["cartoon", "series"])
        #expect(result.genres == ["Комедии", "Мелодрамы"])
    }

    @Test func roundTripIsStable() {
        for chip in ExclusionChip.allCases {
            let stored = ExclusionChip.apply([chip], kinds: [], genres: [])
            #expect(ExclusionChip.selected(kinds: stored.kinds, genres: stored.genres) == [chip])
        }
        let none = ExclusionChip.apply([], kinds: [], genres: [])
        #expect(none.kinds.isEmpty && none.genres.isEmpty)
    }

    @Test func everyChipCoversSomething() {
        for chip in ExclusionChip.allCases {
            #expect(!chip.kinds.isEmpty || !chip.genres.isEmpty)
        }
        #expect(ExclusionChip.allCases.map(\.title) == ["Аниме", "Мультфильмы", "ТВ-шоу", "Документальное", "Ужасы", "Мелодрамы", "Реалити"])
    }

    @Test(arguments: [(0, AgeLimit.any), (6, .six), (12, .twelve), (14, .twelve), (16, .sixteen), (18, .any)])
    func ageLimitReadsTheStoredValue(stored: Int, expected: AgeLimit) {
        #expect(AgeLimit(stored: stored) == expected)
    }
}

@Suite("Вкус словами")
struct TasteSummaryTests {
    private func feature(_ name: String, _ affinity: Double, support: Int = 3) -> FeatureAffinity {
        FeatureAffinity(feature: FeatureKey(.genre, name), name: name, affinity: affinity, support: support)
    }

    @Test func chipsAreTheLikedSupportedOnes() {
        let profile = ProfileSummary(
            top: [feature("Детективы", 0.8), feature("детективы", 0.7), feature("Скандинавия", 0.5), feature("Мюзиклы", 0.9, support: 1), feature("Драмы", -0.2)],
            disliked: [], positiveCount: 3, negativeCount: 0, seriesShare: 0.9
        )
        #expect(TasteSummary.chips(profile) == ["Детективы", "Скандинавия"])
    }

    @Test func seriesOrFilmsOnlyWithEnoughTitles() {
        let many = ProfileSummary(top: [feature("Детективы", 0.8)], disliked: [], positiveCount: 12, negativeCount: 1, seriesShare: 0.7)
        #expect(TasteSummary.chips(many).last == "Сериалы чаще фильмов")
        let films = ProfileSummary(top: [], disliked: [], positiveCount: 12, negativeCount: 1, seriesShare: 0.2)
        #expect(TasteSummary.chips(films) == ["Фильмы чаще сериалов"])
        let balanced = ProfileSummary(top: [], disliked: [], positiveCount: 12, negativeCount: 1, seriesShare: 0.45)
        #expect(TasteSummary.chips(balanced).isEmpty)
    }

    @Test func chipsStopAtTheLimit() {
        let top = (0 ..< 20).map { feature("Жанр \($0)", 0.5) }
        let profile = ProfileSummary(top: top, disliked: [], positiveCount: 0, negativeCount: 0, seriesShare: 0)
        #expect(TasteSummary.chips(profile, limit: 5).count == 5)
    }

    @Test func countsReadNaturally() {
        #expect(TasteSummary.counts(.empty) == nil)
        #expect(TasteSummary.counts(ProfileSummary(top: [], disliked: [], positiveCount: 21, negativeCount: 0, seriesShare: 0)) == "Учтено 21 тайтл")
        #expect(TasteSummary.counts(ProfileSummary(top: [], disliked: [], positiveCount: 37, negativeCount: 5, seriesShare: 0)) == "Учтено 42 тайтла: 37 по душе, 5 нет")
    }

    @Test(arguments: [(1, "тайтл"), (2, "тайтла"), (5, "тайтлов"), (11, "тайтлов"), (12, "тайтлов"), (21, "тайтл"), (22, "тайтла"), (111, "тайтлов"), (0, "тайтлов")])
    func plurals(n: Int, form: String) {
        #expect(RussianPlural.form(n, "тайтл", "тайтла", "тайтлов") == form)
    }

    @Test func numbersGroupThousands() {
        #expect(RussianPlural.number(7) == "7")
        #expect(RussianPlural.number(1240) == "1\u{00A0}240")
        #expect(RussianPlural.number(1_234_567) == "1\u{00A0}234\u{00A0}567")
        #expect(RussianPlural.number(-3000) == "−3\u{00A0}000")
    }

    @Test func catalogueLine() {
        #expect(CatalogueStatusText.line(known: 3120, pages: 1240, fetchedToday: 84, dailyLimit: 300, enabled: true)
            == "Изучено 1\u{00A0}240 тайтлов из 3\u{00A0}120 · сегодня 84 из 300")
        #expect(CatalogueStatusText.line(known: 10, pages: 10, fetchedToday: 0, dailyLimit: 300, enabled: false)
            == "Изучено 10 тайтлов · фоновое изучение выключено")
        #expect(CatalogueStatusText.line(known: 0, pages: 0, fetchedToday: 0, dailyLimit: 0, enabled: true)
            == "Каталог пока пуст: он растёт, пока вы листаете")
    }
}
