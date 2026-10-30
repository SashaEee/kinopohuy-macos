import ComposableArchitecture
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// The last searches that led somewhere (a result was opened), newest first, eight at most.
    static let recentSearches = Key<[String]>("recent_searches", default: [])
}

@Reducer
struct SearchFeature {
    @ObservableState
    struct State: Equatable {
        var movies: DataState<[MovieSimple]> = .data([])
        var paginationState: DataPaginationState = .idle

        var title = String(localized: "key.search")

        var query = ""

        /// With nothing typed: the last searches that led somewhere, and what the site says is watched now.
        var recent: [String] = []
        var popular: DataState<[MovieSimple]> = .idle

        fileprivate var page = 1
        fileprivate var loadedQuery = ""
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case reload
        case loadMore
        case search(force: Bool)
        case moviesLoaded(isInitial: Bool, Result<[MovieSimple], any Error>)
        case popularLoaded(Result<[MovieSimple], any Error>)
        /// A result was opened: its query goes to «Недавние запросы».
        case resultOpened
        case recentTapped(String)
        case recentRemoved(String)
        case recentCleared
    }

    /// How many recent searches are kept.
    private static let recentLimit = 8

    private enum CancelID {
        case debounce
        case load
        case popular
    }

    @Dependency(\.searchUseCase) private var searchUseCase
    @Dependency(\.getWatchingNowMoviesUseCase) private var getWatchingNowMoviesUseCase
    @Dependency(\.continuousClock) private var clock

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding(\.query):
                return debounce(force: state.query.trim().isEmpty)

            case .binding:
                return .none

            case .onAppear:
                state.recent = Defaults[.recentSearches]

                let popular: Effect<Action> = state.popular.needsLoad ? loadPopular(&state) : .none

                guard state.movies.needsLoad else { return popular }

                return .merge(debounce(force: true), popular)

            case .reload:
                guard !state.query.trim().isEmpty else { return loadPopular(&state) }

                return debounce(force: true)

            case let .search(force):
                let query = state.query.trim()

                guard force || query != state.loadedQuery || state.movies.error != nil else { return .none }

                state.loadedQuery = query
                state.paginationState = .idle
                state.page = 1

                guard !query.isEmpty else {
                    state.title = String(localized: "key.search")
                    state.movies = .data([])

                    return .cancel(id: CancelID.load)
                }

                state.movies = .loading
                state.title = String(localized: "key.search.result-\(query)")

                return load(query: query, page: state.page, isInitial: true)

            case .loadMore:
                guard state.paginationState == .idle, !state.loadedQuery.isEmpty else { return .none }

                state.paginationState = .loading

                return load(query: state.loadedQuery, page: state.page, isInitial: false)

            case let .moviesLoaded(isInitial, result):
                if case .success = result {
                    state.page += 1
                }

                state.paginationState = state.movies.receivePage(result, isInitial: isInitial, emptyPageIsError: true)

                return .none

            case let .popularLoaded(result):
                state.popular = switch result {
                case let .success(movies): .data(Array(movies.prefix(20)))
                case let .failure(error): .error(error)
                }

                return .none

            case .resultOpened:
                let query = state.loadedQuery.trim()
                guard !query.isEmpty else { return .none }

                saveRecent([query] + state.recent.filter { $0.caseInsensitiveCompare(query) != .orderedSame }, &state)

                return .none

            case let .recentTapped(query):
                state.query = query

                return debounce(force: true)

            case let .recentRemoved(query):
                saveRecent(state.recent.filter { $0 != query }, &state)

                return .none

            case .recentCleared:
                saveRecent([], &state)

                return .none
            }
        }
    }

    private func saveRecent(_ recent: [String], _ state: inout State) {
        state.recent = Array(recent.prefix(Self.recentLimit))
        Defaults[.recentSearches] = state.recent
    }

    /// «Популярно сейчас»: the site's «смотрят сейчас», its first page.
    private func loadPopular(_ state: inout State) -> Effect<Action> {
        state.popular = .loading

        return .run { send in
            let result = await Result { try await getWatchingNowMoviesUseCase(page: 1, genre: 0) }

            await send(.popularLoaded(result), animation: .easeInOut)
        }
        .cancellable(id: CancelID.popular, cancelInFlight: true)
    }

    private func debounce(force: Bool) -> Effect<Action> {
        .run { send in
            if !force {
                try await clock.sleep(for: .milliseconds(500))
            }

            await send(.search(force: force), animation: .easeInOut)
        }
        .cancellable(id: CancelID.debounce, cancelInFlight: true)
    }

    private func load(query: String, page: Int, isInitial: Bool) -> Effect<Action> {
        .run { send in
            let result = await Result { try await searchUseCase(query: query, page: page) }

            await send(.moviesLoaded(isInitial: isInitial, result), animation: .easeInOut)
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
