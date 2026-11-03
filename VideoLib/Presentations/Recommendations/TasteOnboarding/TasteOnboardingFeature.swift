import ComposableArchitecture
import Defaults
import Foundation
import RecommenderCore

/// «Уточнить вкус за минуту»: «Что вам близко?» as bubbles (what the data says is pre-selected; a click adds or
/// removes, a right click is «Не моё»), then a deck of your own titles — only what was played — to rate with one key
/// each, with «Вкус изучен на N %» and what Home would recommend right now updating after every answer; then «Что
/// хочется посмотреть?», a grid of unseen titles to tick (interest, not a rating); then what never to show. Every answer
/// counts the moment it's given, so leaving halfway keeps what was said; «Пропустить» is on every step. Offered once
/// (`shouldOffer`), and from Settings.
@Reducer
struct TasteOnboardingFeature {
    enum Step: Int, CaseIterable, Equatable, Sendable {
        case intro
        case stack
        /// «Что хочется посмотреть?»: unseen titles to tick.
        case interest
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
        /// «Что вам близко?».
        var bubbles: [Bubble] = []
        /// «Вкус изучен на N %», after each answer.
        var confidence: Double = 0
        /// «Сейчас мы бы посоветовали»: the first of «Для вас» as things stand, after each answer.
        var preview: [TitleFeatures] = []
        /// «Что хочется посмотреть?» and what's ticked.
        var interest: [TitleFeatures] = []
        var interested: Set<String> = []
        /// Done or skipped: the view closes.
        var isFinished = false

        struct Answer: Equatable, Sendable {
            let titleId: String
            let choice: OnboardingChoice
        }

        /// A bubble of «Что вам близко?».
        struct Bubble: Equatable, Identifiable, Sendable {
            let feature: FeatureKey
            let name: String
            /// The data already says it's liked (shown chosen until the user says otherwise).
            let likedByData: Bool
            /// 0…1, for its size.
            let strength: Double
            var state: BubbleState

            var id: FeatureKey { feature }
        }

        enum BubbleState: Equatable, Sendable {
            case neutral
            case liked
            case notForMe
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
        case loaded(chips: [String], counts: String?, stack: [TitleFeatures], previous: [String: Double], bubbles: [State.Bubble])
        /// A click on a bubble: chosen ↔ not.
        case bubbleTapped(FeatureKey)
        /// Right click → «Не моё» (again: back to neutral).
        case bubbleNotForMe(FeatureKey)
        case interestLoaded([TitleFeatures])
        case interestToggled(String)
        case progress(confidence: Double, preview: [TitleFeatures])
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

    private enum CancelID { case load, progress }

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
                    async let features = recommender.tasteBubbles()
                    async let overrides = recommender.overrides()
                    let home = await snapshot
                    let profile = home?.output.profile ?? .empty
                    let stack = await Array(ownTitles.prefix(TasteOnboardingRules.stackLimit))
                    var previous: [String: Double] = [:]
                    for title in stack {
                        if let rating = await recommender.rating(title.id) { previous[title.id] = rating }
                    }
                    let bubbles = await Self.bubbles(features, overrides: overrides)
                    await send(
                        .loaded(chips: TasteSummary.chips(profile), counts: TasteSummary.counts(profile), stack: stack, previous: previous, bubbles: bubbles),
                        animation: .smooth(duration: 0.35)
                    )
                    await send(.progress(confidence: await recommender.tasteConfidence(), preview: Self.preview(home)))
                    await send(.interestLoaded(await recommender.interestGrid()))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loaded(chips, counts, stack, previous, bubbles):
                state.tasteChips = chips
                state.countsLine = counts
                state.stack = stack
                state.previousRatings = previous
                state.bubbles = bubbles
                state.isLoading = false
                #if DEBUG
                    // KP_TASTE=stack: straight to the deck (to look at it).
                    if ProcessInfo.processInfo.environment["KP_TASTE"] == "stack", !stack.isEmpty { state.go(.stack) }
                #endif

                return .none

            case let .bubbleTapped(feature):
                guard let index = state.bubbles.firstIndex(where: { $0.feature == feature }) else { return .none }

                let bubble = state.bubbles[index]
                let next: State.BubbleState = bubble.state == .liked ? .neutral : .liked
                state.bubbles[index].state = next

                return .merge(setBubble(bubble, to: next), refreshProgress())

            case let .bubbleNotForMe(feature):
                guard let index = state.bubbles.firstIndex(where: { $0.feature == feature }) else { return .none }

                let bubble = state.bubbles[index]
                let next: State.BubbleState = bubble.state == .notForMe ? .neutral : .notForMe
                state.bubbles[index].state = next

                return .merge(setBubble(bubble, to: next), refreshProgress())

            case let .interestLoaded(titles):
                state.interest = titles
                #if DEBUG
                    // KP_TASTE=interest: straight to the grid (to look at it).
                    if ProcessInfo.processInfo.environment["KP_TASTE"] == "interest", !titles.isEmpty { state.go(.interest) }
                #endif

                return .none

            case let .interestToggled(titleId):
                let picked = !state.interested.contains(titleId)
                if picked { state.interested.insert(titleId) } else { state.interested.remove(titleId) }

                return .merge(
                    .run { _ in
                        if picked {
                            await recommender.feedback(titleId, .interested)
                        } else {
                            await recommender.removeFeedback(titleId, .interested)
                        }
                    },
                    refreshProgress()
                )

            case let .progress(confidence, preview):
                state.confidence = confidence
                if !preview.isEmpty { state.preview = preview }

                return .none

            case .startTapped:
                state.go(!state.stack.isEmpty ? .stack : state.interest.isEmpty ? .exclusions : .interest)

                return .none

            case .skipAllTapped:
                state.isFinished = true

                return .none

            case let .choose(choice):
                guard let title = state.current else { return .none }

                state.answers.append(State.Answer(titleId: title.id, choice: choice))
                state.index += 1
                if state.index >= state.stack.count {
                    state.go(state.interest.isEmpty ? .exclusions : .interest)
                }

                guard let level = choice.tasteLevel else { return .none }

                return .run { send in
                    await recommender.rate(title.id, level.level, .onboarding)
                    await send(.progress(confidence: await recommender.tasteConfidence(), preview: Self.preview(await recommender.home(false))), animation: .smooth(duration: 0.45))
                }
                .cancellable(id: CancelID.progress, cancelInFlight: true)

            case .backTapped:
                guard let last = state.answers.popLast() else { return .none }

                state.index = max(0, state.index - 1)
                state.go(.stack)

                guard last.choice != .dontRemember else { return .none }

                let previous = state.previousRatings[last.titleId]
                return .run { send in
                    if let previous {
                        await recommender.rate(last.titleId, previous, .onboarding)
                    } else {
                        await recommender.clearRating(last.titleId)
                    }
                    await send(.progress(confidence: await recommender.tasteConfidence(), preview: Self.preview(await recommender.home(false))), animation: .smooth(duration: 0.45))
                }

            case .skipStepTapped:
                switch state.step {
                case .intro:
                    state.isFinished = true
                case .stack:
                    state.go(state.interest.isEmpty ? .exclusions : .interest)
                case .interest:
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
    /// A bubble's new state as a taste override: chosen = «больше такого» (nothing to store when the data already likes
    /// it), «Не моё» = muted, back to neutral = the override goes (a liked-by-data one unchosen is muted for 90 days:
    /// «не так уж и нравится»).
    private func setBubble(_ bubble: State.Bubble, to state: State.BubbleState) -> Effect<Action> {
        @Dependency(\.recommender) var recommender
        @Dependency(\.date.now) var now
        let feature = bubble.feature
        let until = now.addingTimeInterval(90 * 24 * 3600).timeIntervalSince1970
        return .run { _ in
            switch state {
            case .liked:
                if bubble.likedByData {
                    await recommender.clearOverride(feature)
                } else {
                    await recommender.override(TasteOverride(feature: feature, mode: .more))
                }
            case .notForMe:
                await recommender.override(TasteOverride(feature: feature, mode: .mute))
            case .neutral:
                if bubble.likedByData {
                    await recommender.override(TasteOverride(feature: feature, mode: .mute, until: until))
                } else {
                    await recommender.clearOverride(feature)
                }
            }
        }
    }

    private func refreshProgress() -> Effect<Action> {
        @Dependency(\.recommender) var recommender
        return .run { send in
            await send(.progress(confidence: await recommender.tasteConfidence(), preview: Self.preview(await recommender.home(false))), animation: .smooth(duration: 0.45))
        }
        .cancellable(id: CancelID.progress, cancelInFlight: true)
    }

    /// The bubbles with what the user set before: «больше» / «закрепить» chosen, «приглушить» / «исключить» «Не моё»;
    /// otherwise as the data says.
    static func bubbles(_ features: [FeatureAffinity], overrides: [TasteOverride]) -> [State.Bubble] {
        let set = Dictionary(overrides.map { ($0.feature, $0.mode) }, uniquingKeysWith: { _, last in last })
        let strongest = max(0.01, features.map { abs($0.affinity) }.max() ?? 0.01)
        // Only the clearest few are chosen up front: someone who watches a bit of everything would otherwise get every
        // bubble ticked, and a choice that's already made says nothing.
        let leaders = features.filter { $0.affinity > 0.15 && $0.support >= 2 }.prefix(TasteOnboardingRules.preselectedBubbles).map(\.feature)
        return features.map { feature in
            let rank = leaders.firstIndex(of: feature.feature)
            let likedByData = rank != nil
            let state: State.BubbleState = switch set[feature.feature] {
            case .more, .pin: .liked
            case .mute, .exclude: .notForMe
            case nil: likedByData ? .liked : feature.affinity < -0.1 ? .notForMe : .neutral
            }
            return State.Bubble(
                feature: feature.feature, name: feature.name, likedByData: likedByData,
                // The leaders large, in their order; the rest small, a little larger the more the data leans.
                strength: rank.map { 1 - Double($0) * 0.12 } ?? min(0.3, 0.3 * abs(feature.affinity) / strongest), state: state
            )
        }
    }

    /// «Сейчас мы бы посоветовали»: the first eight of «Для вас».
    static func preview(_ snapshot: RecSnapshot?) -> [TitleFeatures] {
        guard let snapshot, let row = snapshot.output.page.rows.first(where: { $0.kind == .forYou }) ?? snapshot.output.page.rows.first else { return [] }
        return row.items.prefix(8).compactMap { snapshot.titles[$0.titleId] }
    }

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
