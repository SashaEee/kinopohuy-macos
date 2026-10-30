import RecommenderCore
import Testing
@testable import RecsAppLogic

@Suite("Три уровня и оценка сайта")
struct TasteLevelTests {
    @Test func levelsMatchThePlan() {
        #expect(TasteLevel.notForMe.level == -2)
        #expect(TasteLevel.like.level == 1)
        #expect(TasteLevel.love.level == 2)
    }

    @Test(arguments: [
        (2.0, TasteLevel.love), (1.5, .love), (1.0, .like), (0.5, .like),
        (-1.0, .notForMe), (-1.5, .notForMe), (-2.0, .notForMe),
    ])
    func storedLevelLightsTheNearestButton(stored: Double, expected: TasteLevel) {
        #expect(TasteLevel(stored: stored) == expected)
    }

    @Test(arguments: [nil, 0.0, 0.3, -0.4, -0.9] as [Double?])
    func neutralOrMissingLightsNothing(stored: Double?) {
        #expect(TasteLevel(stored: stored) == nil)
    }

    @Test func tappingTheLitButtonClearsIt() {
        #expect(TasteLevel.toggled(current: .like, tapped: .like) == nil)
        #expect(TasteLevel.toggled(current: .like, tapped: .love) == .love)
        #expect(TasteLevel.toggled(current: nil, tapped: .notForMe) == .notForMe)
    }

    @Test func keysAreOneTwoThree() {
        #expect(TasteLevel.allCases.map(\.key) == ["1", "2", "3"])
    }

    @Test(arguments: [(10, 2.0), (9, 2.0), (8, 1.0), (7, 1.0), (6, 0.0), (5, 0.0), (4, -1.5), (1, -1.5)])
    func siteRatingMapsOntoTheScale(score: Int, level: Double) {
        #expect(SiteRatingMirror.level(for: score) == level)
    }

    @Test(arguments: [0, 11, -3])
    func outOfRangeSiteRatingIsIgnored(score: Int) {
        #expect(SiteRatingMirror.level(for: score) == nil)
    }

    @Test func siteRatingAgreesWithTheButtons() {
        // A 9 on the site lights «Обожаю», a 7 «Нравится», a 3 «Не моё», a 5 nothing.
        #expect(TasteLevel(stored: SiteRatingMirror.level(for: 9)) == .love)
        #expect(TasteLevel(stored: SiteRatingMirror.level(for: 7)) == .like)
        #expect(TasteLevel(stored: SiteRatingMirror.level(for: 3)) == .notForMe)
        #expect(TasteLevel(stored: SiteRatingMirror.level(for: 5)) == nil)
    }
}

@Suite("Действия над тайтлом")
struct TitleActionTests {
    @Test func everyActionIsEitherARatingOrAMark() {
        for action in TitleAction.allCases {
            #expect((action.rating == nil) != (action.feedback == nil), "\(action)")
        }
    }

    @Test func ratingsComeFromTheThreeLevels() {
        for level in TasteLevel.allCases {
            #expect(TitleAction(level).rating == level.level)
        }
    }

    @Test func everyFeedbackKindTheUIOffersHasAnAction() {
        let offered: [FeedbackKind] = [.hidden, .seen, .notToday, .notMe, .continueHidden, .dropped]
        for kind in offered {
            #expect(TitleAction.of(kind)?.feedback == kind)
        }
        // «Не учитывать «X»» lives in «Почему это?», not in these menus.
        #expect(TitleAction.of(.notSeed) == nil)
    }

    @Test func confirmationsFitOnAPoster() {
        for action in TitleAction.allCases {
            #expect(action.confirmation.count <= 22, "\(action.confirmation)")
            #expect(!action.title.isEmpty && !action.help.isEmpty)
        }
    }

    @Test func notForMeAndHiddenSayTheSame() {
        #expect(TitleAction.notForMe.confirmation == "Больше не покажем")
        #expect(TitleAction.hidden.confirmation == "Больше не покажем")
    }
}

@Suite("Плашка после просмотра")
struct PostPlayTests {
    @Test func filmAsksInItsCredits() {
        #expect(!PostPlayRules.reachedEnd(isSeries: false, isLastOfSeason: false, currentTime: 5000, duration: 6000, finished: false))
        #expect(PostPlayRules.reachedEnd(isSeries: false, isLastOfSeason: false, currentTime: 5910, duration: 6000, finished: false))
        #expect(PostPlayRules.reachedEnd(isSeries: false, isLastOfSeason: false, currentTime: 0, duration: 6000, finished: true))
    }

    @Test func seriesAsksOnlyAtTheSeasonsLastEpisode() {
        #expect(!PostPlayRules.reachedEnd(isSeries: true, isLastOfSeason: false, currentTime: 2990, duration: 3000, finished: true))
        #expect(PostPlayRules.reachedEnd(isSeries: true, isLastOfSeason: true, currentTime: 2950, duration: 3000, finished: false))
        #expect(!PostPlayRules.reachedEnd(isSeries: true, isLastOfSeason: true, currentTime: 100, duration: 3000, finished: false))
    }

    @Test func unknownOrTinyDurationNeverAsksEarly() {
        #expect(!PostPlayRules.reachedEnd(isSeries: false, isLastOfSeason: false, currentTime: 10, duration: nil, finished: false))
        // A 2-minute clip would be «in its credits» from the start.
        #expect(!PostPlayRules.reachedEnd(isSeries: false, isLastOfSeason: false, currentTime: 31, duration: 120, finished: false))
    }

    @Test func asksOncePerTitleWhileOnAndUnrated() {
        #expect(PostPlayRules.shouldAsk(enabled: true, titleId: "42", asked: [], hasRating: false))
        #expect(!PostPlayRules.shouldAsk(enabled: false, titleId: "42", asked: [], hasRating: false))
        #expect(!PostPlayRules.shouldAsk(enabled: true, titleId: "42", asked: ["42"], hasRating: false))
        #expect(!PostPlayRules.shouldAsk(enabled: true, titleId: "42", asked: [], hasRating: true))
        #expect(!PostPlayRules.shouldAsk(enabled: true, titleId: nil, asked: [], hasRating: false))
        #expect(!PostPlayRules.shouldAsk(enabled: true, titleId: "", asked: [], hasRating: false))
    }

    @Test func memoryKeepsTheNewestAndNoRepeats() {
        var asked: [String] = []
        for id in 0 ..< 10 { asked = PostPlayRules.remembering("\(id)", in: asked, limit: 4) }
        #expect(asked == ["6", "7", "8", "9"])
        asked = PostPlayRules.remembering("7", in: asked, limit: 4)
        #expect(asked == ["6", "8", "9", "7"])
    }

    @Test func questionCutsLongNames() {
        #expect(PostPlayRules.question("Мост") == "Как вам «Мост»?")
        #expect(PostPlayRules.question("  ") == "Как вам?")
        let long = PostPlayRules.question(String(repeating: "а", count: 60), maxLength: 10)
        #expect(long == "Как вам «ааааааааа…»?")
    }
}
