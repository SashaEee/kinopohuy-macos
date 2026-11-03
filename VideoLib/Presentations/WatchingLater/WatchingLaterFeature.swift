import ComposableArchitecture
import Defaults
import RecommenderCore
import SQLiteData
import SwiftUI

extension Defaults.Keys {
    /// «Бросил» also takes the title off the site's «Досмотреть» (asked once; nil until answered).
    static let recDropRemovesFromSite = Key<Bool?>("rec_drop_removes_from_site")
}

@Reducer
struct WatchingLaterFeature {
    @ObservableState
    struct State: Equatable {
        var movies: DataState<[MovieWatchLater]> = .idle
        /// The pills over the grid: everything, what's not finished, series or films.
        var filter: Filter = .all
        /// The segment pill beside them («Продолжить», «Можно начать», «Похоже, бросили?», «Досмотрено»); nil: any.
        var segment: WatchingSegment?
        /// Each title's segment, by its path (none: taken off the row or dropped).
        var segments: [String: WatchingSegment] = [:]
        /// Titles taken off the row («Убрать из ряда») or dropped («Бросил»), by number.
        var setAside: Set<String> = []
        /// Films rated here (or «Уже смотрел»): under «Досмотрено» before the site says so.
        var done: Set<String> = []
        /// This Mac's history, for how far a film got and when it last played.
        var history = KPWatchHistory()

        @Presents var alert: AlertState<Action.Alert>?
        @Presents var dropDialog: ConfirmationDialogState<Action.DropDialog>?

        /// The list through the chosen pills.
        var filtered: [MovieWatchLater] {
            (movies.data ?? []).filter { filter.includes($0) && (segment == nil || segments[$0.watchLaterId] == segment) }
        }

        /// How many the segment holds (within the chosen filter, as the grid would show).
        func count(_ segment: WatchingSegment) -> Int {
            (movies.data ?? []).count { filter.includes($0) && segments[$0.watchLaterId] == segment }
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
        /// A segment pill; the chosen one again clears it.
        case segmentSelected(WatchingSegment)
        case historyChanged(KPWatchHistory)
        case setAsideLoaded(ContinueStatus)
        /// «Убрать из ряда», «Это смотрел не я», «Не моё» from a card (recorded by the card's marks).
        case titleAction(MovieWatchLater, TitleAction)
        /// «Вернуть» on a card: it's back in its segment.
        case titleRestored(String)
        /// «Бросил»: a weak minus, out of «Похоже, бросили?», and (asked once) off the site's list too.
        case dropTapped(MovieWatchLater)
        case dropDialog(PresentationAction<DropDialog>)
        case switchWatched(MovieWatchLater)
        case watchedSwitched(MovieWatchLater, Result<Bool, any Error>)
        case remove(MovieWatchLater)
        case removed(MovieWatchLater, Result<Bool, any Error>)
        case alert(PresentationAction<Alert>)

        enum Alert: Equatable {}

        enum DropDialog: Equatable {
            case removeFromSite(MovieWatchLater)
            case keepOnSite
        }
    }

    private enum CancelID { case load, setAside }

    @Dependency(\.getWatchingLaterMoviesUseCase) private var getWatchingLaterMoviesUseCase
    @Dependency(\.switchWatchedItemUseCase) private var switchWatchedItemUseCase
    @Dependency(\.removeWatchingItemUseCase) private var removeWatchingItemUseCase
    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.recommender) private var recommender
    @Dependency(\.date.now) private var now

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
                classify(&state)
                let setAside = loadSetAside(movies)

                #if DEBUG
                    // Test hook: KP_FORGET=<part of a title's path>,… takes those titles off the list, as «Убрать из списка» does.
                    if let keys = ProcessInfo.processInfo.environment["KP_FORGET"]?.split(separator: ",").map(String.init), !keys.isEmpty {
                        let doomed = movies.filter { movie in keys.contains { movie.watchLaterId.contains($0) } }
                        print("KP_FORGET", doomed.map(\.name))
                        return .merge(doomed.map { .send(.remove($0)) } + [setAside])
                    }
                #endif

                return setAside

            case let .moviesLoaded(.failure(error)):
                // A quiet refresh that failed keeps what's on screen.
                guard state.movies.data == nil else { return .none }

                state.movies = .error(error)

                return .none

            case let .filterSelected(filter):
                state.filter = filter

                return .none

            case let .segmentSelected(segment):
                state.segment = state.segment == segment ? nil : segment

                return .none

            case let .historyChanged(history):
                guard history != state.history else { return .none }

                state.history = history
                classify(&state)

                return .none

            case let .setAsideLoaded(status):
                state.setAside = status.setAside
                state.done = status.done
                classify(&state)

                return .none

            case let .titleAction(movie, action):
                // The card records it (and can take it back); here it only moves between segments.
                guard action == .continueHidden || action == .dropped, let id = movie.watchLaterId.id else { return .none }

                state.setAside.insert(id)
                classify(&state)

                return .none

            case let .titleRestored(id):
                guard state.setAside.remove(id) != nil else { return .none }

                classify(&state)

                return .none

            case let .dropTapped(movie):
                guard let id = movie.watchLaterId.id else { return .none }

                state.setAside.insert(id)
                classify(&state)

                let record: Effect<Action> = .run { _ in
                    await RecCardMarks.shared.apply(.dropped, to: id)
                }

                switch Defaults[.recDropRemovesFromSite] {
                case true?:
                    return .merge(record, .send(.remove(movie)))
                case false?:
                    return record
                case nil:
                    state.dropDialog = ConfirmationDialogState {
                        TextState(verbatim: "Убрать «\(movie.name)» и из списка на сайте?")
                    } actions: {
                        ButtonState(role: .destructive, action: .removeFromSite(movie)) {
                            TextState(verbatim: "Убрать и с сайта")
                        }
                        ButtonState(action: .keepOnSite) {
                            TextState(verbatim: "Оставить на сайте")
                        }
                    } message: {
                        TextState(verbatim: "Здесь он уже не будет мозолить глаза. Ответ запомним, и дальше «Бросил» будет поступать так же.")
                    }

                    return record
                }

            case let .dropDialog(.presented(.removeFromSite(movie))):
                Defaults[.recDropRemovesFromSite] = true

                return .send(.remove(movie))

            case .dropDialog(.presented(.keepOnSite)):
                Defaults[.recDropRemovesFromSite] = false

                return .none

            case .dropDialog:
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
                classify(&state)

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
                    classify(&state)
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
        .ifLet(\.$dropDialog, action: \.dropDialog)
    }

    /// Sorts the list into segments from the site's cards, this Mac's history and what was set aside.
    private func classify(_ state: inout State) {
        let now = self.now
        var segments: [String: WatchingSegment] = [:]
        for movie in state.movies.data ?? [] {
            let id = movie.watchLaterId.id
            let entry = state.history[id]
            let playedAt = entry.map { Date(timeIntervalSince1970: $0.updatedAt) }
            let siteDate = ActivityDate.parse(movie.date, now: now)
            let place = movie.watchingEpisode
            let filmFraction: Double? = movie.isSeries ? nil : entry.flatMap { entry in
                if entry.position >= PlayerFeature.watchedMark { return 1 }
                guard entry.position >= 30, entry.duration > 0 else { return nil }
                return min(1, entry.position / entry.duration)
            }
            let facts = WatchingFacts(
                watched: movie.watched || (id.map(state.done.contains) ?? false),
                lastActivity: [playedAt, siteDate].compactMap { $0 }.max(),
                isSeries: movie.isSeries,
                season: place?.season,
                episode: place?.episode,
                filmFraction: filmFraction,
                playedHere: (entry?.position ?? 0) >= 30,
                isSetAside: id.map(state.setAside.contains) ?? false
            )
            segments[movie.watchLaterId] = WatchingSegment.classify(facts, now: now)
        }
        state.segments = segments
    }

    /// Which titles were taken off the row or dropped, read from the recommender.
    private func loadSetAside(_ movies: [MovieWatchLater]) -> Effect<Action> {
        .run { send in
            let items = movies.compactMap { movie in movie.watchLaterId.id.map { ContinueItem(titleId: $0, isSeries: movie.isSeries) } }
            await send(.setAsideLoaded(await recommender.continueStatus(items)), animation: .smooth(duration: 0.3))
        }
        .cancellable(id: CancelID.setAside, cancelInFlight: true)
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
