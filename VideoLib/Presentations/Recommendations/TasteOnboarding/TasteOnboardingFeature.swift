import ComposableArchitecture
import Defaults
import Foundation
import RecommenderCore

/// «Уточнить вкус за минуту» (the plan's §2.1, branch A): what the app already knows of your taste, then up to 12 of
/// your own titles to rate with one key each, then what never to show. Every answer counts the moment it's given, so
/// leaving halfway keeps what was said; «Пропустить» is on every step. Offered once (`shouldOffer`), and from Settings.
@Reducer
struct TasteOnboardingFeature {
    enum Step: Int, CaseIterable, Equatable, Sendable {
        case intro
        case stack
        case exclusions
        case done
    }

    @ObservableState
    struct State: Equatable {
        var step: Step = .intro
        /// The last step change went on (or back, with «Назад»): the steps slide that way.
        var movingForward = true
        var isLoading = true
        /// «Детективы · Скандинавия · 2010-е · Финчер · Сериалы чаще фильмов».
        var tasteChips: [String] = []
        /// «Учтено 42 тайтла: 37 по душе, 5 нет».
        var countsLine: String?
        var stack: [TitleFeatures] = []
        var index = 0
        /// The answers so far, in order (for «Назад»).
        var answers: [Answer] = []
        /// What each stack title was rated before (to put it back on «Назад»).
        var previousRatings: [String: Double] = [:]
        var exclusions: Set<ExclusionChip>
        var maxAge: AgeLimit
        /// Done or skipped: the view closes.
        var isFinished = false

        struct Answer: Equatable, Sendable {
            let titleId: String
            let choice: OnboardingChoice
        }

        init() {
            exclusions = ExclusionChip.selected(kinds: Defaults[.recExcludedKinds], genres: Defaults[.recExcludedGenres])
            maxAge = AgeLimit(stored: Defaults[.recMaxAge])
        }

        var current: TitleFeatures? {
            stack.indices.contains(index) ? stack[index] : nil
        }

        /// The three levels given (not «Не помню»).
        var ratedCount: Int {
            answers.count { $0.choice != .dontRemember }
        }

        /// What the current title was already rated, if it was (the card says so).
        var currentPrevious: TasteLevel? {
            current.flatMap { TasteLevel(stored: previousRatings[$0.id]) }
        }

        mutating func go(_ next: Step) {
            movingForward = next.rawValue >= step.rawValue
            step = next
        }
    }

    enum Action: Equatable {
        case onAppear
        case loaded(chips: [String], counts: String?, stack: [TitleFeatures], previous: [String: Double])
        /// «Уточнить за минуту».
        case startTapped
        /// «Сразу к рекомендациям», or «Пропустить» on the first step.
        case skipAllTapped
        case choose(OnboardingChoice)
        /// «Назад»: the last answer is taken back.
        case backTapped
        /// «Пропустить» on the stack or the exclusions: on to the next step.
        case skipStepTapped
        case exclusionToggled(ExclusionChip)
        case maxAgeSelected(AgeLimit)
        /// «Готово» on the exclusions.
        case finishTapped
        /// «К рекомендациям» at the end.
        case closeTapped
    }

    private enum CancelID { case load }

    @Dependency(\.recommender) private var recommender

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Offered is offered, whatever happens next.
                Defaults[.recOnboardingOffered] = true
                guard state.isLoading else { return .none }

                return .run { send in
                    async let snapshot = recommender.home(false)
                    async let ownTitles = recommender.onboardingStack()
                    let profile = await snapshot?.output.profile ?? .empty
                    let stack = await Array(ownTitles.prefix(TasteOnboardingRules.stackLimit))
                    var previous: [String: Double] = [:]
                    for title in stack {
                        if let rating = await recommender.rating(title.id) { previous[title.id] = rating }
                    }
                    await send(
                        .loaded(chips: TasteSummary.chips(profile), counts: TasteSummary.counts(profile), stack: stack, previous: previous),
                        animation: .smooth(duration: 0.35)
                    )
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loaded(chips, counts, stack, previous):
                state.tasteChips = chips
                state.countsLine = counts
                state.stack = stack
                state.previousRatings = previous
                state.isLoading = false

                return .none

            case .startTapped:
                state.go(state.stack.isEmpty ? .exclusions : .stack)

                return .none

            case .skipAllTapped:
                state.isFinished = true

                return .none

            case let .choose(choice):
                guard let title = state.current else { return .none }

                state.answers.append(State.Answer(titleId: title.id, choice: choice))
                state.index += 1
                if state.index >= state.stack.count {
                    state.go(.exclusions)
                }

                guard let level = choice.tasteLevel else { return .none }

                return .run { _ in
                    await recommender.rate(title.id, level.level, .onboarding)
                }

            case .backTapped:
                guard let last = state.answers.popLast() else { return .none }

                state.index = max(0, state.index - 1)
                state.go(.stack)

                guard last.choice != .dontRemember else { return .none }

                let previous = state.previousRatings[last.titleId]
                return .run { _ in
                    if let previous {
                        await recommender.rate(last.titleId, previous, .onboarding)
                    } else {
                        await recommender.clearRating(last.titleId)
                    }
                }

            case .skipStepTapped:
                switch state.step {
                case .intro:
                    state.isFinished = true
                case .stack:
                    state.go(.exclusions)
                case .exclusions:
                    state.go(.done)
                case .done:
                    state.isFinished = true
                }

                return .none

            case let .exclusionToggled(chip):
                if state.exclusions.contains(chip) {
                    state.exclusions.remove(chip)
                } else {
                    state.exclusions.insert(chip)
                }

                return .none

            case let .maxAgeSelected(limit):
                state.maxAge = limit

                return .none

            case .finishTapped:
                let applied = ExclusionChip.apply(state.exclusions, kinds: Defaults[.recExcludedKinds], genres: Defaults[.recExcludedGenres])
                Defaults[.recExcludedKinds] = applied.kinds
                Defaults[.recExcludedGenres] = applied.genres
                Defaults[.recMaxAge] = state.maxAge.rawValue
                state.go(.done)

                // Home redraws with all of it by the time the sheet is gone.
                return .run { _ in
                    _ = await recommender.home(true)
                }

            case .closeTapped:
                state.isFinished = true

                return .none
            }
        }
    }
}

extension TasteOnboardingFeature {
    /// Whether to offer the taste stack now: once, signed in, with at least five of the user's own titles to rate (from
    /// «Досмотреть» and this Mac's history; fewer and there's nothing worth asking yet).
    static func shouldOffer() async -> Bool {
        guard TasteOnboardingRules.shouldOffer(offered: Defaults[.recOnboardingOffered], signedIn: Defaults[.isLoggedIn], ownTitles: .max) else {
            return false
        }
        @Dependency(\.recommender) var recommender
        let ownTitles = await recommender.onboardingStack().count
        return TasteOnboardingRules.shouldOffer(offered: Defaults[.recOnboardingOffered], signedIn: Defaults[.isLoggedIn], ownTitles: ownTitles)
    }
}
