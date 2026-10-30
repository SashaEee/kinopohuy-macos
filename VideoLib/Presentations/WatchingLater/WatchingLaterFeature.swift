import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct WatchingLaterFeature {
    @ObservableState
    struct State: Equatable {
        var movies: DataState<[MovieWatchLater]> = .idle
        /// The pills over the grid: everything, what's not finished, series or films.
        var filter: Filter = .all

        @Presents var alert: AlertState<Action.Alert>?

        /// The list through the chosen pill.
        var filtered: [MovieWatchLater] {
            (movies.data ?? []).filter(filter.includes)
        }
    }

    /// The TV's pills over «Досмотреть».
    enum Filter: CaseIterable, Equatable, Identifiable {
        case all, unfinished, series, films

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "Все"
            case .unfinished: "Не досмотрено"
            case .series: "Сериалы"
            case .films: "Фильмы"
            }
        }

        func includes(_ movie: MovieWatchLater) -> Bool {
            switch self {
            case .all: true
            case .unfinished: !movie.watched
            case .series: movie.isSeries
            case .films: !movie.isSeries
            }
        }
    }

    enum Action {
        case onAppear
        case reload
        case moviesLoaded(Result<[MovieWatchLater], any Error>)
        case filterSelected(Filter)
        case switchWatched(MovieWatchLater)
        case watchedSwitched(MovieWatchLater, Result<Bool, any Error>)
        case remove(MovieWatchLater)
        case removed(MovieWatchLater, Result<Bool, any Error>)
        case alert(PresentationAction<Alert>)

        enum Alert: Equatable {}
    }

    private enum CancelID { case load }

    @Dependency(\.getWatchingLaterMoviesUseCase) private var getWatchingLaterMoviesUseCase
    @Dependency(\.switchWatchedItemUseCase) private var switchWatchedItemUseCase
    @Dependency(\.removeWatchingItemUseCase) private var removeWatchingItemUseCase
    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.recommender) private var recommender

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.movies.needsLoad else {
                    // Back on «Досмотреть» (something was just watched, or marked on Home): the list catches up
                    // quietly, without the spinner.
                    guard state.movies.data != nil else { return .none }

                    return load()
                }

                return .send(.reload)

            case .reload:
                state.movies = .loading

                return load()

            case let .moviesLoaded(.success(loaded)):
                let movies = MovieWatchLater.keepingIds(loaded, from: state.movies.data ?? [])
                state.movies = .data(movies)

                #if DEBUG
                    // Test hook: KP_FORGET=<part of a title's path>,… takes those titles off the list, as «Убрать из списка» does.
                    if let keys = ProcessInfo.processInfo.environment["KP_FORGET"]?.split(separator: ",").map(String.init), !keys.isEmpty {
                        let doomed = movies.filter { movie in keys.contains { movie.watchLaterId.contains($0) } }
                        print("KP_FORGET", doomed.map(\.name))
                        return .merge(doomed.map { .send(.remove($0)) })
                    }
                #endif

                return .none

            case let .moviesLoaded(.failure(error)):
                // A quiet refresh that failed keeps what's on screen.
                guard state.movies.data == nil else { return .none }

                state.movies = .error(error)

                return .none

            case let .filterSelected(filter):
                state.filter = filter

                return .none

            case let .switchWatched(movie):
                return .run { send in
                    let result = await Result { try await switchWatchedItemUseCase(item: movie) }

                    await send(.watchedSwitched(movie, result), animation: .easeInOut)
                }

            case let .watchedSwitched(movie, .success(switched)):
                guard switched, var movies = state.movies.data, let index = movies.firstIndex(of: movie) else { return .none }

                movies[index].watched.toggle()

                if !movie.watched {
                    movies.move(fromOffsets: IndexSet(integer: index), toOffset: movies.count)
                }

                state.movies = .data(movies)

                return .none

            case let .remove(movie):
                return .run { send in
                    let result = await Result { try await removeWatchingItemUseCase(item: movie) }

                    await send(.removed(movie, result), animation: .easeInOut)
                }

            case let .removed(movie, .success(removed)):
                #if DEBUG
                    if ProcessInfo.processInfo.environment["KP_FORGET"] != nil { print("KP_FORGET removed", movie.name, removed) }
                #endif
                guard removed else { return .none }

                if var movies = state.movies.data {
                    movies.removeAll(where: { $0.id == movie.id })
                    state.movies = .data(movies)
                }

                guard let watchLaterId = movie.watchLaterId.id else { return .none }

                return .run { _ in
                    try? await database.write { db in
                        try PlayerPosition
                            .where { $0.id.id.eq(watchLaterId) }
                            .delete()
                            .execute(db)
                        try WatchHistory
                            .where { $0.id.eq(watchLaterId) }
                            .delete()
                            .execute(db)
                    }
                }

            case let .watchedSwitched(_, .failure(error)), let .removed(_, .failure(error)):
                state.alert = .error(error)

                return .none

            case .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    private func load() -> Effect<Action> {
        .run { send in
            let result = await Result { try await getWatchingLaterMoviesUseCase() }

            await send(.moviesLoaded(result), animation: .easeInOut)

            // «Досмотреть» as it is now: the recommender's strongest signal about taste.
            if case let .success(movies) = result { await recommender.captureAccountList(movies) }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
