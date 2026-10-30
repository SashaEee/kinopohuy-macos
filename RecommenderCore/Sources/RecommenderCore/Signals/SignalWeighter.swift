import Foundation

/// Where the user is with a title.
enum WatchState: Sendable, Hashable {
    /// Never started (or «Это смотрел не я»).
    case none
    /// Started and not finished: it lives in «Продолжить», not in recommendations.
    case started
    /// Watched to the end, marked watched on the site, «Уже смотрел» or rated.
    case seen
}

/// A place in a series: where to continue it.
struct EpisodeRef: Sendable, Hashable {
    var season: Int
    var episode: Int
    /// The episode after the last one finished on this Mac (otherwise: where the site says you are).
    var isNext: Bool
}

/// What the signals say about one title (§4.2): its taste weight, the intent to watch it, and where the user is.
struct TitleSignal: Sendable, Hashable {
    let titleId: String
    /// Taste weight after decay, in [−2, 2]. An explicit rating overrides every implicit signal.
    var weight: Double = 0
    /// The latest explicit rating (not decayed), nil when there is none.
    var explicitLevel: Double?
    /// Intent to watch (bookmarks, «Досмотреть» without progress, followed): drives «Можно начать», not taste.
    var intent: Double = 0
    var state: WatchState = .none
    /// Watched to the end here or marked watched on the site (not just rated): «Вы досмотрели «X»» is true.
    var finished = false
    /// The latest activity on the title (seconds since 1970).
    var lastActivity: Double?
    /// When it was watched to the end (for the holdout).
    var completedAt: Double?
    /// A hard exclusion from feedback («Не моё», «Скрыть», «Не сегодня», «Бросил», «Не учитывать «X»»).
    var exclusion: FilterReason?
    var bookmarkFolders: [String] = []
    var inLovedFolder = false
    var inAccountList = false
    /// In «Досмотреть», not watched, no progress: «Можно начать».
    var accountListNoProgress = false
    var followed = false
    var notMe = false
    var notSeed = false
    var continueHidden = false
    /// Films: how far the furthest viewing got (0…1), when played on this Mac.
    var filmFraction: Double?
    /// Series: episodes watched to the end, the furthest season, where to continue.
    var episodesWatched = 0
    var lastSeason: Int?
    var resume: EpisodeRef?
    /// The title has local player data (sessions or saved positions).
    var hasLocalData = false

    init(titleId: String) {
        self.titleId = titleId
    }

    /// Explicitly disliked («Не моё», an import of ≤4/10): counts for the person dislike floor.
    var isDisliked: Bool { (explicitLevel ?? 0) <= -1 }
    /// Explicitly «Обожаю» or kept in a «любимое» folder.
    var isLoved: Bool { (explicitLevel ?? 0) >= 2 || inLovedFolder }
}

/// Turns raw signals into per-title weights (§4.2): explicit levels with a 2-year half-life, implicit signals from
/// the player, «Досмотреть», bookmarks and follows with dual-memory decay, all clamped to [−2, 2].
enum SignalWeighter {
    /// A session shorter than this (and not played to the end) is an accidental click.
    static let accidentalSessionSeconds: Double = 180
    /// Two completions closer than this are one viewing logged twice, not a rewatch.
    static let rewatchGapSeconds: Double = 6 * 3600

    static func weigh(
        _ signals: UserSignals, titles: [String: TitleFeatures], settings: RecommenderSettings, weights: Weights,
        context: EngineContext,
    ) -> [String: TitleSignal] {
        let now = context.now
        let day = EngineTime.day
        let offset = EngineTime.utcOffset(context)

        // Feedback still in force.
        var feedback: [String: Set<FeedbackKind>] = [:]
        var droppedAt: [String: Double] = [:]
        for item in signals.feedback where isActive(item, now: now, weights: weights) {
            feedback[item.titleId, default: []].insert(item.kind)
            if item.kind == .dropped { droppedAt[item.titleId] = max(droppedAt[item.titleId] ?? 0, item.createdAt) }
        }

        // Explicit ratings: the latest per title wins. Onboarding group picks (|level| < 1) are a fading pseudo-signal
        // rather than a rating: the user chose a group, not this title.
        var explicit: [String: ExplicitRating] = [:]
        var pseudo: [String: ExplicitRating] = [:]
        let orderedRatings = signals.ratings.sorted {
            ($0.createdAt, $0.titleId, $0.level) < ($1.createdAt, $1.titleId, $1.level)
        }
        for rating in orderedRatings {
            if rating.source == .onboarding, abs(rating.level) < 1, rating.level != 0 {
                pseudo[rating.titleId] = rating
            } else {
                explicit[rating.titleId] = rating
            }
        }

        let sessions = settings.useLocalHistory ? Dictionary(grouping: signals.sessions, by: \.titleId) : [:]
        let progress = settings.useLocalHistory
            ? Dictionary(signals.progress.map { ($0.titleId, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
            : [:]
        let account = settings.useAccountList
            ? Dictionary(signals.accountList.map { ($0.titleId, $0) }, uniquingKeysWith: { lhs, _ in lhs })
            : [:]
        let bookmarks = settings.useBookmarks ? Dictionary(grouping: signals.bookmarks, by: \.titleId) : [:]
        let followed = Set(signals.followed)

        var ids = Set<String>()
        ids.formUnion(sessions.keys)
        ids.formUnion(progress.keys)
        ids.formUnion(account.keys)
        ids.formUnion(bookmarks.keys)
        ids.formUnion(followed)
        ids.formUnion(explicit.keys)
        ids.formUnion(pseudo.keys)
        ids.formUnion(feedback.keys)

        var result: [String: TitleSignal] = [:]
        result.reserveCapacity(ids.count)
        for id in ids.sorted(by: TitleOrder.precedes) {
            let title = titles[id]
            let kinds = feedback[id] ?? []
            var signal = TitleSignal(titleId: id)
            signal.notMe = kinds.contains(.notMe)
            signal.notSeed = kinds.contains(.notSeed)
            signal.continueHidden = kinds.contains(.continueHidden)

            // Implicit components: (value, when). `nil` time = current state (a bookmark exists now): no decay.
            var components: [(value: Double, at: Double?)] = []
            var localState: WatchState = .none

            let played = (sessions[id] ?? []).filter { !isAccidental($0) }.sorted { ($0.startedAt, $0.endedAt) < ($1.startedAt, $1.endedAt) }
            let saved = progress[id]
            let item = account[id]
            let isSeries = title?.isSeries ?? inferSeries(played: played, saved: saved, item: item)

            if isSeries {
                let local = seriesSignal(
                    played: played, saved: saved, item: item, title: title, weights: weights, now: now, offset: offset,
                )
                if local.hasLocal {
                    signal.hasLocalData = true
                    components.append((local.value, local.last))
                    localState = local.state
                    signal.episodesWatched = local.watched
                    signal.lastSeason = local.lastSeason
                    signal.resume = local.resume
                    signal.lastActivity = local.last
                    if local.state == .seen { signal.completedAt = local.last }
                }
            } else {
                let local = filmSignal(played: played, saved: saved, weights: weights, now: now)
                if local.hasLocal {
                    signal.hasLocalData = true
                    components.append((local.value, local.last))
                    localState = local.state
                    signal.lastActivity = local.last
                    signal.completedAt = local.completedAt
                    signal.filmFraction = local.fraction
                }
            }

            // «Досмотреть» on the site (watched on the TV or the site counts too).
            var accountState: WatchState = .none
            if let item {
                signal.inAccountList = true
                let hasProgress = item.season != nil || item.episode != nil
                if item.watched {
                    accountState = .seen
                    signal.completedAt = signal.completedAt ?? item.lastActivityAt
                } else if hasProgress {
                    accountState = .started
                }
                if !signal.hasLocalData {
                    let at = item.lastActivityAt ?? (now - weights.undatedAgeDays * day)
                    let ageDays = EngineTime.days(from: at, to: now)
                    if item.watched {
                        components.append((weights.listWatched, at))
                    } else if ageDays <= 30 {
                        components.append((weights.listRecent, at))
                    } else if ageDays > 90, isSeries, hasProgress, (item.season ?? 1) <= 1, (item.episode ?? 0) <= 2 {
                        components.append((weights.listStale, at))
                    }
                    if !item.watched, !hasProgress { signal.accountListNoProgress = true }
                }
                if !item.watched, let season = item.season, let episode = item.episode, signal.resume == nil {
                    signal.resume = EpisodeRef(season: season, episode: episode, isNext: false)
                }
                if let season = item.season { signal.lastSeason = max(signal.lastSeason ?? 0, season) }
                if let at = item.lastActivityAt { signal.lastActivity = max(signal.lastActivity ?? at, at) }
            }

            // Bookmarks: an intent; to taste only by half, unless the folder says «любимое» (or nothing for «потом»).
            let folders = (bookmarks[id] ?? []).map(\.folder)
            if !folders.isEmpty {
                signal.bookmarkFolders = folders
                signal.intent = max(signal.intent, weights.bookmarkIntent)
                if folders.contains(where: isLovedFolder) {
                    signal.inLovedFolder = true
                    components.append((weights.bookmarkLovedFolder, nil))
                } else if !folders.allSatisfy(isLaterFolder) {
                    components.append((weights.bookmarkIntent * weights.bookmarkTasteFactor, nil))
                }
            }
            if signal.accountListNoProgress { signal.intent = max(signal.intent, weights.bookmarkIntent) }
            if followed.contains(id) {
                signal.followed = true
                signal.intent = max(signal.intent, weights.followed)
                components.append((weights.followed, nil))
            }
            if let at = droppedAt[id] { components.append((weights.dropped, at)) }

            // «Это смотрел не я»: every implicit signal of the title goes, and so does what it said about watching.
            var implicitWeight: Double = 0
            if signal.notMe {
                localState = .none
                accountState = .none
                signal.resume = nil
                signal.filmFraction = nil
                signal.completedAt = nil
                signal.inLovedFolder = false
            } else {
                for component in components {
                    let ageDays = component.at.map { EngineTime.days(from: $0, to: now) } ?? 0
                    implicitWeight += Decay.implicit(component.value, ageDays: ageDays, weights: weights)
                }
                if let rating = pseudo[id] {
                    let ageDays = EngineTime.days(from: rating.createdAt, to: now)
                    implicitWeight += rating.level * Decay.halfLife(ageDays: ageDays, halfLifeDays: weights.onboardingGroupHalfLifeDays)
                }
            }

            signal.state = max(localState, accountState)
            signal.finished = signal.state == .seen
            if let rating = explicit[id] {
                signal.explicitLevel = rating.level
                let ageDays = EngineTime.days(from: rating.createdAt, to: now)
                signal.weight = EngineMath.clamp(Decay.explicit(rating.level, ageDays: ageDays, weights: weights), -2, 2)
                signal.state = .seen
                signal.completedAt = signal.completedAt ?? rating.createdAt
                signal.lastActivity = max(signal.lastActivity ?? rating.createdAt, rating.createdAt)
            } else {
                signal.weight = EngineMath.clamp(implicitWeight, -2, 2)
            }
            if kinds.contains(.seen) { signal.state = .seen }

            // Exclusions, strongest first.
            if let level = signal.explicitLevel, level <= weights.dislikedLevel + 1e-9 {
                signal.exclusion = .notForMe
            } else if kinds.contains(.hidden) {
                signal.exclusion = .hidden
            } else if kinds.contains(.dropped) {
                signal.exclusion = .dropped
            } else if signal.notSeed {
                signal.exclusion = .notSeed
            } else if kinds.contains(.notToday) {
                signal.exclusion = .notToday
            }
            // «Не учитывать «X»»: no longer part of taste at all.
            if signal.notSeed { signal.weight = 0 }
            result[id] = signal
        }
        return result
    }

    /// Feedback with an end date applies until then; «Не сегодня» without one lasts `notTodayDays`.
    static func isActive(_ feedback: Feedback, now: Double, weights: Weights) -> Bool {
        if let until = feedback.until { return until > now }
        if feedback.kind == .notToday { return feedback.createdAt + weights.notTodayDays * EngineTime.day > now }
        return true
    }

    static func isAccidental(_ session: WatchSession) -> Bool {
        guard !session.completed else { return false }
        let length = max(session.endedAt - session.startedAt, session.toPosition - session.fromPosition)
        return length < accidentalSessionSeconds
    }

    static func isLovedFolder(_ folder: String) -> Bool {
        let key = TextKey.normalized(folder)
        return ["любим", "избран", "топ", "лучш", "шедевр"].contains { key.contains($0) }
    }

    static func isLaterFolder(_ folder: String) -> Bool {
        let key = TextKey.normalized(folder)
        return ["потом", "позже", "посмотреть"].contains { key.contains($0) }
    }

    private static func inferSeries(played: [WatchSession], saved: LocalProgress?, item: AccountListItem?) -> Bool {
        if played.contains(where: { $0.season != nil || $0.episode != nil }) { return true }
        if let saved, saved.filmFraction == nil, saved.episodesStarted > 0 { return true }
        return item?.season != nil || item?.episode != nil
    }

    // MARK: Films

    struct FilmResult {
        var hasLocal = false
        var fraction: Double = 0
        var value: Double = 0
        var state: WatchState = .none
        var last: Double?
        var completedAt: Double?
    }

    /// c = position / length (a finished session counts as 1): ≥0.85 → +0.8; 0.5–0.85 → +0.3 (+0.5 over two
    /// sessions); 0.15–0.5 → 0; under 0.15 after 14 quiet days → −0.4; two separate completions add +0.5.
    static func filmSignal(played: [WatchSession], saved: LocalProgress?, weights: Weights, now: Double) -> FilmResult {
        var result = FilmResult()
        var fraction: Double = 0
        var completions: [Double] = []
        for session in played {
            result.hasLocal = true
            if session.completed {
                fraction = 1
                completions.append(session.endedAt)
            } else if session.duration > 0 {
                fraction = max(fraction, min(1, session.toPosition / session.duration))
            }
            result.last = max(result.last ?? session.endedAt, session.endedAt)
        }
        if let saved {
            result.hasLocal = true
            if let saved = saved.filmFraction { fraction = max(fraction, saved) }
            result.last = max(result.last ?? saved.updatedAt, saved.updatedAt)
        }
        guard result.hasLocal else { return result }
        result.fraction = fraction
        let quietDays = result.last.map { EngineTime.days(from: $0, to: now) } ?? .infinity
        if fraction >= 0.85 {
            result.value = weights.filmCompleted
            result.state = .seen
            result.completedAt = completions.max() ?? result.last
        } else if fraction >= 0.5 {
            result.value = played.count >= 2 ? weights.filmMostlyTwoSessions : weights.filmMostly
            result.state = .started
        } else if fraction >= 0.15 {
            result.state = .started
        } else {
            // Only real sessions (≥3 min) count as a try; a saved position alone proves nothing.
            result.value = quietDays >= 14 && !played.isEmpty ? weights.filmAbandoned : 0
            result.state = .started
        }
        var viewings = 0
        var lastCompletion = -Double.infinity
        for time in completions.sorted() where time - lastCompletion > rewatchGapSeconds {
            viewings += 1
            lastCompletion = time
        }
        if viewings >= 2 { result.value += weights.rewatch }
        return result
    }

    // MARK: Series

    struct SeriesResult {
        var hasLocal = false
        var value: Double = 0
        var state: WatchState = .none
        var last: Double?
        var watched = 0
        var lastSeason: Int?
        var resume: EpisodeRef?
    }

    /// e = episodes finished / released: ≥3 episodes → +0.5 + 0.5·min(1, e); a season finished and the next begun →
    /// +0.3; ≥3 episodes in a day → +0.2; dropped after 1–2 episodes and 30 quiet days → −0.4.
    static func seriesSignal(
        played: [WatchSession], saved: LocalProgress?, item: AccountListItem?, title: TitleFeatures?, weights: Weights,
        now: Double, offset: Double,
    ) -> SeriesResult {
        var result = SeriesResult()
        var finished = Set<String>()
        var started = Set<String>()
        var seasons = Set<Int>()
        var finishedSeasons = Set<Int>()
        var perDay: [Int: Set<String>] = [:]
        var latestFinished: (season: Int, episode: Int, at: Double)?
        for session in played {
            result.hasLocal = true
            let key = "\(session.season ?? "")|\(session.episode ?? "")"
            started.insert(key)
            perDay[EngineTime.localDay(session.startedAt, offset: offset), default: []].insert(key)
            let season = session.season.flatMap { Int($0) }
            if let season { seasons.insert(season) }
            if session.completed {
                finished.insert(key)
                if let season { finishedSeasons.insert(season) }
                if let season, let episode = session.episode.flatMap({ Int($0) }),
                   session.endedAt >= (latestFinished?.at ?? -Double.infinity)
                {
                    latestFinished = (season, episode, session.endedAt)
                }
            }
            result.last = max(result.last ?? session.endedAt, session.endedAt)
        }
        if let saved {
            result.hasLocal = true
            result.last = max(result.last ?? saved.updatedAt, saved.updatedAt)
        }
        guard result.hasLocal else { return result }

        let watched = max(saved?.episodesWatched ?? 0, finished.count)
        let startedCount = max(saved?.episodesStarted ?? 0, started.count, watched)
        let released = title?.releasedEpisodes ?? item?.episodesLeft.map { watched + $0 }
        let progress: Double = if let released {
            released > 0 ? min(1, Double(watched) / Double(released)) : 0
        } else {
            min(1, Double(watched) / max(1, weights.typicalSeasonEpisodes))
        }
        let fully = released.map { $0 > 0 && watched >= $0 } ?? false
        let quietDays = result.last.map { EngineTime.days(from: $0, to: now) } ?? .infinity

        if watched >= 3 || fully {
            result.value += weights.seriesBase + weights.seriesProgressBonus * progress
        }
        let maxSeason = seasons.max() ?? 0
        let nextSeasonBegun = seasons.count >= 2 && finishedSeasons.contains { $0 < maxSeason }
        if nextSeasonBegun || ((saved?.lastSeason ?? 0) >= 2 && watched >= 3) {
            result.value += weights.seriesNextSeason
        }
        if perDay.values.contains(where: { $0.count >= 3 }) { result.value += weights.seriesBinge }
        if !fully, watched < 3, startedCount >= 1, startedCount <= 2, quietDays >= 30 {
            result.value = weights.seriesAbandoned
        }
        result.state = fully ? .seen : .started
        result.watched = watched
        result.lastSeason = [saved?.lastSeason, seasons.max()].compactMap(\.self).max()
        if let latestFinished {
            result.resume = EpisodeRef(season: latestFinished.season, episode: latestFinished.episode + 1, isNext: true)
        }
        return result
    }
}

extension WatchState: Comparable {
    private var order: Int {
        switch self {
        case .none: 0
        case .started: 1
        case .seen: 2
        }
    }

    static func < (lhs: WatchState, rhs: WatchState) -> Bool { lhs.order < rhs.order }
}
