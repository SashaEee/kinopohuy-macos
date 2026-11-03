import ComposableArchitecture
import Defaults
import SQLiteData
import SwiftUI

@Reducer
struct MovieSelectionFeature {
    @ObservableState
    struct State: Equatable {
        let id: String

        var details: MovieDetailed?
        var seasons: [MovieSeason]?
        var selectedActing: MovieVoiceActing?
        var selectedSeason: MovieSeason?
        var selectedEpisode: MovieEpisode?
        var selectedQuality: String?
        var selectedSubtitles: MovieSubtitles?
        var movie: MovieVideo?

        var error: EquatableError?
        var isErrorPresented = false

        /// On a title's page rather than in the sheet: it loads as soon as the page opens, so a premium-only title
        /// just says so on the button instead of putting up the «buy premium» dialog unasked.
        let isEmbedded: Bool

        /// Where each episode (or the film) of the chosen voice-over was left on this Mac, in seconds (or the player's
        /// `watchedMark`), by `positionKey`: «Продолжить с 12:34», the ticks and the progress bar on the episodes.
        var positions: [String: Double] = [:]
        /// Each one's real length where the player saved it (by the same key), for the progress bars.
        var durations: [String: Double] = [:]

        /// This Mac's last choice when the page opened, and the latest one read since (the player writes it
        /// whenever a stream starts): when they differ, something was played here meanwhile.
        fileprivate var selectPosition: SelectPosition?
        fileprivate var latestPosition: SelectPosition?
        /// The title's page, already in: the selection starts from it instead of fetching the same page again.
        fileprivate var preloaded: MovieDetailed?

        init(id: String, isEmbedded: Bool = false, details: MovieDetailed? = nil) {
            self.id = id
            self.isEmbedded = isEmbedded
            preloaded = details
        }

        /// Everything the player needs, once a voice-over, an episode (for a series) and a quality are ready.
        var playerData: PlayerData? { playerData() }

        /// The same, «С начала» (`startOver`): the player then ignores where it was left.
        func playerData(startOver: Bool = false) -> PlayerData? {
            guard let details, let selectedActing, let selectedQuality, let movie, !movie.needPremium else { return nil }
            if details.series != nil, selectedEpisode == nil { return nil }
            return PlayerData(details: details, selectedActing: selectedActing, seasons: seasons, selectedSeason: selectedSeason, selectedEpisode: selectedEpisode, selectedQuality: selectedQuality, movie: movie, startOver: startOver)
        }

        static func positionKey(_ season: MovieSeason?, _ episode: MovieEpisode?) -> String {
            "\(season?.seasonId ?? "")|\(episode?.episodeId ?? "")"
        }

        /// The length the site gives, in seconds: a film's, or a series' usual episode (episodes run a little
        /// longer or shorter, so for a series it is an estimate).
        var nominalDuration: Double? {
            guard let minutes = details?.duration, minutes >= 10 else { return nil }
            return Double(minutes * 60)
        }

        /// The player's mark: left in the last 90 s of the real stream (the credits) or played to its end. It knows the
        /// stream's length, so this is what counts; the player starts such a one from 0.
        static func isPlayedToEnd(_ position: Double) -> Bool {
            position >= PlayerFeature.watchedMark
        }

        /// Watched: only the player's mark. The site's minutes are nominal (a stream runs a few longer or shorter), so
        /// guessing from them would have the page say «Смотреть» where the player then resumes, or the other way
        /// round; the player knows the real length and marks the credits itself.
        func isFinished(_ position: Double) -> Bool {
            Self.isPlayedToEnd(position)
        }

        /// Where the chosen episode or film was left, past its first 10 s and before its end: the page offers
        /// «Продолжить с 12:34» and «С начала».
        var resumePosition: Double? {
            guard let position = positions[Self.positionKey(selectedSeason, selectedEpisode)], position >= 10, !isFinished(position) else { return nil }
            return position
        }

        /// Where you stopped: what was played here since the page opened; else the site's mark (signed in, so it
        /// knows the other devices too); else this Mac's last choice.
        var stop: Stop? {
            if let latestPosition, latestPosition != selectPosition, let stop = Stop(latestPosition) { return stop }
            if Defaults[.isLoggedIn] { return details?.series.map(Stop.init) }
            return selectPosition.flatMap(Stop.init)
        }

        /// Where a series opens: the stop, or the site's own pick when there's none (without an account it marks
        /// an episode too, which isn't where you stopped, so it never ticks anything).
        fileprivate var openingPoint: Stop? {
            stop ?? details?.series.map(Stop.init)
        }

        /// Ticked and dimmed: every episode before where you stopped in this voice-over (all of the earlier seasons
        /// too), and any played to its end here.
        func isWatched(_ season: MovieSeason, _ episode: MovieEpisode) -> Bool {
            if let position = positions[Self.positionKey(season, episode)], isFinished(position) { return true }
            guard let stop, stop.acting == selectedActing?.translatorId, let seasons,
                  let stopSeason = seasons.firstIndex(where: { $0.seasonId == stop.season }),
                  let index = seasons.firstIndex(where: { $0.seasonId == season.seasonId })
            else { return false }
            if index != stopSeason { return index < stopSeason }
            guard let stopEpisode = season.episodes.firstIndex(where: { $0.episodeId == stop.episode }),
                  let episodeIndex = season.episodes.firstIndex(where: { $0.episodeId == episode.episodeId })
            else { return false }
            return episodeIndex < stopEpisode
        }

        /// How far into an episode you got (0…1): against its real length where the player saved it, else the site's
        /// usual one; from 30 s in until it's watched.
        func progress(_ season: MovieSeason, _ episode: MovieEpisode) -> Double? {
            let key = Self.positionKey(season, episode)
            guard let position = positions[key], position >= 30, let length = durations[key] ?? nominalDuration,
                  !isWatched(season, episode)
            else { return nil }
            return min(1, position / length)
        }
    }

    /// A voice-over, season and episode where you stopped (the site's mark or this Mac's choice).
    struct Stop: Equatable {
        let acting: String
        let season: String
        let episode: String

        init(_ series: Series) {
            acting = series.acting
            season = series.season
            episode = series.episode
        }

        init?(_ position: SelectPosition) {
            guard let season = position.season, let episode = position.episode else { return nil }
            acting = position.acting
            self.season = season
            self.episode = episode
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case detailsLoaded(Result<(MovieDetailed, SelectPosition?), any Error>)
        case seasonsLoaded(Result<[MovieSeason], any Error>)
        case videoLoaded(Result<MovieVideo, any Error>)
        case positionsLoaded(SavedPlaces)
        /// The window is in front again (the player was closed, say): where things were left, read again.
        case refreshPositions
        case positionsRefreshed(SavedPlaces, SelectPosition?)
        case rememberSelection
        case showError(any Error)
    }

    private enum CancelID {
        case details
        case seasons
        case video
        case positions
    }

    @Dependency(\.getMovieDetailsUseCase) private var getMovieDetailsUseCase
    @Dependency(\.getMovieVideoUseCase) private var getMovieVideoUseCase
    @Dependency(\.getSeriesSeasonsUseCase) private var getSeriesSeasonsUseCase
    @Dependency(\.saveWatchingStateUseCase) private var saveWatchingStateUseCase
    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.appRouter) private var appRouter
    @Dependency(\.dismiss) private var dismiss
    @Dependency(\.recommender) private var recommender

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding(\.selectedActing):
                return actingChanged(&state)

            case .binding(\.selectedSeason):
                return seasonChanged(&state)

            case .binding(\.selectedEpisode):
                return episodeChanged(&state)

            case .binding:
                return .none

            case .onAppear:
                guard state.details == nil else { return .none }

                return .run { [id = state.id, preloaded = state.preloaded] send in
                    let result = await Result {
                        let details = if let preloaded { preloaded } else { try await getMovieDetailsUseCase(movieId: id) }

                        let selectPosition: SelectPosition? = if let movieId = details.movieId.id {
                            try? await database.read { db in
                                try SelectPosition.where { $0.id.eq(movieId) }.fetchOne(db)
                            }
                        } else {
                            nil
                        }

                        return (details, selectPosition)
                    }

                    await send(.detailsLoaded(result), animation: .easeInOut)

                    // A page read here (not handed over by the title's page) goes into the recommender's catalogue.
                    if preloaded == nil, case let .success((details, _)) = result { await recommender.captureDetails(details) }
                }
                .cancellable(id: CancelID.details, cancelInFlight: true)

            case let .detailsLoaded(.success((details, selectPosition))):
                state.details = details
                state.preloaded = nil
                state.selectPosition = selectPosition

                guard let acting = details.voiceActing else { return .none }

                let available = acting.filter { Defaults[.isUserPremium] != nil || !$0.isPremium }

                state.selectedActing = if !Defaults[.isLoggedIn],
                                          let position = selectPosition,
                                          let first = available.first(where: { $0.translatorId == position.acting })
                {
                    first
                } else if let series = details.series,
                          let first = available.first(where: { $0.translatorId == series.acting })
                {
                    first
                } else if let first = available.first(where: { $0.isSelected }) {
                    first
                } else if let first = available.first {
                    first
                } else {
                    acting.first
                }

                return actingChanged(&state)

            case let .seasonsLoaded(.success(seasons)):
                state.seasons = seasons

                state.selectedSeason = if let target = resumeTarget(state) {
                    target.season
                } else if let first = seasons.first(where: { $0.isSelected }) {
                    first
                } else {
                    seasons.first
                }

                return seasonChanged(&state)

            case let .positionsLoaded(saved):
                state.positions = saved.positions
                state.durations = saved.durations

                return .none

            case .refreshPositions:
                guard let details = state.details, let acting = state.selectedActing else { return .none }

                return .run { [movieId = details.movieId.id] send in
                    let positions = await readPositions(acting)
                    let latest: SelectPosition? = if let movieId {
                        try? await database.read { db in
                            try SelectPosition.where { $0.id.eq(movieId) }.fetchOne(db)
                        }
                    } else {
                        nil
                    }

                    await send(.positionsRefreshed(positions, latest), animation: .smooth(duration: 0.35))
                }
                .cancellable(id: CancelID.positions, cancelInFlight: true)

            case let .positionsRefreshed(saved, latest):
                state.positions = saved.positions
                state.durations = saved.durations

                let previous = state.latestPosition ?? state.selectPosition
                state.latestPosition = latest

                guard let latest, latest != previous else { return .none }

                // Switched to another voice-over in the player: the page follows (when it's one you can pick here), so
                // its seasons, episode, ticks and «Продолжить» are that voice-over's, not the old one's.
                if latest.acting != state.selectedActing?.translatorId {
                    guard let acting = state.details?.voiceActing?.first(where: { $0.translatorId == latest.acting }),
                          Defaults[.isUserPremium] != nil || !acting.isPremium
                    else { return .none }

                    state.selectedActing = acting

                    return actingChanged(&state)
                }

                // Played here meanwhile: the page moves on to where you are now (the next episode once that one's
                // finished), as when it opens.
                guard let target = resumeTarget(state) else { return .none }

                if target.season != state.selectedSeason {
                    state.selectedSeason = target.season
                    return seasonChanged(&state)
                }
                guard target.episode != state.selectedEpisode else { return .none }

                state.selectedEpisode = target.episode
                return episodeChanged(&state)

            case let .videoLoaded(.success(movie)):
                guard !movie.needPremium || state.isEmbedded else {
                    return .run { _ in
                        await dismiss()

                        appRouter.present(.premium)
                    }
                }

                state.movie = movie

                let qualities = movie.getAvailableQualities()
                let defaultQuality = Defaults[.defaultQuality]

                if defaultQuality != .ask,
                   defaultQuality != .highest,
                   qualities.contains(defaultQuality.rawValue)
                {
                    state.selectedQuality = defaultQuality.rawValue
                } else if defaultQuality == .highest,
                          let highest = qualities.last
                {
                    state.selectedQuality = highest
                }

                state.selectedSubtitles = movie.subtitles.first(where: { $0.lang == state.selectPosition?.subtitles?.replacingOccurrences(of: "uk", with: "ua") })

                return .none

            case let .detailsLoaded(.failure(error)),
                 let .seasonsLoaded(.failure(error)),
                 let .videoLoaded(.failure(error)),
                 let .showError(error):
                state.error = EquatableError(error)
                state.isErrorPresented = true

                return .none

            case .rememberSelection:
                guard let selectedActing = state.selectedActing else { return .none }

                return .run { [selectedSeason = state.selectedSeason, selectedEpisode = state.selectedEpisode] _ in
                    if Defaults[.isLoggedIn] {
                        _ = try? await saveWatchingStateUseCase(voiceActing: selectedActing, season: selectedSeason, episode: selectedEpisode)
                    }

                    try? await database.write { db in
                        try SelectPosition
                            .upsert {
                                SelectPosition.Draft(
                                    id: selectedActing.voiceId,
                                    acting: selectedActing.translatorId,
                                    season: selectedSeason?.seasonId,
                                    episode: selectedEpisode?.episodeId
                                )
                            }
                            .execute(db)
                    }
                }
            }
        }
    }

    private func actingChanged(_ state: inout State) -> Effect<Action> {
        state.selectedSeason = nil
        state.selectedEpisode = nil
        state.selectedQuality = nil
        state.seasons = nil
        state.movie = nil
        state.positions = [:]
        state.durations = [:]

        let cancel = Effect<Action>.merge(.cancel(id: CancelID.seasons), .cancel(id: CancelID.video), .cancel(id: CancelID.positions))

        guard let details = state.details, let selectedActing = state.selectedActing else { return cancel }

        guard details.series != nil else {
            return .concatenate(cancel, .merge(
                loadVideo(details: details, acting: selectedActing, season: nil, episode: nil),
                .run { send in
                    await send(.positionsLoaded(readPositions(selectedActing)), animation: .smooth(duration: 0.3))
                }
                .cancellable(id: CancelID.positions, cancelInFlight: true)
            ))
        }

        guard let movieId = details.movieId.id else {
            state.isErrorPresented = true

            return cancel
        }

        return .concatenate(
            cancel,
            .run { send in
                // Where the episodes were left first (a local read): which one opens depends on it.
                await send(.positionsLoaded(readPositions(selectedActing)))

                let result = await Result { try await getSeriesSeasonsUseCase(movieId: movieId, voiceActing: selectedActing, favs: details.favs) }

                await send(.seasonsLoaded(result), animation: .easeInOut)
            }
            .cancellable(id: CancelID.seasons, cancelInFlight: true)
        )
    }

    private func seasonChanged(_ state: inout State) -> Effect<Action> {
        state.selectedQuality = nil
        state.movie = nil

        let episodes = state.selectedSeason?.episodes

        // Where you'd go on in this season, if it's that one; otherwise the site's pick or its first episode.
        state.selectedEpisode = if let target = resumeTarget(state), target.season == state.selectedSeason {
            target.episode
        } else if let first = episodes?.first(where: { $0.isSelected }) {
            first
        } else {
            episodes?.first
        }

        return episodeChanged(&state)
    }

    /// Where to go on in the chosen voice-over: the episode you stopped at, or once the player marked it watched to its
    /// end, the next one (the next season's first after a season's last). Never on the site's length alone: episodes
    /// run longer than it, and the rest of one would be skipped.
    private func resumeTarget(_ state: State) -> (season: MovieSeason, episode: MovieEpisode)? {
        guard let point = state.openingPoint, let seasons = state.seasons,
              let seasonIndex = seasons.firstIndex(where: { $0.seasonId == point.season }),
              let index = seasons[seasonIndex].episodes.firstIndex(where: { $0.episodeId == point.episode })
        else { return nil }

        let season = seasons[seasonIndex]
        let episode = season.episodes[index]

        guard let position = state.positions[State.positionKey(season, episode)], State.isPlayedToEnd(position) else {
            return (season, episode)
        }
        if index + 1 < season.episodes.count {
            return (season, season.episodes[index + 1])
        }
        if seasonIndex + 1 < seasons.count, let first = seasons[seasonIndex + 1].episodes.first {
            return (seasons[seasonIndex + 1], first)
        }
        return (season, episode)
    }

    /// This Mac's saved places in one voice-over (all its episodes, or the film), and their lengths, by
    /// `State.positionKey`.
    private func readPositions(_ acting: MovieVoiceActing) async -> SavedPlaces {
        let rows = (try? await database.read { db in
            try PlayerPosition
                .where { $0.id.id.eq(acting.voiceId) && $0.id.acting.eq(acting.translatorId) }
                .fetchAll(db)
        }) ?? []

        return SavedPlaces(
            positions: Dictionary(rows.map { ("\($0.id.season)|\($0.id.episode)", $0.position) }, uniquingKeysWith: { _, last in last }),
            durations: Dictionary(rows.compactMap { row in row.duration.map { ("\(row.id.season)|\(row.id.episode)", $0) } }, uniquingKeysWith: { _, last in last })
        )
    }

    private func episodeChanged(_ state: inout State) -> Effect<Action> {
        state.selectedQuality = nil
        state.movie = nil

        guard let details = state.details,
              let selectedSeason = state.selectedSeason,
              let selectedEpisode = state.selectedEpisode,
              let selectedActing = state.selectedActing
        else {
            return .cancel(id: CancelID.video)
        }

        return loadVideo(details: details, acting: selectedActing, season: selectedSeason, episode: selectedEpisode)
    }

    private func loadVideo(details: MovieDetailed, acting: MovieVoiceActing, season: MovieSeason?, episode: MovieEpisode?) -> Effect<Action> {
        .run { send in
            let result = await Result { try await getMovieVideoUseCase(voiceActing: acting, season: season, episode: episode, favs: details.favs) }

            await send(.videoLoaded(result), animation: .easeInOut)
        }
        .cancellable(id: CancelID.video, cancelInFlight: true)
    }
}

/// Saved places and lengths read from this Mac's database (see `MovieSelectionFeature.readPositions`).
struct SavedPlaces: Equatable, Sendable {
    var positions: [String: Double]
    var durations: [String: Double]
}
