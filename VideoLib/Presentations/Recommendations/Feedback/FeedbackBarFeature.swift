import ComposableArchitecture
import Foundation
import RecommenderCore

/// The title page's «Не моё · Нравится · Обожаю» and its «…» («Скрыть», «Уже смотрел», «Не сегодня», «Это смотрел не
/// я»). Everything is shown at once and recorded behind it; the page's site rating, once sent, is read back here (the
/// app keeps a copy, since the site never returns it).
@Reducer
struct FeedbackBarFeature {
    @ObservableState
    struct State: Equatable {
        /// The title's number on the site; nil (an address without one) leaves the bar out.
        let titleId: String?
        var level: TasteLevel?
        /// The service marks that are on.
        var marks: Set<FeedbackKind> = []
        var isLoaded = false
        /// Just marked «Уже смотрел»: the bar asks «Как вам?» over its three buttons for a while.
        var asksAfterSeen = false

        init(titleId: String?) {
            self.titleId = titleId
        }

        /// The marks the «…» menu offers, in its order.
        static let menuActions: [TitleAction] = [.hidden, .seen, .notToday, .notMe]

        /// The marks that are on, as actions, in the menu's order (then any others, e.g. from «Досмотреть»).
        var activeActions: [TitleAction] {
            let ordered = Self.menuActions + [.continueHidden, .dropped]
            return ordered.filter { action in action.feedback.map(marks.contains) ?? false }
        }
    }

    enum Action: Equatable {
        case onAppear
        /// Read the level and marks again (after the site rating was copied in).
        case reload
        case loaded(level: Double?, marks: Set<FeedbackKind>)
        case levelTapped(TasteLevel)
        /// A mark from the «…» menu: on if it was off, off if it was on.
        case markToggled(TitleAction)
        case markRemoved(FeedbackKind)
        case seenPromptEnded
    }

    private enum CancelID { case load, seenPrompt }

    /// How long «Уже смотрели — как вам?» stays.
    static let seenPromptSeconds = 12

    @Dependency(\.recommender) private var recommender
    @Dependency(\.continuousClock) private var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Every time: a card's menu or the player may have rated it since.
                return .send(.reload)

            case .reload:
                guard let titleId = state.titleId else { return .none }

                return .run { send in
                    async let level = recommender.rating(titleId)
                    async let marks = recommender.activeFeedback(titleId)
                    await send(.loaded(level: level, marks: marks), animation: .smooth(duration: 0.25))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loaded(level, marks):
                state.level = TasteLevel(stored: level)
                state.marks = marks
                state.isLoaded = true

                return .none

            case let .levelTapped(tapped):
                guard let titleId = state.titleId else { return .none }

                let level = TasteLevel.toggled(current: state.level, tapped: tapped)
                state.level = level
                state.asksAfterSeen = false
                state.isLoaded = true

                return .merge(
                    // A read still on its way is older than this press.
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.seenPrompt),
                    .run { _ in
                        if let level {
                            await recommender.rate(titleId, level.level, .app)
                        } else {
                            await recommender.clearRating(titleId)
                            // A card dimmed «Больше не покажем» in this session shouldn't say so any more.
                            await RecCardMarks.shared.clear(titleId)
                        }
                    }
                )

            case let .markToggled(action):
                guard let titleId = state.titleId, let kind = action.feedback else { return .none }

                if state.marks.contains(kind) {
                    return .send(.markRemoved(kind))
                }

                state.marks.insert(kind)
                state.isLoaded = true
                let record: Effect<Action> = .merge(
                    .cancel(id: CancelID.load),
                    .run { _ in await recommender.feedback(titleId, kind) }
                )

                guard kind == .seen, state.level == nil else { return record }

                // Watched elsewhere: the three buttons are right here, so the bar just asks.
                state.asksAfterSeen = true

                return .merge(
                    record,
                    .run { send in
                        try await clock.sleep(for: .seconds(Self.seenPromptSeconds))
                        await send(.seenPromptEnded, animation: .smooth(duration: 0.3))
                    }
                    .cancellable(id: CancelID.seenPrompt, cancelInFlight: true)
                )

            case let .markRemoved(kind):
                guard let titleId = state.titleId else { return .none }

                state.marks.remove(kind)
                if kind == .seen { state.asksAfterSeen = false }

                return .merge(.cancel(id: CancelID.load), .run { _ in
                    await recommender.removeFeedback(titleId, kind)
                    await RecCardMarks.shared.clear(titleId)
                })

            case .seenPromptEnded:
                state.asksAfterSeen = false

                return .none
            }
        }
    }
}
