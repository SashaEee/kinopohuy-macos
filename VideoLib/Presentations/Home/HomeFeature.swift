import ComposableArchitecture
import Defaults
import RecommenderCore
import SQLiteData
import SwiftUI

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var categories: DataState<[Category]> = .idle
        var paginationState: DataPaginationState = .idle
        @Presents var seriesUpdates: SeriesUpdatesFeature.State?

        /// The banner: the first few titles of the first row, with their pages (large poster, description), one
        /// shown at a time, the next every 10 s.
        var hero: [MovieDetailed] = []
        var heroIndex = 0
        /// None of the banner's pages came (signed out, and the site hides those pages from guests): no banner then.
        var heroFailed = false
        /// The pointer is over the banner: it holds still, so «Смотреть» isn't pulled away mid-aim.
        var heroHeld = false
        /// The banner is scrolled away or the window isn't in front: it doesn't turn (nobody sees it).
        var heroHidden = false
        /// What the banner turns through: the recommender's picks for tonight first (once their pages are in), then the
        /// trends.
        var slides: [HeroSlide] = []

        /// «Продолжить просмотр», first on Home when signed in (the site's continue list, unwatched first).
        var continueWatching: [MovieWatchLater] = []
        /// «Новые серии»: episodes just out of the series you're watching (past where you are) or follow.
        var newEpisodes: [NewEpisode] = []
        /// «Похоже на «…»»: the site's «смотрите также» for the first title you're watching.
        var similar: Similar?

        /// The personal rows from the recommender («Для вас», «Потому что вы досмотрели «…»», …), in its order.
        var recRows: [RecRowModel] = []
        /// «Сегодня вечером»: the pick for this evening, in place of the trends banner.
        var tonight: Tonight?
        /// The recommender knows too little yet: «Изучаем ваш вкус» instead of the personal rows.
        var recLearning = false
        var recStatus: RecStatus?

        @Presents var alert: AlertState<Action.Alert>?

        /// The pages of tonight's picks (large poster, description), by title id.
        fileprivate var tonightDetails: [String: MovieDetailed] = [:]
        /// When the rows shown were built: a newer build the same day is merged in place (a card gone after «Не моё»
        /// is filled from the same row), so the page never reshuffles under the pointer.
        fileprivate var recsBuiltAt: Date?
        /// Home came into view: the next build's first cards count as shown (the recommender stops pushing what's
        /// passed over again and again).
        fileprivate var impressionsPending = true

        /// The whole continue list, watched ones too (new episodes are matched against it).
        fileprivate var watchList: [MovieWatchLater] = []
        /// The site's feed of released episodes, and when it came (it's asked for again after 10 minutes).
        fileprivate var updateGroups: [SeriesUpdateGroup]?
        fileprivate var updatesLoadedAt: Date?
        /// Posters found for followed series that aren't in the continue list, by the series' number.
        fileprivate var posters: [String: String] = [:]
        /// Whose «смотрите также» the similar row was made from (asked for once per title).
        fileprivate var similarSource: String?

        fileprivate var nextPage: Categories?
    }

    /// A card in «Новые серии».
    struct NewEpisode: Identifiable, Equatable {
        /// The series' number on the site.
        let id: String
        let movieId: String
        let name: String
        var poster: String?
        /// «5 сезон, 8 серия».
        let place: String
        /// «28 октября · Дубляж».
        let detail: String

        var simple: MovieSimple { MovieSimple(movieId: movieId, name: name, poster: poster) }
    }

    /// «Сегодня вечером»: the main pick and two more, each a slide of the banner once its page is in.
    struct Tonight: Equatable {
        var main: RecItem
        var alternatives: [RecItem]
        /// «Будний вечер», «Поздно — на одну серию».
        var label: String
    }

    /// A banner slide: a title's page, what it is to the user («Сегодня вечером», «Сейчас в тренде») and, for a
    /// recommendation, why.
    struct HeroSlide: Equatable, Identifiable {
        let details: MovieDetailed
        let kicker: String
        var reason: String?
        /// The recommendation's title id (its «…»: «Почему это?», «Не сегодня», «Не моё»); nil for the trends.
        var recId: String?

        var id: String { details.movieId }
    }

    /// What the banner's «…» does with its pick.
    enum TonightFeedback {
        case notToday
        case notMe
        case seen
    }

    /// The «Похоже на «…»» row.
    struct Similar: Equatable {
        let name: String
        let movies: [MovieSimple]
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case reload
        case loadMore(reset: Bool = false)
        case categoryLoaded(Categories, isInitial: Bool, Result<[MovieSimple], any Error>)
        case heroLoaded([MovieDetailed])
        case heroTick
        case heroSelected(Int)
        case heroHeld(Bool)
        case heroVisible(Bool)
        case continueLoaded(Result<[MovieWatchLater], any Error>)
        case updatesLoaded(Result<[SeriesUpdateGroup], any Error>)
        case newEpisodePoster(id: String, poster: String)
        case similarLoaded(source: String, name: String, Result<[MovieSimple], any Error>)
        case recsLoaded(RecSnapshot?, merge: Bool)
        case recsChanged
        case recStatusLoaded(RecStatus)
        case recOpened(String)
        case tonightDetailsLoaded(String, MovieDetailed)
        case tonightFeedback(String, TonightFeedback)
        /// Settings → «Рекомендации» → what the banner shows.
        case heroModeChanged
        case pickForMeTapped
        case switchWatched(MovieWatchLater)
        case watchedSwitched(MovieWatchLater, Result<Bool, any Error>)
        case remove(MovieWatchLater)
        case removed(MovieWatchLater, Result<Bool, any Error>)
        case seriesUpdatesTapped
        case seriesUpdates(PresentationAction<SeriesUpdatesFeature.Action>)
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        enum Delegate {
            case push(Destinations)
            /// «Все» on «Продолжить просмотр»: the «Досмотреть» section.
            case showWatchingLater
            /// The dice on the banner: «Выбери за меня».
            case pickForMe
        }

        enum Alert: Equatable {}
    }

    private enum CancelID { case load, hero, heroTimer, continueWatching, updates, posters, similar, recs, recUpdates, tonight }

    /// How long the feed of released episodes is kept before it's asked for again.
    private static let updatesLifetime: TimeInterval = 10 * 60

    /// How many titles take turns in the banner.
    private static let heroCount = 5

    @Dependency(\.getHotMoviesUseCase) private var getHotMoviesUseCase
//    @Dependency(\.getFeaturedMoviesUseCase) private var getFeaturedMoviesUseCase
    @Dependency(\.getWatchingNowMoviesUseCase) private var getWatchingNowMoviesUseCase
    @Dependency(\.getLatestMoviesUseCase) private var getLatestMoviesUseCase
    @Dependency(\.getLatestNewestMoviesUseCase) private var getLatestNewestMoviesUseCase
    @Dependency(\.getPopularMoviesUseCase) private var getPopularMoviesUseCase
    @Dependency(\.getSoonMoviesUseCase) private var getSoonMoviesUseCase
    @Dependency(\.getMovieDetailsUseCase) private var getMovieDetailsUseCase
    @Dependency(\.getWatchingLaterMoviesUseCase) private var getWatchingLaterMoviesUseCase
    @Dependency(\.getSeriesUpdatesUseCase) private var getSeriesUpdatesUseCase
    @Dependency(\.switchWatchedItemUseCase) private var switchWatchedItemUseCase
    @Dependency(\.removeWatchingItemUseCase) private var removeWatchingItemUseCase
    @Dependency(\.recommender) private var recommender
    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                state.impressionsPending = true

                // Back on Home: «Продолжить просмотр» may have moved (something was just watched), and so may the
                // recommendations.
                guard state.categories.needsLoad else { return .merge(loadContinueWatching(), loadRecs(merge: true)) }

                return .send(.reload)

            case .reload:
                state.categories = .loading
                state.paginationState = .idle
                state.nextPage = Categories.allCases.first
                state.hero = []
                state.slides = []
                state.heroIndex = 0
                state.heroFailed = false
                // The personal rows are asked for afresh (signed out: they go).
                state.updateGroups = nil
                state.updatesLoadedAt = nil
                state.similarSource = nil
                state.recsBuiltAt = nil
                if !Defaults[.isLoggedIn] {
                    state.recRows = []
                    state.tonight = nil
                    state.watchList = []
                    state.continueWatching = []
                    state.newEpisodes = []
                    state.similar = nil
                    state.posters = [:]
                }

                guard let page = state.nextPage else { return .cancel(id: CancelID.load) }

                return .merge(
                    load(page, isInitial: true),
                    loadContinueWatching(),
                    loadRecs(merge: false),
                    observeRecs(),
                    .cancel(id: CancelID.updates),
                    .cancel(id: CancelID.posters),
                    .cancel(id: CancelID.similar)
                )

            case let .loadMore(reset):
                guard let page = state.nextPage, state.paginationState == .idle || reset else { return .none }

                state.paginationState = .loading

                return load(page, isInitial: false)

            case let .categoryLoaded(category, isInitial, result):
                if case .success = result {
                    state.nextPage = Categories.allCases.element(after: category)
                }

                state.paginationState = state.categories.receivePage(
                    result.map { [Category(category: category, title: category.localized, movies: $0, id: uuid())] },
                    isInitial: isInitial
                )

                if isInitial, state.hero.isEmpty, case let .success(movies) = result {
                    return loadHero(Array(movies.prefix(Self.heroCount)))
                }

                return .none

            case let .heroLoaded(hero):
                state.hero = hero
                state.heroFailed = hero.isEmpty

                return rebuildSlides(&state)

            case .heroModeChanged:
                return rebuildSlides(&state)

            case let .heroHeld(held):
                guard held != state.heroHeld else { return .none }

                state.heroHeld = held

                // Paused under the pointer; when it leaves, the banner gets a fresh 10 s (the dot shows them run out).
                return held || state.heroHidden || state.slides.count < 2 ? .cancel(id: CancelID.heroTimer) : heroTimer()

            case let .heroVisible(visible):
                guard visible == state.heroHidden else { return .none }

                state.heroHidden = !visible

                // Turning a banner nobody sees would rebuild Home every 10 s while scrolling the rows below.
                return !visible || state.heroHeld || state.slides.count < 2 ? .cancel(id: CancelID.heroTimer) : heroTimer()

            case .heroTick:
                guard !state.slides.isEmpty, !state.heroHeld, !state.heroHidden else { return .none }

                state.heroIndex = (state.heroIndex + 1) % state.slides.count

                return .none

            case let .heroSelected(index):
                guard state.slides.indices.contains(index) else { return .none }

                state.heroIndex = index

                return heroTimer() // a fresh 10 s for the one just picked

            case let .continueLoaded(.success(movies)):
                state.watchList = MovieWatchLater.keepingIds(movies, from: state.watchList)
                refreshPersonalRows(&state)

                return .merge(loadUpdates(&state), loadSimilar(&state))

            case .continueLoaded(.failure):
                return .none

            case let .updatesLoaded(.success(groups)):
                state.updateGroups = groups
                state.updatesLoadedAt = now
                refreshPersonalRows(&state)

                return loadPosters(state.newEpisodes)

            case .updatesLoaded(.failure):
                // A nicety: Home goes on without the row.
                return .none

            case let .newEpisodePoster(id, poster):
                state.posters[id] = poster
                if let index = state.newEpisodes.firstIndex(where: { $0.id == id }) {
                    state.newEpisodes[index].poster = poster
                }

                return .none

            case let .similarLoaded(source, name, .success(movies)):
                guard source == state.similarSource else { return .none }

                state.similar = movies.isEmpty ? nil : Similar(name: name, movies: Array(movies.prefix(20)))

                return .none

            case let .similarLoaded(source, _, .failure):
                // Asked for again next time Home shows.
                if source == state.similarSource { state.similarSource = nil }

                return .none

            case let .switchWatched(movie):
                return .run { send in
                    let result = await Result { try await switchWatchedItemUseCase(item: movie) }

                    await send(.watchedSwitched(movie, result), animation: .smooth(duration: 0.35))
                }

            case let .watchedSwitched(movie, .success(switched)):
                guard switched, let index = state.watchList.firstIndex(where: { $0.id == movie.id }) else { return .none }

                state.watchList[index].watched.toggle()
                refreshPersonalRows(&state)

                return loadSimilar(&state)

            case let .remove(movie):
                return .run { send in
                    let result = await Result { try await removeWatchingItemUseCase(item: movie) }

                    await send(.removed(movie, result), animation: .smooth(duration: 0.35))
                }

            case let .removed(movie, .success(removed)):
                guard removed else { return .none }

                state.watchList.removeAll { $0.id == movie.id }
                refreshPersonalRows(&state)

                guard let watchLaterId = movie.watchLaterId.id else { return loadSimilar(&state) }

                // This Mac's saved places for it go too, as on «Досмотреть».
                return .merge(
                    loadSimilar(&state),
                    .run { _ in
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
                )

            case let .watchedSwitched(_, .failure(error)), let .removed(_, .failure(error)):
                state.alert = .error(error)

                return .none

            case let .recsLoaded(snapshot, merge):
                return recsLoaded(&state, snapshot, merge: merge)

            case .recsChanged:
                return loadRecs(merge: true)

            case let .recStatusLoaded(status):
                state.recStatus = status

                return .none

            case let .recOpened(titleId):
                return .run { _ in await recommender.markOpened(titleId) }

            case let .tonightDetailsLoaded(titleId, details):
                state.tonightDetails[titleId] = details

                return rebuildSlides(&state)

            case let .tonightFeedback(titleId, feedback):
                guard var tonight = state.tonight else { return .none }

                let signal: Effect<Action> = switch feedback {
                case .notToday: .run { _ in await recommender.feedback(titleId, .notToday) }
                case .notMe: .run { _ in await recommender.rate(titleId, -2, .app) }
                case .seen: .run { _ in await recommender.feedback(titleId, .seen) }
                }

                // Its slide goes at once; the next pick in line leads.
                if tonight.main.id == titleId {
                    if tonight.alternatives.isEmpty {
                        state.tonight = nil
                    } else {
                        tonight.main = tonight.alternatives.removeFirst()
                        state.tonight = tonight
                    }
                } else {
                    tonight.alternatives.removeAll { $0.id == titleId }
                    state.tonight = tonight
                }

                return .merge(signal, rebuildSlides(&state))

            case .pickForMeTapped:
                return .send(.delegate(.pickForMe))

            case .seriesUpdatesTapped:
                state.seriesUpdates = SeriesUpdatesFeature.State()

                return .none

            case let .seriesUpdates(.presented(.delegate(.openMovie(movie)))):
                return .send(.delegate(.push(.details(movie))))

            case .seriesUpdates, .alert, .delegate:
                return .none
            }
        }
        .ifLet(\.$seriesUpdates, action: \.seriesUpdates) {
            SeriesUpdatesFeature()
        }
        .ifLet(\.$alert, action: \.alert)
    }

    // MARK: Recommendations

    /// The recommender's snapshot (instant from its cache when it has one).
    private func loadRecs(merge: Bool) -> Effect<Action> {
        .run { send in
            let snapshot = await recommender.home(false)

            await send(.recsLoaded(snapshot, merge: merge), animation: .smooth(duration: 0.35))
        }
        .cancellable(id: CancelID.recs, cancelInFlight: true)
    }

    /// A new signal or a batch of the catalogue read in the background: the rows are brought up to date in place.
    private func observeRecs() -> Effect<Action> {
        .run { send in
            for await _ in recommender.updates() {
                await send(.recsChanged)
            }
        }
        .cancellable(id: CancelID.recUpdates, cancelInFlight: true)
    }

    private func recsLoaded(_ state: inout State, _ snapshot: RecSnapshot?, merge: Bool) -> Effect<Action> {
        guard let snapshot else {
            state.recRows = []
            state.tonight = nil
            state.recLearning = Defaults[.isLoggedIn]
            return state.recLearning ? loadRecStatus() : .none
        }

        let output = snapshot.output
        let rows = Self.rowModels(snapshot)
        let allowed = Self.allowedIds(output)
        let sameDay = state.recsBuiltAt.map { Calendar.current.isDate($0, inSameDayAs: snapshot.builtAt) } ?? false

        state.recLearning = output.isColdStart
        state.recRows = merge && sameDay && !state.recRows.isEmpty ? Self.merged(old: state.recRows, new: rows, allowed: allowed) : rows
        state.recsBuiltAt = snapshot.builtAt

        var effects: [Effect<Action>] = []

        if let hero = output.page.hero, !output.isColdStart, let main = Self.item(hero.main, snapshot) {
            if merge, sameDay, var current = state.tonight, allowed.contains(current.main.id) {
                // The banner keeps its pick; an «Или:» that's gone (rated, hidden) is replaced from the new build.
                current.alternatives = current.alternatives.filter { allowed.contains($0.id) }
                for alternative in hero.alternatives.compactMap({ Self.item($0, snapshot) })
                    where current.alternatives.count < 2 && alternative.id != current.main.id && !current.alternatives.contains(alternative)
                {
                    current.alternatives.append(alternative)
                }
                current.label = hero.contextLabel
                state.tonight = current
            } else if state.tonight?.main.id != main.id {
                state.tonight = Tonight(main: main, alternatives: hero.alternatives.compactMap { Self.item($0, snapshot) }, label: hero.contextLabel)
            }
        } else {
            state.tonight = nil
        }
        effects.append(loadTonightDetails(state))
        effects.append(rebuildSlides(&state))

        if state.impressionsPending {
            state.impressionsPending = false
            var shown: [String] = []
            if let tonight = state.tonight { shown += [tonight.main.id] + tonight.alternatives.map(\.id) }
            for row in state.recRows { shown += row.items.prefix(6).map(\.id) }
            if !shown.isEmpty {
                effects.append(.run { [shown] _ in await recommender.recordImpressions(shown, "home") })
            }
        }

        if output.isColdStart { effects.append(loadRecStatus()) }

        return .merge(effects)
    }

    private func loadRecStatus() -> Effect<Action> {
        .run { send in
            await send(.recStatusLoaded(await recommender.status()))
        }
    }

    /// The picks' pages (large poster, description), one at a time, as the trends banner does: each becomes a slide as
    /// it comes.
    private func loadTonightDetails(_ state: State) -> Effect<Action> {
        let picks = state.tonight.map { [$0.main] + $0.alternatives } ?? []
        let missing = picks.filter { state.tonightDetails[$0.id] == nil }
        guard !missing.isEmpty else { return .none }

        return .run { send in
            for item in missing {
                guard let details = try? await getMovieDetailsUseCase(movieId: item.title.path) else { continue }

                await send(.tonightDetailsLoaded(item.id, details), animation: .easeInOut(duration: 0.4))
            }
        }
        .cancellable(id: CancelID.tonight, cancelInFlight: true)
    }

    /// The banner's slides as things are now: tonight's picks first («Сегодня вечером», then «Подобрано для вас»), the
    /// trends after them. The slide on screen stays on screen while it's still there; when the picks first arrive,
    /// they lead.
    private func rebuildSlides(_ state: inout State) -> Effect<Action> {
        let mode = HeroMode(rawValue: Defaults[.recHeroMode]) ?? .tonight
        var slides: [HeroSlide] = []
        if mode == .tonight, let tonight = state.tonight {
            for (offset, item) in ([tonight.main] + tonight.alternatives).enumerated() {
                guard let details = state.tonightDetails[item.id] else { continue }
                slides.append(HeroSlide(
                    details: details, kicker: offset == 0 ? "Сегодня вечером" : "Подобрано для вас",
                    reason: item.rec.reason.long, recId: item.id
                ))
            }
        }
        if mode != .hidden {
            for movie in state.hero where slides.count <= Self.heroCount && !slides.contains(where: { $0.id == movie.movieId }) {
                slides.append(HeroSlide(details: movie, kicker: "Сейчас в тренде"))
            }
        }

        let current = state.slides.indices.contains(state.heroIndex) ? state.slides[state.heroIndex].id : nil
        let picksArrived = !state.slides.contains { $0.recId != nil } && slides.first?.recId != nil
        state.slides = slides
        if picksArrived {
            state.heroIndex = 0
        } else if let current, let index = slides.firstIndex(where: { $0.id == current }) {
            state.heroIndex = index
        } else {
            state.heroIndex = min(state.heroIndex, max(0, slides.count - 1))
        }

        return slides.count > 1 && !state.heroHeld && !state.heroHidden ? heroTimer() : .cancel(id: CancelID.heroTimer)
    }

    private static func item(_ recommendation: Recommendation, _ snapshot: RecSnapshot) -> RecItem? {
        snapshot.titles[recommendation.titleId].map { RecItem(rec: recommendation, title: $0) }
    }

    /// The engine's rows with their titles (a title the snapshot has no data for is left out).
    static func rowModels(_ snapshot: RecSnapshot) -> [RecRowModel] {
        snapshot.output.page.rows.compactMap { row in
            let items = row.items.compactMap { item($0, snapshot) }
            return items.isEmpty ? nil : RecRowModel(id: row.id, kind: row.kind, title: row.title, items: items)
        }
    }

    /// Every title the build still recommends somewhere.
    static func allowedIds(_ output: EngineOutput) -> Set<String> {
        var ids = Set(output.ranked.map(\.titleId))
        for row in output.page.rows { ids.formUnion(row.items.map(\.titleId)) }
        if let hero = output.page.hero { ids.formUnion([hero.main.titleId] + hero.alternatives.map(\.titleId)) }
        return ids
    }

    /// A newer build merged into the rows on screen: each row keeps its place and its cards' order, a card no longer
    /// recommended goes and the row is topped up from its new version; rows that appeared go at the end. A row left
    /// with fewer than four cards goes.
    static func merged(old: [RecRowModel], new: [RecRowModel], allowed: Set<String>) -> [RecRowModel] {
        let fresh = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var kept = old.map { row in row.items.filter { allowed.contains($0.id) } }
        var used = Set(kept.flatMap { $0.map(\.id) })

        var rows: [RecRowModel] = []
        for (index, row) in old.enumerated() {
            var items = kept[index]
            if let update = fresh[row.id] {
                for item in update.items where items.count < row.items.count && !used.contains(item.id) {
                    items.append(item)
                    used.insert(item.id)
                }
            }
            kept[index] = items
            if items.count >= 4 {
                rows.append(RecRowModel(id: row.id, kind: row.kind, title: row.title, items: items))
            }
        }
        for row in new where !old.contains(where: { $0.id == row.id }) {
            let items = row.items.filter { !used.contains($0.id) }
            guard items.count >= 8 else { continue }
            rows.append(RecRowModel(id: row.id, kind: row.kind, title: row.title, items: items))
            used.formUnion(items.map(\.id))
        }
        return rows
    }

    /// «Продолжить просмотр» and «Новые серии» from the continue list and the feed as they are now.
    private func refreshPersonalRows(_ state: inout State) {
        state.continueWatching = state.watchList.filter { !$0.watched }
        state.newEpisodes = Self.newEpisodes(groups: state.updateGroups ?? [], watchList: state.watchList, posters: state.posters)
    }

    /// The feed of released episodes, at most every 10 minutes (Home shows often; the list itself is matched again
    /// every time).
    private func loadUpdates(_ state: inout State) -> Effect<Action> {
        if let loadedAt = state.updatesLoadedAt, now.timeIntervalSince(loadedAt) < Self.updatesLifetime {
            return .none
        }

        return .run { send in
            let result = await Result { try await getSeriesUpdatesUseCase() }

            await send(.updatesLoaded(result), animation: .smooth(duration: 0.35))

            // Which series the account follows, for the recommender.
            if case let .success(groups) = result { await recommender.captureSeriesUpdates(groups) }
        }
        .cancellable(id: CancelID.updates, cancelInFlight: true)
    }

    /// Posters for followed series that aren't in the continue list: from their pages, one at a time.
    private func loadPosters(_ episodes: [NewEpisode]) -> Effect<Action> {
        let missing = episodes.filter { $0.poster == nil }
        guard !missing.isEmpty else { return .none }

        return .run { send in
            for episode in missing {
                guard let details = try? await getMovieDetailsUseCase(movieId: episode.movieId) else { continue }
                await recommender.captureDetails(details)
                let poster = details.poster.isEmpty ? details.hposter : details.poster
                guard !poster.isEmpty else { continue }

                await send(.newEpisodePoster(id: episode.id, poster: poster), animation: .easeInOut(duration: 0.25))
            }
        }
        .cancellable(id: CancelID.posters, cancelInFlight: true)
    }

    /// «Похоже на «…»» for the first title still being watched, once per title.
    private func loadSimilar(_ state: inout State) -> Effect<Action> {
        guard let first = state.continueWatching.first(where: { $0.watchLaterId.id != nil }) else {
            state.similar = nil
            state.similarSource = nil
            return .cancel(id: CancelID.similar)
        }
        guard first.watchLaterId != state.similarSource else { return .none }

        state.similarSource = first.watchLaterId

        return .run { send in
            let result = await Result { try await getMovieDetailsUseCase(movieId: first.watchLaterId) }
            let name = (try? result.get().nameRussian).flatMap { $0.isEmpty ? nil : $0 } ?? first.name

            await send(.similarLoaded(source: first.watchLaterId, name: name, result.map(\.watchAlsoMovies)), animation: .smooth(duration: 0.35))

            if case let .success(details) = result { await recommender.captureDetails(details) }
        }
        .cancellable(id: CancelID.similar, cancelInFlight: true)
    }

    /// The TV's pick: the newest release per series, for series in the continue list (not watched, past where you
    /// are) or ones the account follows; twenty at most.
    static func newEpisodes(groups: [SeriesUpdateGroup], watchList: [MovieWatchLater], posters: [String: String]) -> [NewEpisode] {
        var places: [String: (season: Int, episode: Int)] = [:]
        var covers: [String: String] = [:]
        for movie in watchList {
            guard let id = movie.watchLaterId.id else { continue }
            if covers[id] == nil, !movie.cover.isEmpty { covers[id] = movie.cover }
            if !movie.watched, let place = movie.watchingEpisode { places[id] = place }
        }

        var seen: Set<String> = []
        var picks: [NewEpisode] = []
        for group in groups {
            for item in group.releasedEpisodes {
                guard picks.count < 20, let id = item.seriesId.id, !seen.contains(id) else { continue }
                let place = places[id]
                guard place != nil || item.tracked else { continue }

                let season = item.season.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
                let episode = item.releasedEpisode.trimmingCharacters(in: .whitespacesAndNewlines)
                // Already watched past it.
                if let place, let s = firstNumber(season), let e = firstNumber(episode),
                   s < place.season || (s == place.season && e <= place.episode)
                {
                    continue
                }

                seen.insert(id)
                let voice = item.chosenVoiceActing.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
                picks.append(NewEpisode(
                    id: id,
                    movieId: item.seriesId,
                    name: item.seriesName,
                    poster: covers[id] ?? posters[id],
                    place: [season, episode].filter { !$0.isEmpty }.joined(separator: ", "),
                    detail: [shortDate(group.date), voice].filter { !$0.isEmpty }.joined(separator: " · ")
                ))
            }
        }
        return picks
    }

    private static func firstNumber(_ text: String) -> Int? {
        text.range(of: "\\d+", options: .regularExpression).flatMap { Int(text[$0]) }
    }

    /// «30 октября 2026 (сегодня)» → «Сегодня»; «28 октября 2026» → «28 октября».
    private static func shortDate(_ text: String) -> String {
        let lowered = text.lowercased()
        if lowered.contains("сегодня") { return "Сегодня" }
        if lowered.contains("вчера") { return "Вчера" }
        return text
            .replacingOccurrences(of: "\\s*\\(.*\\)\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+\\d{4}$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load(_ category: Categories, isInitial: Bool) -> Effect<Action> {
        .run { send in
            let result = await Result { try await movies(category) }

            await send(.categoryLoaded(category, isInitial: isInitial, result), animation: .easeInOut)

            // The row's cards go into the recommender's catalogue (no extra request).
            if case let .success(cards) = result { await recommender.captureCards(cards, nil) }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// The banner's titles one by one: the first shows as soon as its page is in.
    private func loadHero(_ movies: [MovieSimple]) -> Effect<Action> {
        .run { send in
            var hero: [MovieDetailed] = []

            for movie in movies {
                guard let details = try? await getMovieDetailsUseCase(movieId: movie.movieId) else { continue }

                hero.append(details)

                if hero.count == 1 {
                    await send(.heroLoaded(hero), animation: .easeInOut)
                }

                await recommender.captureDetails(details)
            }

            if hero.count != 1 {
                await send(.heroLoaded(hero)) // all of them, or none (then the banner is left out)
            }
        }
        .cancellable(id: CancelID.hero, cancelInFlight: true)
    }

    private func heroTimer() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(10)) {
                await send(.heroTick, animation: .easeInOut(duration: 0.7))
            }
        }
        .cancellable(id: CancelID.heroTimer, cancelInFlight: true)
    }

    private func loadContinueWatching() -> Effect<Action> {
        // Signed out: a list still on its way is the previous account's.
        guard Defaults[.isLoggedIn] else { return .cancel(id: CancelID.continueWatching) }

        return .run { send in
            let result = await Result { try await getWatchingLaterMoviesUseCase() }

            await send(.continueLoaded(result), animation: .easeInOut)

            // The whole list, watched ones too: the recommender's strongest signal about taste.
            if case let .success(movies) = result { await recommender.captureAccountList(movies) }
        }
        .cancellable(id: CancelID.continueWatching, cancelInFlight: true)
    }

    private func movies(_ category: Categories) async throws -> [MovieSimple] {
        switch category {
        case .hot: try await getHotMoviesUseCase(genre: 0)
//        case .featured: try await getFeaturedMoviesUseCase(page: 1, genre: 0)
        case .watchingNow: try await getWatchingNowMoviesUseCase(page: 1, genre: 0)
        case .latest: try await getLatestMoviesUseCase(page: 1, genre: 0)
        case .newest: try await getLatestNewestMoviesUseCase(page: 1, genre: 0)
        case .popular: try await getPopularMoviesUseCase(page: 1, genre: 0)
        case .soon: try await getSoonMoviesUseCase(page: 1, genre: 0)
        }
    }
}
