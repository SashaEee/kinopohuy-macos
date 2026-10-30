import ComposableArchitecture
import RecommenderCore
import SwiftUI

/// «Выбери за меня» and «Что хочется?» in one sheet (⌘J, ⌘K with the cursor in the field). A pick is ready the moment it
/// opens, chosen for the hour and the day; words, chips and the critique buttons («Полегче», «Покороче») change the
/// request, and «Другое» moves on without changing taste. Nothing is kept once the sheet closes, apart from explicit
/// feedback («Не моё», «Не сегодня», «Уже смотрел»).
@Reducer
struct PickForMeFeature {
    @ObservableState
    struct State: Equatable {
        /// Opened with ⌘K: the cursor goes straight to the field.
        var focusText = false
        /// ⌘K pressed again while open: the cursor goes back to the field.
        var focusRequests = 0
        var text = ""
        /// What's asked now: the hour's defaults, then words, chips and critiques on top.
        var intent: WatchIntent = .empty
        /// «Понял так: …», each removable.
        var chips: [IntentChip] = []
        var pool: PickPool = .mix
        /// «КП или IMDb от 7».
        var highRating = false

        var result: PickResult?
        var titles: [String: TitleFeatures] = [:]
        var isPicking = false
        /// A line under the field: the answer to an off-topic request, what was understood, what was dropped.
        var note: String?
        /// The last few exchanges («Вы: без драмы» → «Убрал драму»), the whole conversation the sheet keeps.
        var turns: [Turn] = []
        /// «Уже смотрел» on a title: its three rating buttons, once.
        var ratePrompt: RatePrompt?

        /// Titles shown this session (never shown again in it), «Другое» presses, the session's seed.
        var shown: [String] = []
        var skips = 0
        var seed: UInt64 = 0
        var askedQuestion = false

        var main: TitleFeatures? { result?.main.flatMap { titles[$0.titleId] } }
    }

    struct Turn: Equatable, Identifiable {
        let id: Int
        let you: String
        let reply: String
    }

    struct RatePrompt: Equatable {
        let titleId: String
        let name: String
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case submit
        case parsed(text: String, ParsedRequest)
        case removeChip(IntentChip)
        case setKinds(Set<TitleKind>?)
        case setTime(TimeBudget?)
        case setMood(Mood)
        case setCompany(Company?)
        case picked(PickResult, [String: TitleFeatures])
        case watch(String)
        case open(String)
        case promote(String)
        case other
        case notToday
        case notMe
        case alreadySeen
        case rateSeen(Double?)
        case critique(Critique, label: String)
        case critiqued(label: String, WatchIntent)
        case answer(ClarifyingQuestion.Option)
        case delegate(Delegate)

        enum Delegate {
            case open(MovieSimple)
            case watch(MovieSimple)
        }
    }

    private enum CancelID { case pick, parse }

    @Dependency(\.recommender) private var recommender
    @Dependency(\.date.now) private var now

    var body: some ReducerOf<Self> {
        BindingReducer()
            .onChange(of: \.pool) { _, _ in
                Reduce { state, _ in pick(&state) }
            }
            .onChange(of: \.highRating) { _, _ in
                Reduce { state, _ in pick(&state) }
            }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                guard state.result == nil else { return .none }

                state.seed = UInt64(max(0, now.timeIntervalSince1970))
                state.intent = recommender.contextIntent()
                state.chips = IntentChips.chips(for: state.intent)

                return pick(&state)

            case .submit:
                let text = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    return state.result?.main.map { .send(.watch($0.titleId)) } ?? .none
                }

                state.text = ""

                return .run { send in
                    await send(.parsed(text: text, await recommender.parse(text)))
                }
                .cancellable(id: CancelID.parse, cancelInFlight: true)

            case let .parsed(text, parsed):
                if parsed.offTopic {
                    state.note = "Я подбираю, что посмотреть: скажите настроение, время или на что похоже"
                    remember(&state, you: text, reply: "Не по теме")
                    return .none
                }

                state.intent = state.intent.merging(parsed.intent)
                state.chips = IntentChips.chips(for: state.intent)
                state.skips = 0

                let understood = IntentChips.chips(for: parsed.intent).map(\.label)
                var reply = understood.isEmpty ? "Не всё понял, но попробую" : "Понял: " + understood.joined(separator: " · ")
                if !parsed.similarQueries.isEmpty, parsed.intent.similarTo.isEmpty {
                    reply += " · «\(parsed.similarQueries[0])» пока не нашёл в каталоге"
                }
                state.note = nil
                remember(&state, you: text, reply: reply)

                return pick(&state)

            case let .removeChip(chip):
                state.intent = IntentChips.removing(chip, from: state.intent)
                state.chips = IntentChips.chips(for: state.intent)
                remember(&state, you: "без «\(chip.label)»", reply: "Убрал «\(chip.label)»")

                return pick(&state)

            case let .setKinds(kinds):
                state.intent.kinds = kinds
                state.intent.confidence[.kinds] = 1
                return chipsChanged(&state)

            case let .setTime(time):
                state.intent.time = time
                state.intent.confidence[.time] = 1
                return chipsChanged(&state)

            case let .setMood(mood):
                state.intent.moods = [mood: 1]
                state.intent.confidence[.moods] = 1
                return chipsChanged(&state)

            case let .setCompany(company):
                state.intent.company = company
                state.intent.confidence[.company] = 1
                return chipsChanged(&state)

            case let .picked(result, titles):
                state.isPicking = false
                state.result = result
                state.titles.merge(titles) { _, new in new }
                if let main = result.main, !state.shown.contains(main.titleId) {
                    state.shown.append(main.titleId)
                }
                if result.showGrid {
                    for alternative in result.alternatives where !state.shown.contains(alternative.titleId) {
                        state.shown.append(alternative.titleId)
                    }
                }
                if result.question != nil { state.askedQuestion = true }

                if !result.relaxed.isEmpty, result.main != nil {
                    state.note = "Ровно такого нет — " + result.relaxed.map(\.label).joined(separator: ", ")
                } else if result.main == nil {
                    state.note = nil
                }

                let ids = ([result.main] + result.alternatives).compactMap { $0?.titleId }
                return .run { _ in await recommender.recordImpressions(ids, "pick") }

            case let .watch(titleId):
                guard let title = state.titles[titleId] else { return .none }

                return .merge(
                    .run { _ in await recommender.markOpened(titleId) },
                    .send(.delegate(.watch(title.simple)))
                )

            case let .open(titleId):
                guard let title = state.titles[titleId] else { return .none }

                return .merge(
                    .run { _ in await recommender.markOpened(titleId) },
                    .send(.delegate(.open(title.simple)))
                )

            case let .promote(titleId):
                // An «Или:» clicked: it becomes the main pick, the main one moves to its place.
                guard var result = state.result, let index = result.alternatives.firstIndex(where: { $0.titleId == titleId }) else { return .none }

                let alternative = result.alternatives[index]
                if let main = result.main {
                    result.alternatives[index] = main
                } else {
                    result.alternatives.remove(at: index)
                }
                result.main = alternative
                state.result = result
                if !state.shown.contains(titleId) { state.shown.append(titleId) }

                return .none

            case .other:
                state.skips += 1
                state.ratePrompt = nil

                return pick(&state)

            case .notToday:
                guard let main = state.result?.main else { return .none }

                let id = main.titleId
                state.ratePrompt = nil
                remember(&state, you: "Не сегодня", reply: "Уберу «\(name(state, id))» на неделю")

                return .merge(
                    .run { _ in await recommender.feedback(id, .notToday) },
                    pick(&state)
                )

            case .notMe:
                guard let main = state.result?.main else { return .none }

                let id = main.titleId
                state.ratePrompt = nil
                remember(&state, you: "Не моё", reply: "Больше не покажу «\(name(state, id))»")

                return .merge(
                    .run { _ in await recommender.rate(id, -2, .app) },
                    pick(&state)
                )

            case .alreadySeen:
                guard let main = state.result?.main else { return .none }

                let id = main.titleId
                state.ratePrompt = RatePrompt(titleId: id, name: name(state, id))

                return .merge(
                    .run { _ in await recommender.feedback(id, .seen) },
                    pick(&state)
                )

            case let .rateSeen(level):
                guard let prompt = state.ratePrompt else { return .none }

                state.ratePrompt = nil
                guard let level else { return .none }

                return .run { _ in await recommender.rate(prompt.titleId, level, .app) }

            case let .critique(critique, label):
                let intent = state.intent
                let current = state.result?.main?.titleId

                return .run { send in
                    await send(.critiqued(label: label, await recommender.critique(critique, intent, current)))
                }

            case let .critiqued(label, intent):
                state.intent = intent
                state.chips = IntentChips.chips(for: intent)
                state.skips = 0
                remember(&state, you: label, reply: IntentChips.chips(for: intent).map(\.label).joined(separator: " · "))

                return pick(&state)

            case let .answer(option):
                state.intent = state.intent.merging(option.intent)
                state.chips = IntentChips.chips(for: state.intent)
                remember(&state, you: option.label, reply: "Хорошо")

                return pick(&state)

            case .delegate:
                return .none
            }
        }
    }

    private func chipsChanged(_ state: inout State) -> Effect<Action> {
        state.chips = IntentChips.chips(for: state.intent)
        state.skips = 0
        return pick(&state)
    }

    private func pick(_ state: inout State) -> Effect<Action> {
        state.isPicking = true

        var intent = state.intent
        if state.highRating, intent.minRating == nil {
            intent.minRating = RatingFloor(source: .any, value: 7)
        }
        let request = PickRequest(
            intent: intent,
            pool: state.pool,
            shown: state.shown,
            skips: state.skips,
            seed: state.seed,
            askedQuestion: state.askedQuestion
        )
        let known = Set(state.titles.keys)

        return .run { send in
            let result = await recommender.pick(request)
            var titles: [String: TitleFeatures] = [:]
            for id in ([result.main] + result.alternatives).compactMap({ $0?.titleId }) where !known.contains(id) {
                titles[id] = await recommender.title(id)
            }

            await send(.picked(result, titles), animation: .smooth(duration: 0.35))
        }
        .cancellable(id: CancelID.pick, cancelInFlight: true)
    }

    private func remember(_ state: inout State, you: String, reply: String) {
        let id = (state.turns.last?.id ?? 0) + 1
        state.turns.append(Turn(id: id, you: you, reply: reply))
        if state.turns.count > 3 { state.turns.removeFirst(state.turns.count - 3) }
    }

    private func name(_ state: State, _ titleId: String) -> String {
        state.titles[titleId]?.name ?? "это"
    }
}

extension WatchIntent {
    /// This request with another on top: what the other says replaces what was here (a new time, a new kind), the
    /// rest stays («а теперь комедию» keeps «до 90 минут»).
    func merging(_ other: WatchIntent) -> WatchIntent {
        var merged = self
        if let kinds = other.kinds { merged.kinds = kinds }
        if !other.moods.isEmpty { merged.moods = other.moods }
        if let company = other.company { merged.company = company }
        if let time = other.time { merged.time = time }
        if !other.genres.isEmpty {
            merged.genres.include.formUnion(other.genres.include)
            merged.genres.exclude.formUnion(other.genres.exclude)
            merged.genres.include.subtract(other.genres.exclude)
            merged.genres.exclude.subtract(other.genres.include)
        }
        if !other.countries.isEmpty {
            merged.countries.include.formUnion(other.countries.include)
            merged.countries.exclude.formUnion(other.countries.exclude)
            merged.countries.include.subtract(other.countries.exclude)
        }
        if let years = other.years { merged.years = years }
        if let minRating = other.minRating { merged.minRating = minRating }
        if let familiarity = other.familiarity { merged.familiarity = familiarity }
        if !other.similarTo.isEmpty { merged.similarTo = other.similarTo }
        if !other.people.isEmpty { merged.people = other.people }
        for term in other.avoid where !merged.avoid.contains(term) { merged.avoid.append(term) }
        if let freeText = other.freeText, !freeText.isEmpty { merged.freeText = freeText }
        merged.confidence.merge(other.confidence) { max($0, $1) }
        return merged
    }
}
