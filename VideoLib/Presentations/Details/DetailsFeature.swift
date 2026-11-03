import ComposableArchitecture
import Defaults
import SwiftUI

@Reducer
struct DetailsFeature {
    @Reducer
    enum Destination {
        case bookmarks(BookmarksSheetFeature)
        case createBookmark(CreateBookmarkFeature)
        case watch(MovieSelectionFeature)
        case download(MovieSelectionFeature)
        case openExternalPlayer(MovieSelectionFeature)
    }

    @ObservableState
    struct State: Equatable {
        let id: String
        let title: String?
        /// The card's poster: the page shows it at once, before the title's own page is in.
        let poster: String?

        var details: DataState<MovieDetailed> = .idle
        /// From Rutube (see RutubeTrailers); its stream once «Трейлер» is pressed.
        var trailer: RutubeTrailers.Trailer?
        /// The trailer is being looked for: its button keeps its place (dimmed), so the row doesn't shift when it's found.
        var trailerSearching = false
        var trailerStream: URL?

        /// Start playing as soon as the page and its stream are in («Смотреть» on Home's banner).
        var autoWatch: Bool

        /// The voice-over, season and episode chosen on the page itself, with the stream already fetched, so
        /// «Смотреть» and an episode's tile start playback in one press.
        var selection: MovieSelectionFeature.State?

        /// In any of your bookmark folders (signed in): «В закладках» on the button. nil until it's known.
        var isBookmarked: Bool?

        /// «Не моё · Нравится · Обожаю» and «…» next to the site's rating.
        var feedback: FeedbackBarFeature.State

        @Presents var alert: AlertState<Action.Alert>?
        @Presents var destination: Destination.State?

        init(movie: MovieSimple, autoWatch: Bool = false) {
            id = movie.movieId
            title = movie.name
            poster = movie.poster
            self.autoWatch = autoWatch
            feedback = FeedbackBarFeature.State(titleId: movie.movieId.id)
        }

        var movieId: String {
            details.data?.movieId ?? id
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case reload
        case detailsLoaded(Result<MovieDetailed, any Error>)
        case selection(MovieSelectionFeature.Action)
        case autoWatchHandled
        case trailerLoaded(RutubeTrailers.Trailer?)
        case trailerTapped
        case trailerStreamLoaded(Result<URL, any Error>)
        case rate(Int)
        case rated(Result<(Float?, String?)?, any Error>)
        case bookmarkStateLoaded(Result<[Bookmark], any Error>)
        case bookmarksTapped
        case watchTapped
        case downloadTapped
        case openExternalPlayerTapped
        case feedback(FeedbackBarFeature.Action)
        case push(Destinations)
        case delegate(Delegate)
        case alert(PresentationAction<Alert>)
        case destination(PresentationAction<Destination.Action>)

        enum Alert: Equatable {}

        enum Delegate {
            case push(Destinations)
        }
    }

    private enum CancelID { case load, rate, trailer, bookmarks }

    @Dependency(\.getMovieDetailsUseCase) private var getMovieDetailsUseCase
    @Dependency(\.getMovieBookmarksUseCase) private var getMovieBookmarksUseCase
    @Dependency(\.rateUseCase) private var rateUseCase
    @Dependency(\.recommender) private var recommender

    var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(state: \.feedback, action: \.feedback) {
            FeedbackBarFeature()
        }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                guard state.details.needsLoad else { return .none }

                return .send(.reload)

            case .reload:
                state.details = .loading
                state.selection = nil
                state.trailerSearching = false

                return .run { [id = state.id] send in
                    let result = await Result { try await getMovieDetailsUseCase(movieId: id) }

                    await send(.detailsLoaded(result), awaitingAnimation: .smooth(duration: 0.55))

                    guard case let .success(details) = result else { return }

                    // The page goes into the recommender's catalogue (no extra request), and the title counts as opened.
                    await recommender.captureDetails(details)
                    if let titleId = details.movieId.id { await recommender.markOpened(titleId) }

                    let names = [details.nameRussian] + (details.nameOriginal.map { [$0] } ?? [])
                    let trailer = await RutubeTrailers.find(names: names, year: details.displayYear, series: details.series != nil)
                    await send(.trailerLoaded(trailer), animation: .smooth(duration: 0.4))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .detailsLoaded(.success(details)):
                state.details = .data(details)
                state.trailerSearching = state.trailer == nil

                // Whether it's bookmarked: the folders come with the page, asked for once it's in.
                let bookmarks: Effect<Action> = Defaults[.isLoggedIn] ? .run { [id = state.id] send in
                    let result = await Result { try await getMovieBookmarksUseCase(movieId: id) }

                    await send(.bookmarkStateLoaded(result), animation: .smooth(duration: 0.3))
                }
                .cancellable(id: CancelID.bookmarks, cancelInFlight: true) : .none

                guard details.available, details.voiceActing?.isEmpty == false else {
                    state.autoWatch = false
                    return bookmarks
                }

                // It starts from this very page rather than fetching it again.
                state.selection = MovieSelectionFeature.State(id: state.movieId, isEmbedded: true, details: details)

                return .merge(.send(.selection(.onAppear)), bookmarks)

            case let .bookmarkStateLoaded(.success(bookmarks)):
                state.isBookmarked = bookmarks.contains { $0.isChecked == true }

                return .none

            case .bookmarkStateLoaded(.failure):
                // Only the label depends on it: it stays «В закладки».
                return .none

            case .autoWatchHandled:
                state.autoWatch = false

                return .none

            case .selection:
                return .none

            case let .detailsLoaded(.failure(error)):
                state.details = .error(error)

                return .none

            case let .trailerLoaded(trailer):
                // A reload's search that finds nothing (Rutube down for a moment) keeps the trailer already found.
                state.trailer = trailer ?? state.trailer
                state.trailerSearching = false

                return .none

            case .trailerTapped:
                guard let trailer = state.trailer else { return .none }

                return .run { send in
                    let result = await Result { try await RutubeTrailers.streamURL(id: trailer.id) }

                    await send(.trailerStreamLoaded(result))
                }
                .cancellable(id: CancelID.trailer, cancelInFlight: true)

            case let .trailerStreamLoaded(.success(url)):
                state.trailerStream = url

                return .none

            case let .trailerStreamLoaded(.failure(error)):
                state.alert = .error(error)

                return .none

            case let .rate(rating):
                guard let id = state.id.id else { return .none }

                return .run { send in
                    let result = await Result { try await rateUseCase(id: id, rating: rating) }

                    // The site never gives its rating back: a copy here, on the three-level scale, lights the bar.
                    if case .success(.some) = result, let level = SiteRatingMirror.level(for: rating) {
                        await recommender.rate(id, level, .site)
                        // Rated now: «Вам подойдёт?» steps aside, as it does for «Ваша оценка».
                        await MainActor.run { NotificationCenter.default.post(name: .recRatingChanged, object: id) }
                        await send(.feedback(.reload))
                    }

                    await send(.rated(result), animation: .easeInOut)
                }
                .cancellable(id: CancelID.rate, cancelInFlight: true)

            case let .rated(.success(rating)):
                guard let rating, case var .data(details) = state.details else {
                    state.alert = .error()

                    return .none
                }

                details.rate(rating.0, rating.1)
                state.details = .data(details)

                return .none

            case let .rated(.failure(error)):
                state.alert = .error(error)

                return .none

            case .bookmarksTapped:
                state.destination = .bookmarks(BookmarksSheetFeature.State(id: state.id))

                return .none

            case .watchTapped:
                state.destination = .watch(MovieSelectionFeature.State(id: state.movieId))

                return .none

            case .downloadTapped:
                state.destination = .download(MovieSelectionFeature.State(id: state.movieId))

                return .none

            case .openExternalPlayerTapped:
                state.destination = .openExternalPlayer(MovieSelectionFeature.State(id: state.movieId))

                return .none

            case let .destination(.presented(.bookmarks(.bookmarksLoaded(.success(bookmarks))))):
                state.isBookmarked = bookmarks.contains { $0.isChecked == true }

                return .none

            case .destination(.presented(.bookmarks(.toggled(_, _, .success(true))))):
                // The sheet has already counted it in (its reducer runs first).
                if let bookmarks = state.destination?.bookmarks?.bookmarks.data {
                    state.isBookmarked = bookmarks.contains { $0.isChecked == true }
                }

                return .none

            case .destination(.presented(.bookmarks(.delegate(.createBookmark)))):
                state.destination = .createBookmark(CreateBookmarkFeature.State())

                return .none

            case .destination(.dismiss):
                if case .createBookmark = state.destination {
                    state.destination = .bookmarks(BookmarksSheetFeature.State(id: state.id))
                }

                return .none

            case let .push(route):
                return .send(.delegate(.push(route)))

            case .alert, .destination, .delegate, .feedback:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$destination, action: \.destination)
        .ifLet(\.selection, action: \.selection) {
            MovieSelectionFeature()
        }
    }
}

extension DetailsFeature.Destination.State: Equatable {}
