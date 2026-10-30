import Testing
@testable import RecommenderCore

@Test func emptyInputGivesColdStart() {
    let input = EngineInput(context: EngineContext(now: 0, weekday: 5, hour: 21, minute: 0), titles: [], signals: UserSignals(), settings: RecommenderSettings(), seed: 1)
    #expect(Recommender.run(input).isColdStart)
}
