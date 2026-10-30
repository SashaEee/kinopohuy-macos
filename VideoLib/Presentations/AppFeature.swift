import ComposableArchitecture
import Defaults
import SwiftUI

@Reducer
struct AppFeature {
    @Reducer
    enum Path {
        case details(DetailsFeature)
        case list(ListFeature)
        case person(PersonFeature)
        case comments(CommentsFeature)
    }

    @Reducer
    enum Destination {
        case signIn(SignInFeature)
        case signUp(SignUpFeature)
        case restore(RestoreFeature)
    }

    @ObservableState
    struct State: Equatable {
        var selectedTab: Tabs = .home
        /// A push a feature asked for; the shell takes it and opens it through the page fade.
        var pendingRoute: PendingRoute?

        var path = StackState<Path.State>()

        var home = HomeFeature.State()
        var search = SearchFeature.State()
        var categories = CategoriesFeature.State()
        var collections = CollectionsFeature.State()
        var watchingLater = WatchingLaterFeature.State()
        var bookmarks = BookmarksFeature.State()

        var isSignOutPresented = false
        var isPremiumPresented = false
        var isCommentsRulesPresented = false

        @Presents var destination: Destination.State?
        @Presents var alert: AlertState<Action.Alert>?
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case path(StackActionOf<Path>)
        case home(HomeFeature.Action)
        case search(SearchFeature.Action)
        case categories(CategoriesFeature.Action)
        case collections(CollectionsFeature.Action)
        case watchingLater(WatchingLaterFeature.Action)
        case bookmarks(BookmarksFeature.Action)
        case appLaunched
        /// The site's address was saved (the first one, or a new one).
        case siteAddressChanged
        case routeReceived(AppRoute)
        case signInTapped
        /// Opens a title, list or person on the stack (the shell sends it under the page fade).
        case pushRoute(Destinations)
        case pendingRouteTaken
        case signOutConfirmed
        case loggedOut(Result<Bool, any Error>)
        case loggedInChanged(Bool)
        case destination(PresentationAction<Destination.Action>)
        case alert(PresentationAction<Alert>)

        enum Alert: Equatable {}
    }

    @Dependency(\.appRouter) private var appRouter
    @Dependency(\.getVersionUseCase) private var getVersionUseCase
    @Dependency(\.logoutUseCase) private var logoutUseCase

    var body: some ReducerOf<Self> {
        BindingReducer()
            .onChange(of: \.selectedTab) { _, _ in
                Reduce { state, _ in
                    state.path = StackState()

                    return .none
                }
            }

        Scope(state: \.home, action: \.home) { HomeFeature() }
        Scope(state: \.search, action: \.search) { SearchFeature() }
        Scope(state: \.categories, action: \.categories) { CategoriesFeature() }
        Scope(state: \.collections, action: \.collections) { CollectionsFeature() }
        Scope(state: \.watchingLater, action: \.watchingLater) { WatchingLaterFeature() }
        Scope(state: \.bookmarks, action: \.bookmarks) { BookmarksFeature() }

        Reduce { state, action in
            switch action {
            case .home(.delegate(.showWatchingLater)):
                state.selectedTab = .watchingLater

                return .none

            case let .home(.delegate(.push(route))):
                state.pendingRoute = PendingRoute(route: route)

                return .none

            case let .path(.element(_, action)):
                guard let route = action.route else { return .none }

                state.pendingRoute = PendingRoute(route: route)

                return .none

            case let .pushRoute(route):
                state.path.append(Path.State(route))

                return .none

            case .pendingRouteTaken:
                state.pendingRoute = nil

                return .none

            case .appLaunched:
                #if DEBUG
                    // Test hooks (debug builds only): KP_OPEN=<title path> opens a title's page, KP_AUTOPLAY plays it.
                    if let id = ProcessInfo.processInfo.environment["KP_OPEN"] {
                        let movie = MovieSimple(movieId: id)
                        state.path.append(Path.State(ProcessInfo.processInfo.environment["KP_AUTOPLAY"] != nil ? .watch(movie) : .details(movie)))
                    }
                    // KP_SIGNIN shows the sign-in sheet even when signed in (to look at it; nothing is sent until submitted).
                    if ProcessInfo.processInfo.environment["KP_SIGNIN"] != nil {
                        state.destination = .signIn(SignInFeature.State())
                    }
                #endif

                return .merge(
                    .run { send in
                        for await route in appRouter.routes() {
                            await send(.routeReceived(route))
                        }
                    },
                    .run { _ in
                        // Only once the user has entered the site's address: the placeholder is never asked anything.
                        guard SiteAddress.isConfigured else { return }

                        let version = try await getVersionUseCase()

                        Defaults[.siteAppVersion] = version
                    }
                )

            case .siteAddressChanged:
                // Home asks the new address afresh (with none it showed «Укажите адрес сайта»), and the site's app
                // version for the headers is read from it.
                return .merge(
                    .send(.home(.reload)),
                    .run { _ in
                        guard SiteAddress.isConfigured else { return }

                        let version = try await getVersionUseCase()

                        Defaults[.siteAppVersion] = version
                    }
                )

            case .routeReceived(.signOut):
                guard Defaults[.isLoggedIn] else { return .none }

                state.isSignOutPresented = true

                return .none

            case .routeReceived(.signIn), .signInTapped:
                if case .signIn = state.destination {
                    return .none
                }

                state.destination = .signIn(SignInFeature.State())

                return .none

            case .routeReceived(.premium):
                state.isPremiumPresented = true

                return .none

            case .routeReceived(.commentsRules):
                state.isCommentsRulesPresented = true

                return .none

            case .signOutConfirmed:
                return .run { send in
                    let result = await Result { try await logoutUseCase() }

                    await send(.loggedOut(result))
                }

            case .loggedOut(.success(true)):
                return .none

            case .loggedOut(.success(false)):
                state.alert = .error()

                return .none

            case let .loggedOut(.failure(error)):
                state.alert = .error(error)

                return .none

            case let .loggedInChanged(isLoggedIn):
                if !isLoggedIn, state.selectedTab.needAccount {
                    state.selectedTab = .home
                }

                // Signed in or out: Home's banner, rows and «Продолжить просмотр» are different now (the site may
                // show some title pages to signed-in viewers only).
                return .send(.home(.reload))

            case .destination(.presented(.signIn(.delegate(.showRestore)))):
                state.destination = .restore(RestoreFeature.State())

                return .none

            case .destination(.presented(.signIn(.delegate(.showSignUp)))):
                state.destination = .signUp(SignUpFeature.State())

                return .none

            case .destination(.presented(.signUp(.delegate(.showSignIn)))),
                 .destination(.presented(.restore(.delegate(.showSignIn)))):
                state.destination = .signIn(SignInFeature.State())

                return .none

            case .binding, .path, .home, .search, .categories, .collections, .watchingLater, .bookmarks, .destination, .alert:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$destination, action: \.destination)
        .ifLet(\.$alert, action: \.alert)
    }
}

extension AppFeature.Path.State: Equatable {}
extension AppFeature.Destination.State: Equatable {}

extension AppFeature.Path.State {
    init(_ route: Destinations) {
        self = switch route {
        case let .details(movie): .details(DetailsFeature.State(movie: movie))
        case let .watch(movie): .details(DetailsFeature.State(movie: movie, autoWatch: true))
        case let .country(country): .list(ListFeature.State(source: .country(country)))
        case let .category(category): .list(ListFeature.State(source: .category(category)))
        case let .genre(genre): .list(ListFeature.State(source: .genre(genre)))
        case let .collection(collection): .list(ListFeature.State(source: .collection(collection)))
        case let .customList(movies, title): .list(ListFeature.State(source: .movies(movies, title: title)))
        case let .list(list): .list(ListFeature.State(source: .list(list)))
        case let .person(person): .person(PersonFeature.State(person: person))
        case let .comments(details): .comments(CommentsFeature.State(details: details))
        }
    }
}

extension AppFeature.Path.Action {
    var route: Destinations? {
        switch self {
        case let .details(.delegate(.push(route))), let .comments(.delegate(.push(route))):
            route
        default:
            nil
        }
    }
}

/// A push waiting for the shell (each one distinct, even to the same place).
struct PendingRoute: Equatable {
    let id = UUID()
    let route: Destinations

    static func == (lhs: PendingRoute, rhs: PendingRoute) -> Bool { lhs.id == rhs.id }
}
