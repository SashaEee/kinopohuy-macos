import AVKit
import ComposableArchitecture
import Defaults
import SQLiteData
import SwiftUI

@Reducer
struct PlayerFeature {
    @ObservableState
    struct State: Equatable {
        let poster: String
        let name: String
        let favs: String
        /// The title's id on the site, for another voice-over's seasons.
        let movieId: String
        /// The title's voice-overs, to switch between during playback, and each one's share of the viewers.
        let actings: [MovieVoiceActing]
        let popularity: [MovieVoiceActingRating]
        /// For the pause screen: the title's description as one paragraph, its facts («2024 · Драма, Триллер · 16+»)
        /// and the episodes' names from the site's schedule, by «season-episode».
        let synopsis: String?
        let facts: [String]
        let episodeNames: [String: String]
        /// Where the site says you stopped (logged in): the episodes before it count as watched.
        let siteSeries: Series?
        let hideMainWindow = Defaults[.hideMainWindow]
        let times: [Int]

        var voiceActing: MovieVoiceActing

        var seasons: [MovieSeason]?
        var season: MovieSeason?
        var episode: MovieEpisode?
        var movie: MovieVideo
        var quality: String

        var isReady = false
        var currentTime = 0.0
        var duration = Double.greatestFiniteMagnitude
        var loadedTimeRanges: [CMTimeRange] = []
        var isPlaying = true
        var isLoading = true
        var isMaskShow = true
        var timer: Int?
        var nextTimer: CGFloat?
        var error: EquatableError?
        var subtitles: String?
        var subtitlesOptions: [SubtitleOption] = []
        var thumbnails: WebVTT?
        var routesDetected = false
        var isPictureInPictureActive = false
        var isPictureInPicturePossible = false
        var isFocused = false
        var isDismissed = false

        var rate = Defaults[.rate]
        var isMuted = Defaults[.isMuted]
        var volume = Defaults[.volume]
        /// The stream's length once the player knows it (nil before: it starts as greatestFiniteMagnitude).
        var knownDuration: Double? {
            duration > 0 && duration < .greatestFiniteMagnitude ? duration : nil
        }

        /// What a key just did, shown for a moment over the picture.
        var hud: HUD?
        var playerFullscreen = Defaults[.playerFullscreen]
        /// A few seconds into a pause with nothing touched: the picture dims and says what's on, Netflix-style.
        var isPauseScreenShown = false
        var pauseReason: PauseReason = .user
        /// «Смотреть титры»: the next-episode card stays away for the rest of this episode.
        var isNextDismissed = false
        /// Episodes played to the end in this window («season-episode»), ticked in «Серии» besides the site's.
        var finishedEpisodes: Set<String> = []

        fileprivate var videoGravity = Defaults[.videoGravity]
        fileprivate var ambientLight = Defaults[.ambientLight]
        fileprivate var mediaControlButtonIsSeeking = Defaults[.mediaControlButtonIsSeeking]
        fileprivate var isMaskLocked = false
        /// A menu is open (the settings, the subtitles, the menu bar): the pause screen waits.
        fileprivate var isMenuTracking = false
        fileprivate var pendingSeek: Double?
        fileprivate var playsAfterSetup = true
        /// «С начала»: the first stream skips the saved position; later episodes resume as usual.
        fileprivate var startsOver: Bool
        /// Position ticks (about a second of playback each) since the site was last told the time.
        fileprivate var ticksSinceReport = 0
        /// The episode or film that just played to its end (its `itemKey`), until something plays again: the jump back
        /// to its start isn't saved as where it was left, nor told to the site. Kept through a reload, so a last tick
        /// of the old stream during the switch to the next episode can't undo it either.
        fileprivate var endedItem: String?
        /// A saved position read before the stream's length came in: it waits for it (a few seconds at most), since
        /// one in the last 90 s (the credits) starts over instead of resuming there.
        fileprivate var pendingResume: Double?
        /// Another voice-over's stream is loading, under its «Озвучка: …» notice.
        fileprivate var isVoiceLoading = false

        init(data: PlayerData) {
            let details = data.details

            poster = details.poster
            name = details.nameRussian
            favs = details.favs
            movieId = details.movieId.id ?? data.selectedActing.voiceId
            actings = details.voiceActing ?? []
            popularity = details.voiceActingRating ?? []
            synopsis = Self.synopsis(details.description)
            facts = Self.facts(details, isFilm: data.selectedEpisode == nil)
            episodeNames = Self.episodeNames(details.schedule)
            siteSeries = Defaults[.isLoggedIn] ? details.series : nil
            startsOver = data.startOver
            voiceActing = data.selectedActing
            seasons = data.seasons
            season = data.selectedSeason
            episode = data.selectedEpisode
            movie = data.movie
            quality = data.selectedQuality

            times = data.seasons != nil && data.selectedSeason != nil && data.selectedEpisode != nil ? [900, 1800, 2700, 3600, -1] : [900, 1800, 2700, 3600]
        }

        var isSeries: Bool {
            seasons != nil && season != nil && episode != nil
        }

        /// «voice-over-season-episode»: what's on, for the site's reports and for the end of an episode.
        fileprivate var itemKey: String {
            "\(voiceActing.translatorId)-\(season?.seasonId ?? "")-\(episode?.episodeId ?? "")"
        }

        /// The current episode's name from the schedule («Пилот»), when the site lists one.
        var episodeTitle: String? {
            guard let season, let episode else { return nil }
            return episodeNames[Self.episodeKey(season, episode)]
        }

        /// The next episode's name, for its card.
        var nextEpisodeTitle: String? {
            guard let (season, episode) = nextEpisode else { return nil }
            return episodeNames[Self.episodeKey(season, episode)]
        }

        /// The pause screen's kicker: what's on, or that it's over (the last episode, a film, the sleep timer's
        /// «До конца серии»).
        var pauseKicker: String {
            guard pauseReason == .finished else { return "Вы смотрите" }
            return isSeries ? "Серия закончилась" : "Фильм закончился"
        }

        /// Ticked in «Серии» («season-episode»): the episodes before where the site says you stopped (in this
        /// voice-over), and those played to the end here.
        var watchedEpisodes: Set<String> {
            var watched = finishedEpisodes
            guard let siteSeries, siteSeries.acting == voiceActing.translatorId, let seasons,
                  let stopSeason = seasons.firstIndex(where: { $0.seasonId == siteSeries.season })
            else { return watched }
            for season in seasons[..<stopSeason] {
                for episode in season.episodes { watched.insert(Self.episodeKey(season, episode)) }
            }
            let season = seasons[stopSeason]
            if let stop = season.episodes.firstIndex(where: { $0.episodeId == siteSeries.episode }) {
                for episode in season.episodes[..<stop] { watched.insert(Self.episodeKey(season, episode)) }
            }
            return watched
        }

        fileprivate var canShowPauseScreen: Bool {
            isReady && !isPlaying && !isLoading && error == nil && !isPictureInPictureActive && !isMaskLocked && !isMenuTracking
                && duration < .greatestFiniteMagnitude
        }

        var previousEpisode: (MovieSeason, MovieEpisode)? {
            guard let seasons, let season, let episode else { return nil }

            if let previous = season.episodes.element(before: episode) {
                return (season, previous)
            } else if let previousSeason = seasons.element(before: season), let previous = previousSeason.episodes.last {
                return (previousSeason, previous)
            }

            return nil
        }

        var nextEpisode: (MovieSeason, MovieEpisode)? {
            guard let seasons, let season, let episode else { return nil }

            if let next = season.episodes.element(after: episode) {
                return (season, next)
            } else if let nextSeason = seasons.element(after: season), let next = nextSeason.episodes.first {
                return (nextSeason, next)
            }

            return nil
        }

        var hasPreviousEpisode: Bool {
            previousEpisode != nil
        }

        var hasNextEpisode: Bool {
            nextEpisode != nil
        }

        fileprivate var isAmbientLightVisible: Bool {
            ambientLight && videoGravity == .fit && !isPictureInPictureActive
        }

        /// «1-4»: the schedule's numbers, so «01» and «1» meet.
        static func episodeKey(_ season: MovieSeason, _ episode: MovieEpisode) -> String {
            "\(Int(season.seasonId).map(String.init) ?? season.seasonId)-\(Int(episode.episodeId).map(String.init) ?? episode.episodeId)"
        }

        /// One paragraph: the site's line breaks and runs of spaces become single spaces.
        private static func synopsis(_ text: String) -> String? {
            let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return text.isEmpty || text == "-" ? nil : text
        }

        /// «2024 · Драма, Триллер · 2 ч 49 мин · 16+» (the length only for a film).
        private static func facts(_ details: MovieDetailed, isFilm: Bool) -> [String] {
            var facts: [String] = []
            // The year, or for a film that has only a release date, the year from it (as on the banners).
            if let year = details.year, !year.isEmpty {
                facts.append(year)
            } else if let date = details.releaseDate, let range = date.range(of: "(19|20)\\d\\d", options: .regularExpression) {
                facts.append(String(date[range]))
            }
            if let genres = details.genres, !genres.isEmpty { facts.append(genres.prefix(2).map(\.name).joined(separator: ", ")) }
            if isFilm, let duration = details.duration, duration > 0 {
                let hours = duration / 60, minutes = duration % 60
                facts.append(hours == 0 ? "\(minutes) мин" : minutes == 0 ? "\(hours) ч" : "\(hours) ч \(minutes) мин")
            }
            if let age = details.ageRestriction, !age.isEmpty { facts.append(age) }
            return facts
        }

        /// From the schedule's «1 сезон 4 серия»: the Russian name, or the original one; generic ones («Серия 4»,
        /// «Episode #1.4») are left out so they don't repeat the number.
        private static func episodeNames(_ schedule: [SeriesScheduleGroup]?) -> [String: String] {
            var names: [String: String] = [:]
            for item in schedule?.flatMap(\.items) ?? [] {
                guard let match = item.title.firstMatch(of: #/(\d+)\s*сезон\s*(\d+)\s*серия/#.ignoresCase()),
                      let season = Int(match.1), let episode = Int(match.2)
                else { continue }
                let name = [item.russianEpisodeName, item.originalEpisodeName ?? ""]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty && $0 != "-" && $0 != "—" && !isGenericEpisodeName($0) }
                if let name { names["\(season)-\(episode)"] = name }
            }
            return names
        }

        private static func isGenericEpisodeName(_ name: String) -> Bool {
            name.range(of: #"^(\d+\s*)?(серия|episode)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                || name.range(of: #"episode\s*#?\d"#, options: [.regularExpression, .caseInsensitive]) != nil
        }

        fileprivate var trackCommandMode: PlayerEngine.TrackCommandMode {
            if mediaControlButtonIsSeeking {
                .seeking
            } else if isSeries {
                .episodes(hasPrevious: hasPreviousEpisode, hasNext: hasNextEpisode)
            } else {
                .none
            }
        }
    }

    /// Why it's paused, for the pause screen: by you, by the sleep timer (it comes sooner and darker), or at the end.
    enum PauseReason: Equatable {
        case user
        case sleepTimer
        case finished
    }

    enum MoveDirection {
        case up
        case down
        case left
        case right
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case disappeared
        case selectPositionLoaded(subtitles: String?)
        case engine(PlayerEvent)
        case thumbnailsLoaded(WebVTT)
        case subtitleOptionsLoaded([SubtitleOption])
        case playbackPositionLoaded(Double?)
        /// The stream's length never came (a few seconds after the saved position): it resumes without it.
        case durationWaitExpired
        case defaultsChanged(DefaultsChange)
        case videoTapped
        case playPauseTapped
        case toggleMuteTapped
        case volumeChanged(Float)
        case seek(Double)
        case skip(Double)
        case moveCommand(MoveDirection)
        case previousTrackTapped
        case nextTrackTapped
        /// An episode picked in the player's «Серии» panel.
        case episodeSelected(MovieSeason, MovieEpisode)
        case trackLoaded(MovieSeason, MovieEpisode, Result<MovieVideo, any Error>)
        case qualitySelected(String)
        case subtitlesSelected(String?)
        case timerSelected(Int?)
        case pictureInPictureTapped
        case userActivity
        case hoverChanged(isActive: Bool)
        case lockMask(Bool)
        case unlockMask(Bool)
        case hideMaskFired
        case sleepTimerFired
        case hudExpired
        case scenePhaseChanged(isActive: Bool)
        case retryTapped
        case pauseScreenFired
        /// A menu opened or closed while the player's window is in front.
        case menuTracking(Bool)
        /// Another voice-over from the settings menu: the same episode at the same spot.
        case voiceSelected(MovieVoiceActing)
        /// Its stream, with (for a series) its seasons and its season and episode, found by the ids of what was on
        /// when it was picked: it is dropped if another episode is on by then.
        case voiceLoaded(MovieVoiceActing, [MovieSeason]?, MovieSeason?, MovieEpisode?, Result<MovieVideo, any Error>)
        case voiceRefused(String)
        /// «Смотреть титры» on the next-episode card.
        case creditsTapped
    }

    /// A jump (several in a row add up) or the volume after a key.
    enum HUD: Equatable {
        case skip(Double)
        case volume(Float)
        /// A short line: where it resumed, the voice-over it switched to, or why it couldn't.
        case notice(icon: String, text: String)
    }

    enum DefaultsChange {
        case rate(Float)
        case isMuted(Bool)
        case volume(Float)
        case spatialAudio(SpatialAudio)
        case playerFullscreen(Bool)
        case videoGravity(VideoGravity)
        case ambientLight(Bool)
        case mediaControlButtonIsSeeking(Bool)
    }

    private enum CancelID: Hashable {
        case engine
        case defaults
        case track
        case hideMask
        case sleepTimer
        case hud
        case pauseScreen
        case voice
        /// The wait for the stream's length before resuming.
        case resume
        /// One report in flight per episode: a newer one replaces it.
        case report(String)
    }

    /// Saved instead of a position once an episode or film reaches its last 90 s (the credits) or plays to its end:
    /// the player starts it over next time, and the title's page ticks it and moves on to the next episode.
    static let watchedMark = Double.greatestFiniteMagnitude

    let engine: PlayerEngine

    @Dependency(\.appRouter) private var appRouter
    @Dependency(\.saveWatchingStateUseCase) private var saveWatchingStateUseCase
    @Dependency(\.getMovieThumbnailsUseCase) private var getMovieThumbnailsUseCase
    @Dependency(\.getMovieVideoUseCase) private var getMovieVideoUseCase
    @Dependency(\.getSeriesSeasonsUseCase) private var getSeriesSeasonsUseCase
    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.continuousClock) private var clock

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .task:
                return .merge(
                    observeDefaults(),
                    .run { [voiceId = state.voiceActing.voiceId] send in
                        let position = try? await database.read { db in
                            try SelectPosition.where { $0.id.eq(voiceId) }.fetchOne(db)
                        }

                        await send(.selectPositionLoaded(subtitles: position?.subtitles))
                    }
                )

            case .disappeared:
                let report = reportProgress(state, outlivesWindow: true)

                resetState(&state)

                return .merge(
                    report,
                    .cancel(id: CancelID.engine),
                    .cancel(id: CancelID.defaults),
                    .cancel(id: CancelID.track),
                    .cancel(id: CancelID.hideMask),
                    .cancel(id: CancelID.sleepTimer),
                    .cancel(id: CancelID.hud),
                    .cancel(id: CancelID.pauseScreen),
                    .cancel(id: CancelID.voice),
                    .cancel(id: CancelID.resume),
                    perform { $0.reset() }
                )

            case let .selectPositionLoaded(subtitles):
                state.subtitles = subtitles

                return setup(&state, seek: nil, isPlaying: true)

            case let .engine(event):
                return handle(event, &state)

            case let .thumbnailsLoaded(thumbnails):
                state.thumbnails = thumbnails

                return .none

            case let .subtitleOptionsLoaded(options):
                state.subtitlesOptions = options

                return .none

            case var .playbackPositionLoaded(position):
                // «С начала» skips it once.
                if state.startsOver {
                    state.startsOver = false
                    position = nil
                }

                // The stream's length isn't in yet: without it the credits can't be told apart, so a title closed in
                // them would reopen there with «Продолжаем с …». It waits for the length, a few seconds at most.
                if let saved = position, saved >= 10, saved < Self.watchedMark, state.duration == .greatestFiniteMagnitude {
                    state.pendingResume = saved

                    return .run { send in
                        try await clock.sleep(for: .seconds(4))
                        await send(.durationWaitExpired)
                    }
                    .cancellable(id: CancelID.resume, cancelInFlight: true)
                }

                return resume(from: position, &state)

            case .durationWaitExpired:
                guard let saved = state.pendingResume else { return .none }

                state.pendingResume = nil

                return resume(from: saved, &state)

            case let .defaultsChanged(change):
                return handle(change, &state)

            case .videoTapped:
                guard state.isReady, !state.isPictureInPictureActive, !state.isLoading else { return .none }

                return togglePlayback(state)

            case .playPauseTapped:
                let resetTimer = resetSleepTimer(&state)

                guard !state.isPictureInPictureActive else { return resetTimer }

                return .merge(resetTimer, togglePlayback(state))

            case .toggleMuteTapped:
                let resetTimer = resetSleepTimer(&state)

                guard !state.isPictureInPictureActive else { return resetTimer }

                return .merge(resetTimer, noteActivity(&state), perform { $0.toggleMute() })

            case let .volumeChanged(volume):
                return .merge(noteActivity(&state), perform { $0.setVolume(volume) })

            case let .seek(seconds):
                return .merge(noteActivity(&state), perform { _ = await $0.seek(to: seconds) })

            case let .skip(interval):
                return .merge(noteActivity(&state), skip(by: interval, &state))

            case let .moveCommand(direction):
                let resetTimer = Effect.merge(resetSleepTimer(&state), noteActivity(&state))

                guard state.isReady, !state.isPictureInPictureActive else { return resetTimer }

                switch direction {
                case .up:
                    let volume = min(state.volume + 0.05, 1.0)
                    state.hud = .volume(volume)

                    guard state.volume < 1.0 else { return .merge(resetTimer, hudTimer()) }

                    return .merge(resetTimer, hudTimer(), perform { engine in engine.setVolume(volume) })
                case .down:
                    let volume = max(state.volume - 0.05, 0.0)
                    state.hud = .volume(volume)

                    guard state.volume > 0.0 else { return .merge(resetTimer, hudTimer()) }

                    return .merge(resetTimer, hudTimer(), perform { engine in engine.setVolume(volume) })
                case .left:
                    return .merge(resetTimer, skip(by: -10.0, &state))
                case .right:
                    return .merge(resetTimer, skip(by: 10.0, &state))
                }

            case .previousTrackTapped:
                guard let (season, episode) = state.previousEpisode else { return .none }

                return switchTrack(to: season, episode, &state)

            case .nextTrackTapped:
                guard let (season, episode) = state.nextEpisode else { return .none }

                return switchTrack(to: season, episode, &state)

            case let .episodeSelected(season, episode):
                guard season != state.season || episode != state.episode else { return .none }

                return switchTrack(to: season, episode, &state)

            case let .trackLoaded(season, episode, .success(movie)):
                guard !movie.needPremium else {
                    state.isDismissed = true

                    return .run { _ in appRouter.present(.premium) }
                }

                state.movie = movie
                state.season = season
                state.episode = episode

                return setup(&state, seek: nil, isPlaying: true)

            case let .trackLoaded(_, _, .failure(error)):
                state.error = EquatableError(error)

                return .none

            case let .qualitySelected(quality):
                state.quality = quality

                let seek = state.currentTime
                let isPlaying = state.isPlaying
                let dropVoice = cancelVoice(&state)

                resetState(&state)

                return .merge(dropVoice, setup(&state, seek: seek, isPlaying: isPlaying))

            case let .subtitlesSelected(language):
                state.subtitles = language

                return .merge(noteActivity(&state), perform { [voiceActing = state.voiceActing, season = state.season, episode = state.episode] engine in
                    guard await engine.selectSubtitles(language) else { return }

                    try? await database.write { db in
                        try SelectPosition
                            .upsert {
                                SelectPosition.Draft(
                                    id: voiceActing.voiceId,
                                    acting: voiceActing.translatorId,
                                    season: season?.seasonId,
                                    episode: episode?.episodeId,
                                    subtitles: language
                                )
                            }
                            .execute(db)
                    }
                })

            case let .timerSelected(timer):
                state.timer = timer

                return .merge(resetSleepTimer(&state), noteActivity(&state))

            case .pictureInPictureTapped:
                return .merge(noteActivity(&state), perform { $0.startPictureInPicture() })

            case .userActivity:
                return .merge(resetSleepTimer(&state), noteActivity(&state))

            case let .hoverChanged(isActive):
                // The pointer leaving the window keeps the pause screen up; only coming back wakes it.
                if !isActive, state.isPauseScreenShown { return resetSleepTimer(&state) }

                let isMaskShown = isActive
                    ? !state.isPictureInPictureActive
                    : (state.isLoading || !state.isPlaying) && !state.isPictureInPictureActive

                return .merge(
                    resetSleepTimer(&state),
                    showCursor(),
                    setMask(isMaskShown, &state)
                )

            case let .lockMask(isMaskShown):
                state.isMaskLocked = true
                state.isMaskShow = isMaskShown
                state.isPauseScreenShown = false

                return .merge(.cancel(id: CancelID.hideMask), .cancel(id: CancelID.pauseScreen))

            case let .unlockMask(isMaskShown):
                state.isMaskLocked = false

                return setMask(isMaskShown, &state)

            case .hideMaskFired:
                return .merge(showCursor(false), setMask(false, &state))

            case .hudExpired:
                state.hud = nil

                return .none

            case .sleepTimerFired:
                guard state.isReady else { return .none }

                state.pauseReason = .sleepTimer

                return perform { $0.pause() }

            case let .scenePhaseChanged(isActive):
                guard !isActive, state.isReady, !state.isPictureInPictureActive, state.isPlaying else { return .none }

                return perform { $0.pause() }

            case .retryTapped:
                let dropVoice = cancelVoice(&state)

                resetState(&state)

                return .merge(dropVoice, setup(&state, seek: nil, isPlaying: true))

            case .pauseScreenFired:
                guard state.canShowPauseScreen, !state.isPauseScreenShown else { return .none }

                state.isPauseScreenShown = true
                state.isMaskShow = false

                return .merge(showCursor(false), .cancel(id: CancelID.hideMask))

            case let .menuTracking(isTracking):
                state.isMenuTracking = isTracking

                guard !state.isPlaying, !state.isPictureInPictureActive else { return .none }

                // Opening one wakes the pause screen and holds it off; closing one counts the pause from there.
                if isTracking {
                    return state.isPauseScreenShown ? setMask(true, &state) : .cancel(id: CancelID.pauseScreen)
                }

                return state.isMaskShow ? setMask(true, &state) : .none

            case let .voiceSelected(acting):
                let wake = noteActivity(&state)

                guard state.isReady, acting.translatorId != state.voiceActing.translatorId else { return wake }

                state.hud = .notice(icon: "waveform", text: "Озвучка: \(acting.name)…")
                state.isVoiceLoading = true

                return .merge(wake, hudTimer(seconds: 8), loadVoice(acting, state))

            case let .voiceLoaded(acting, seasons, season, episode, .success(movie)):
                // Only for what's on: another episode started meanwhile (or the player is reloading), and this
                // stream would play the wrong one, or save the new episode's place under the old voice-over.
                guard state.isReady, season?.seasonId == state.season?.seasonId, episode?.episodeId == state.episode?.episodeId else {
                    return cancelVoice(&state)
                }

                state.isVoiceLoading = false

                guard !movie.needPremium else {
                    return refuse("Озвучка «\(acting.name)» — только с премиумом", &state)
                }

                let report = reportProgress(state)
                let seek = state.currentTime
                let isPlaying = state.isPlaying
                let qualities = movie.getAvailableQualities()

                state.voiceActing = acting
                if let seasons, let season, let episode {
                    state.seasons = seasons
                    state.season = season
                    state.episode = episode
                }
                state.movie = movie
                if !qualities.isEmpty, !qualities.contains(state.quality), let best = qualities.last {
                    state.quality = best
                }
                state.hud = .notice(icon: "waveform", text: "Озвучка: \(acting.name)")

                resetState(&state)

                return .merge(report, hudTimer(seconds: 2.2), setup(&state, seek: seek, isPlaying: isPlaying))

            case .voiceLoaded(_, _, _, _, .failure):
                state.isVoiceLoading = false

                return refuse("Не получилось переключить озвучку", &state)

            case let .voiceRefused(message):
                state.isVoiceLoading = false

                return refuse(message, &state)

            case .creditsTapped:
                state.isNextDismissed = true
                updateNextTimer(&state)

                return .none
            }
        }
    }

    private func handle(_ event: PlayerEvent, _ state: inout State) -> Effect<Action> {
        switch event {
        case let .time(seconds):
            state.currentTime = seconds
            updateNextTimer(&state)

            return .none

        case let .positionTick(seconds):
            // Played to its end: the jump back to the start is neither where it was left nor news for the site.
            guard state.endedItem != state.itemKey else { return .none }

            state.ticksSinceReport += 1

            var report = Effect<Action>.none
            if state.ticksSinceReport >= 15 {
                state.ticksSinceReport = 0
                report = reportProgress(state)
            }

            // In the last 90 s (the credits) it counts as watched, as the player itself treats it next time.
            let position = seconds > state.duration - 90 ? Self.watchedMark : seconds

            return .merge(report, .run { [voiceActing = state.voiceActing, season = state.season, episode = state.episode, duration = state.knownDuration] _ in
                await savePosition(position, duration: duration, voiceActing: voiceActing, season: season, episode: episode)
            })

        case .status(.readyToPlay):
            state.isReady = true
            state.isFocused = true
            updateNextTimer(&state)

            return .merge(
                .run { [voiceActing = state.voiceActing, season = state.season, episode = state.episode] _ in
                    if Defaults[.isLoggedIn] {
                        _ = try? await saveWatchingStateUseCase(voiceActing: voiceActing, season: season, episode: episode)
                    }

                    try? await database.write { db in
                        try SelectPosition
                            .upsert {
                                SelectPosition.Draft(
                                    id: voiceActing.voiceId,
                                    acting: voiceActing.translatorId,
                                    season: season?.seasonId,
                                    episode: episode?.episodeId
                                )
                            }
                            .execute(db)
                    }
                },
                .run { [engine, subtitles = state.subtitles] send in
                    let options = await engine.subtitleOptions(selecting: subtitles)

                    await send(.subtitleOptionsLoaded(options), animation: .easeInOut(duration: 0.15))
                },
                perform { [mode = state.trackCommandMode] engine in engine.configureTrackCommands(mode) },
                // Reloaded while paused (another quality or voice-over): the pause counts from here.
                state.playsAfterSetup ? .none : armPauseScreen(state),
                startPlayback(state)
            )

        case .status:
            return .none

        case let .timeControlStatus(status):
            let wasPlaying = state.isPlaying

            switch status {
            case .playing:
                state.isPlaying = true
                state.isLoading = false
                state.pauseReason = .user
                // Played again after its end: where it is from now on is saved again.
                state.endedItem = nil
            case .paused:
                // The same status again under the pause screen: nothing changed, keep it.
                if state.isPauseScreenShown, !state.isPlaying, !state.isLoading { return .none }

                state.isPlaying = false
                state.isLoading = false
                if wasPlaying { state.ticksSinceReport = 0 }
            default:
                state.isPlaying = false
                state.isLoading = true
            }

            updateNextTimer(&state)

            return .merge(
                status == .paused && wasPlaying ? reportProgress(state) : .none,
                showCursor(),
                setMask(!state.isPictureInPictureActive, &state)
            )

        case let .isMuted(isMuted):
            updateNextTimer(&state)

            return .merge(
                .run { _ in Defaults[.isMuted] = isMuted },
                showCursor(),
                setMask(!state.isPictureInPictureActive, &state)
            )

        case let .volume(volume):
            updateNextTimer(&state)

            return .merge(
                perform { engine in
                    Defaults[.volume] = volume

                    engine.setMuted(Defaults[.isMuted])
                },
                showCursor(),
                setMask(!state.isPictureInPictureActive, &state)
            )

        case let .duration(duration):
            state.duration = duration
            updateNextTimer(&state)

            // The saved position was waiting for it.
            guard let saved = state.pendingResume else { return .none }

            state.pendingResume = nil

            return .merge(.cancel(id: CancelID.resume), resume(from: saved, &state))

        case let .loadedTimeRanges(ranges):
            state.loadedTimeRanges = ranges

            return .none

        case let .failed(error):
            let dropVoice = cancelVoice(&state)

            resetState(&state)
            state.error = EquatableError(error)

            return .merge(dropVoice, perform { $0.reset() })

        case .didPlayToEnd:
            let isPictureInPictureActive = state.isPictureInPictureActive
            let advances = state.timer != -1 && state.hasNextEpisode
            let report = reportProgress(state, position: state.duration)

            if let season = state.season, let episode = state.episode {
                state.finishedEpisodes.insert(State.episodeKey(season, episode))
            }

            if !advances, !isPictureInPictureActive {
                state.pauseReason = .finished
            }

            state.endedItem = state.itemKey

            return .merge(report, .run { [engine, voiceActing = state.voiceActing, season = state.season, episode = state.episode, duration = state.knownDuration] send in
                _ = await engine.seek(to: 0)

                // Watched, saved after the jump back so nothing from before it lands later: the title's page ticks
                // it and the player starts it over next time.
                await savePosition(Self.watchedMark, duration: duration, voiceActing: voiceActing, season: season, episode: episode)

                if isPictureInPictureActive {
                    await engine.stopPictureInPicture()
                } else if advances {
                    await send(.nextTrackTapped, animation: .easeInOut(duration: 0.15))
                }
            })

        case let .routesDetected(routesDetected):
            state.routesDetected = routesDetected

            return .none

        case let .pictureInPictureActive(isActive):
            state.isPictureInPictureActive = isActive
            if isActive { state.isPauseScreenShown = false }
            updateNextTimer(&state)

            return .merge(
                showCursor(),
                setMask(!isActive, &state),
                perform { [isVisible = state.isAmbientLightVisible] engine in engine.setAmbientLight(isVisible) }
            )

        case let .pictureInPicturePossible(isPossible):
            state.isPictureInPicturePossible = isPossible

            return .none

        case let .remote(command):
            switch command {
            case .play:
                return perform { [rate = state.rate] engine in engine.play(rate: rate) }
            case .pause:
                return perform { $0.pause() }
            case .togglePlayPause:
                return togglePlayback(state)
            case let .changePosition(position):
                return .merge(noteActivity(&state), perform { _ = await $0.seek(to: position) })
            case let .changeRate(rate):
                return .run { _ in Defaults[.rate] = rate }
            case let .skip(interval):
                return .merge(noteActivity(&state), skip(by: interval, &state))
            case .previousTrack:
                return .run { send in await send(.previousTrackTapped, animation: .easeInOut(duration: 0.15)) }
            case .nextTrack:
                return .run { send in await send(.nextTrackTapped, animation: .easeInOut(duration: 0.15)) }
            }
        }
    }

    private func handle(_ change: DefaultsChange, _ state: inout State) -> Effect<Action> {
        switch change {
        case let .rate(rate):
            state.rate = rate

            return perform { [isPlaying = state.isPlaying] engine in engine.setRate(rate, isPlaying: isPlaying) }

        case let .isMuted(isMuted):
            state.isMuted = isMuted

            return .none

        case let .volume(volume):
            state.volume = volume

            return .none

        case let .spatialAudio(spatialAudio):
            return perform { $0.setSpatialAudio(spatialAudio) }

        case let .playerFullscreen(playerFullscreen):
            state.playerFullscreen = playerFullscreen

            return .none

        case let .videoGravity(videoGravity):
            state.videoGravity = videoGravity

            return perform { [isVisible = state.isAmbientLightVisible] engine in
                engine.setAmbientLight(isVisible)
                engine.setVideoGravity(videoGravity)
            }

        case let .ambientLight(ambientLight):
            state.ambientLight = ambientLight

            return perform { [isVisible = state.isAmbientLightVisible] engine in engine.setAmbientLight(isVisible) }

        case let .mediaControlButtonIsSeeking(isSeeking):
            state.mediaControlButtonIsSeeking = isSeeking

            guard state.isReady else { return .none }

            return perform { [mode = state.trackCommandMode] engine in engine.configureTrackCommands(mode) }
        }
    }

    private func setup(_ state: inout State, seek: Double?, isPlaying: Bool) -> Effect<Action> {
        guard let urls = state.movie.getClosestTo(quality: state.quality)?.compactMap(\.hls), !urls.isEmpty else { return .none }

        state.pendingSeek = seek
        state.playsAfterSetup = isPlaying

        let configuration = PlayerEngine.Configuration(
            urls: urls,
            subtitles: state.movie.subtitles,
            title: state.name,
            album: state.voiceActing.name,
            artist: state.season.flatMap { season in state.episode.map { "Season \(season.name) Episode \($0.name)" } },
            poster: state.poster,
            videoGravity: state.videoGravity,
            ambientLight: state.isAmbientLightVisible,
            volume: state.volume,
            isMuted: state.isMuted,
            rate: state.rate
        )

        var effects: [Effect<Action>] = [
            .run { [engine] send in
                let events = await engine.load(configuration)

                for await event in events {
                    await send(.engine(event), animation: event.animation)
                }
            }
            .cancellable(id: CancelID.engine, cancelInFlight: true),
        ]

        if let path = state.movie.thumbnails {
            effects.append(
                .run { send in
                    guard let thumbnails = try? await getMovieThumbnailsUseCase(path: path) else { return }

                    await send(.thumbnailsLoaded(thumbnails))
                }
            )
        }

        return .merge(effects)
    }

    private func startPlayback(_ state: State) -> Effect<Action> {
        if let seek = state.pendingSeek {
            return perform { [rate = state.rate, isPlaying = state.playsAfterSetup] engine in
                _ = await engine.seek(to: seek)

                if isPlaying {
                    engine.play(rate: rate)
                }
            }
        }

        return .run { [voiceActing = state.voiceActing, season = state.season, episode = state.episode] send in
            let position = try? await database.read { db in
                try PlayerPosition
                    .where {
                        $0.id.id.eq(voiceActing.voiceId) &&
                            $0.id.acting.eq(voiceActing.translatorId) &&
                            $0.id.season.eq(season?.seasonId ?? "") &&
                            $0.id.episode.eq(episode?.episodeId ?? "")
                    }
                    .fetchOne(db)
            }

            await send(.playbackPositionLoaded(position?.position))
        }
    }

    /// Resumes past the first 10 s and not in the last 90 (the credits) nor once played to the end: from the start
    /// then. Seeks first, so the picture doesn't flash the start.
    private func resume(from position: Double?, _ state: inout State) -> Effect<Action> {
        var position = position
        if let saved = position, saved < 10 || saved >= Self.watchedMark || saved > state.duration - 90 {
            position = nil
        }

        var notice = Effect<Action>.none
        if let position, position >= 30 {
            state.hud = .notice(icon: "arrow.counterclockwise", text: "Продолжаем с \(Self.clock(position))")
            notice = hudTimer(seconds: 2.6)
        }

        return .merge(notice, perform { [rate = state.rate, isPlaying = state.playsAfterSetup] engine in
            if let position {
                let isComplete = await engine.seek(to: position)

                if isPlaying, isComplete {
                    engine.play(rate: rate)
                }
            } else if isPlaying {
                engine.play(rate: rate)
            }
        })
    }

    private func switchTrack(to season: MovieSeason, _ episode: MovieEpisode, _ state: inout State) -> Effect<Action> {
        let report = reportProgress(state)
        let dropVoice = cancelVoice(&state)

        resetState(&state)

        return .merge(report, dropVoice, .run { [engine, voiceActing = state.voiceActing, favs = state.favs] send in
            await engine.reset()

            let result = await Result { try await getMovieVideoUseCase(voiceActing: voiceActing, season: season, episode: episode, favs: favs) }

            await send(.trackLoaded(season, episode, result))
        }
        .cancellable(id: CancelID.track, cancelInFlight: true))
    }

    /// The other voice-over's stream for what's on. For a series, its seasons first: if it lacks this episode, it
    /// says so and the current one keeps playing.
    private func loadVoice(_ acting: MovieVoiceActing, _ state: State) -> Effect<Action> {
        .run { [movieId = state.movieId, favs = state.favs, isSeries = state.isSeries, season = state.season, episode = state.episode] send in
            guard isSeries, let season, let episode else {
                let result = await Result { try await getMovieVideoUseCase(voiceActing: acting, season: nil, episode: nil, favs: favs) }

                await send(.voiceLoaded(acting, nil, nil, nil, result))

                return
            }

            do {
                let seasons = try await getSeriesSeasonsUseCase(movieId: movieId, voiceActing: acting, favs: favs)

                guard let newSeason = seasons.first(where: { $0.seasonId == season.seasonId }),
                      let newEpisode = newSeason.episodes.first(where: { $0.episodeId == episode.episodeId })
                else {
                    await send(.voiceRefused("В озвучке «\(acting.name)» нет этой серии"))

                    return
                }

                let result = await Result { try await getMovieVideoUseCase(voiceActing: acting, season: newSeason, episode: newEpisode, favs: favs) }

                await send(.voiceLoaded(acting, seasons, newSeason, newEpisode, result))
            } catch {
                await send(.voiceLoaded(acting, nil, nil, nil, .failure(error)))
            }
        }
        .cancellable(id: CancelID.voice, cancelInFlight: true)
    }

    /// Drops a voice-over still loading when another episode, quality, a retry or an error comes first: its stream is
    /// for what was on then. Its «Озвучка: …» notice goes with it.
    private func cancelVoice(_ state: inout State) -> Effect<Action> {
        if state.isVoiceLoading {
            state.isVoiceLoading = false

            if case .notice(icon: "waveform", text: _) = state.hud {
                state.hud = nil
            }
        }

        return .cancel(id: CancelID.voice)
    }

    /// Where this episode or film was left (or `watchedMark`), for this Mac: the player resumes there, and the title's
    /// page offers «Продолжить» and ticks the episodes.
    private func savePosition(_ position: Double, duration: Double?, voiceActing: MovieVoiceActing, season: MovieSeason?, episode: MovieEpisode?) async {
        try? await database.write { db in
            try PlayerPosition
                .upsert {
                    PlayerPosition.Draft(
                        id: PlayerPosition.ID(
                            id: voiceActing.voiceId,
                            acting: voiceActing.translatorId,
                            season: season?.seasonId,
                            episode: episode?.episodeId
                        ),
                        position: position,
                        duration: duration
                    )
                }
                .execute(db)
        }
    }

    /// The title's row in this Mac's history (what was last played of it, how far, how long it runs): posters and
    /// «Продолжить просмотр» show it. Written as often as the site hears, not every second.
    private static func saveHistory(_ position: Double, duration: Double, voiceActing: MovieVoiceActing, season: MovieSeason?, episode: MovieEpisode?) async {
        @Dependency(\.defaultDatabase) var database
        try? await database.write { db in
            try WatchHistory
                .upsert {
                    WatchHistory.Draft(
                        id: voiceActing.voiceId,
                        acting: voiceActing.translatorId,
                        season: season?.seasonId ?? "",
                        episode: episode?.episodeId ?? "",
                        position: position,
                        duration: duration,
                        updatedAt: Date().timeIntervalSince1970
                    )
                }
                .execute(db)
        }
    }

    /// Says why for a moment; whatever was playing goes on.
    private func refuse(_ message: String, _ state: inout State) -> Effect<Action> {
        state.hud = .notice(icon: "exclamationmark.circle", text: message)

        return hudTimer(seconds: 2.8)
    }

    /// Tells the site how far this episode or film got (logged in only), so its «Досмотреть», the TV and the title's
    /// page pick up here. outlivesWindow: sent from closing, it finishes even though the player is gone.
    private func reportProgress(_ state: State, position: Double? = nil, outlivesWindow: Bool = false) -> Effect<Action> {
        guard state.isReady, state.duration > 0, state.duration < .greatestFiniteMagnitude else { return .none }
        // Played to its end and back at the start: the site already heard it was watched.
        guard position != nil || state.endedItem != state.itemKey else { return .none }

        let position = Int(min(position ?? state.currentTime, state.duration).rounded())
        let total = Int(state.duration.rounded())

        guard position > 0 else { return .none }

        let voiceActing = state.voiceActing
        let season = state.season
        let episode = state.episode
        let key = state.itemKey

        // The credits count as watched, as the player itself treats them next time.
        let historyPosition = Double(position) >= state.duration - 90 ? Self.watchedMark : Double(position)
        let duration = state.duration

        let deliver: @Sendable () async -> Void = {
            await Self.saveHistory(historyPosition, duration: duration, voiceActing: voiceActing, season: season, episode: episode)

            guard Defaults[.isLoggedIn] else { return }

            _ = try? await saveWatchingStateUseCase(voiceActing: voiceActing, season: season, episode: episode, position: position, total: total)
        }

        if outlivesWindow {
            return .run { _ in Task { await deliver() } }
        }

        return .run { _ in await deliver() }
            .cancellable(id: CancelID.report(key), cancelInFlight: true)
    }

    private func resetState(_ state: inout State) {
        state.isReady = false
        state.error = nil
        state.nextTimer = nil
        state.subtitlesOptions = []
        state.isLoading = true
        state.thumbnails = nil
        state.duration = .greatestFiniteMagnitude
        state.currentTime = 0.0
        state.isPauseScreenShown = false
        state.pauseReason = .user
        state.isNextDismissed = false
        state.ticksSinceReport = 0
        state.pendingResume = nil
    }

    private func togglePlayback(_ state: State) -> Effect<Action> {
        perform { [isPlaying = state.isPlaying, rate = state.rate] engine in
            if isPlaying {
                engine.pause()
            } else {
                engine.play(rate: rate)
            }
        }
    }

    private func skip(by interval: Double, _ state: inout State) -> Effect<Action> {
        let target = min(max(state.currentTime + interval, 0.0), state.duration)

        state.currentTime = target

        if case let .skip(total) = state.hud, (total < 0) == (interval < 0) {
            state.hud = .skip(total + interval)
        } else {
            state.hud = .skip(interval)
        }

        return .merge(
            hudTimer(),
            perform { [isPlaying = state.isPlaying, rate = state.rate] engine in
                if await engine.seek(to: target), isPlaying {
                    engine.play(rate: rate)
                }
            },
        )
    }

    private func hudTimer(seconds: Double = 1.1) -> Effect<Action> {
        .run { send in
            try await clock.sleep(for: .seconds(seconds))
            await send(.hudExpired, animation: .easeOut(duration: 0.35))
        }
        .cancellable(id: CancelID.hud, cancelInFlight: true)
    }

    /// Shows or hides the controls. Showing them ends the pause screen and, while paused, counts the pause anew;
    /// during playback they hide again 3 s later.
    private func setMask(_ isMaskShown: Bool, _ state: inout State) -> Effect<Action> {
        guard !state.isMaskLocked else { return .cancel(id: CancelID.pauseScreen) }

        state.isMaskShow = isMaskShown

        if isMaskShown {
            state.isPauseScreenShown = false
        }

        guard isMaskShown, !state.isLoading, state.isPlaying else {
            return .merge(.cancel(id: CancelID.hideMask), isMaskShown ? armPauseScreen(state) : .cancel(id: CancelID.pauseScreen))
        }

        return .merge(
            .cancel(id: CancelID.pauseScreen),
            .run { send in
                try await clock.sleep(for: .seconds(3))

                await send(.hideMaskFired, animation: .easeInOut)
            }
            .cancellable(id: CancelID.hideMask, cancelInFlight: true)
        )
    }

    /// The pause screen comes 6 s into a pause with nothing touched (2 s after the sleep timer: you've likely dozed
    /// off). Sent without animation: the view has its own curves.
    private func armPauseScreen(_ state: State) -> Effect<Action> {
        guard state.canShowPauseScreen else { return .cancel(id: CancelID.pauseScreen) }

        var delay: Double = state.pauseReason == .sleepTimer ? 2 : 6

        #if DEBUG
        // Test hook: KP_PAUSE_DELAY=1 brings it sooner, for screenshots.
        if let value = ProcessInfo.processInfo.environment["KP_PAUSE_DELAY"].flatMap(Double.init) { delay = value }
        #endif

        return .run { [delay] send in
            try await clock.sleep(for: .seconds(delay))

            await send(.pauseScreenFired)
        }
        .cancellable(id: CancelID.pauseScreen, cancelInFlight: true)
    }

    /// A key, a click or a jump while paused (or under the pause screen) brings the controls back and counts the
    /// pause anew; during playback it changes nothing (an arrow only shows the HUD).
    private func noteActivity(_ state: inout State) -> Effect<Action> {
        guard !state.isPlaying || state.isPauseScreenShown else { return .none }

        return .merge(showCursor(), setMask(!state.isPictureInPictureActive, &state))
    }

    private func resetSleepTimer(_ state: inout State) -> Effect<Action> {
        updateNextTimer(&state)

        guard let timer = state.timer, timer > 0, state.isPlaying else { return .cancel(id: CancelID.sleepTimer) }

        return .run { send in
            try await clock.sleep(for: .seconds(timer))

            await send(.sleepTimerFired)
        }
        .cancellable(id: CancelID.sleepTimer, cancelInFlight: true)
    }

    private func updateNextTimer(_ state: inout State) {
        let remaining = (state.duration - state.currentTime) / 60

        // A jump back out of the last minute brings «Смотреть титры»'s card back next time.
        if remaining > 1, state.isNextDismissed {
            state.isNextDismissed = false
        }

        if remaining > 0, remaining <= 1, state.hasNextEpisode, state.timer != -1, !state.isPictureInPictureActive, !state.isNextDismissed {
            state.nextTimer = min(remaining, 1.0)
        } else if state.nextTimer != nil {
            state.nextTimer = nil
        }
    }

    /// 754 → «12:34», 3754 → «1:02:34».
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s < 3600 ? String(format: "%d:%02d", s / 60, s % 60) : String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    private func perform(_ operation: @escaping @MainActor @Sendable (PlayerEngine) async -> Void) -> Effect<Action> {
        .run { [engine] _ in await operation(engine) }
    }

    private func showCursor(_ isShowed: Bool = true) -> Effect<Action> {
        perform { $0.showCursor(isShowed) }
    }

    private func observeDefaults() -> Effect<Action> {
        .run { send in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await value in Defaults.updates(.rate, initial: false) { await send(.defaultsChanged(.rate(value))) } }
                group.addTask { for await value in Defaults.updates(.isMuted, initial: false) { await send(.defaultsChanged(.isMuted(value)), animation: .easeInOut(duration: 0.15)) } }
                group.addTask { for await value in Defaults.updates(.volume, initial: false) { await send(.defaultsChanged(.volume(value)), animation: .easeInOut(duration: 0.15)) } }
                group.addTask { for await value in Defaults.updates(.spatialAudio, initial: false) { await send(.defaultsChanged(.spatialAudio(value))) } }
                group.addTask { for await value in Defaults.updates(.playerFullscreen, initial: false) { await send(.defaultsChanged(.playerFullscreen(value))) } }
                group.addTask { for await value in Defaults.updates(.videoGravity, initial: false) { await send(.defaultsChanged(.videoGravity(value))) } }
                group.addTask { for await value in Defaults.updates(.ambientLight, initial: false) { await send(.defaultsChanged(.ambientLight(value))) } }
                group.addTask { for await value in Defaults.updates(.mediaControlButtonIsSeeking, initial: false) { await send(.defaultsChanged(.mediaControlButtonIsSeeking(value))) } }
            }
        }
        .cancellable(id: CancelID.defaults, cancelInFlight: true)
    }
}

private extension PlayerEvent {
    var animation: Animation? {
        switch self {
        case .time, .positionTick, .loadedTimeRanges, .duration, .status, .isMuted, .volume, .remote, .didPlayToEnd:
            nil
        case .timeControlStatus, .routesDetected, .pictureInPicturePossible:
            .easeInOut(duration: 0.15)
        case .failed, .pictureInPictureActive:
            .easeInOut
        }
    }
}
