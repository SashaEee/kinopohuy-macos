import Foundation
import GRDB
import RecommenderCore

/// Everything the user tells the recommender, by acting or on purpose: ratings, «Скрыть» / «Не сегодня» and the
/// rest, hand-made taste overrides, what was shown where, the playing sessions, the account's lists as last seen, and
/// the cached Home. All of it stays in this Mac's database.
struct SignalStore: Sendable {
    let database: any DatabaseWriter

    private static let day: Double = 86400
    /// Impressions are kept half a year (for fatigue and, later, offline evaluation); the engine sees the last month.
    private static let impressionRetentionDays: Double = 180
    private static let impressionWindowDays: Double = 30
    /// The same title on the same surface within an hour is one impression (Home redraws often).
    private static let impressionDedupSeconds: Double = 3600
    /// A followed series not seen in the feed for three months is no longer counted as followed.
    private static let followedMemoryDays: Double = 90
    /// Sessions the engine reads, newest first.
    private static let sessionLimit = 5000

    // MARK: Ratings

    func rate(_ titleId: String, level: Double, source: ExplicitRating.Source, now: Date = .now) async {
        _ = try? await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO user_rating (titleId, level, source, createdAt, sentToSite) VALUES (?, ?, ?, ?, 0)
                ON CONFLICT(titleId) DO UPDATE SET level = excluded.level, source = excluded.source, createdAt = excluded.createdAt
                """,
                arguments: [titleId, level, source.rawValue, now.timeIntervalSince1970],
            )
        }
    }

    func clearRating(_ titleId: String) async {
        _ = try? await database.write { db in
            try db.execute(sql: "DELETE FROM user_rating WHERE titleId = ?", arguments: [titleId])
        }
    }

    func rating(_ titleId: String) async -> Double? {
        try? await database.read { db in
            try Double.fetchOne(db, sql: "SELECT level FROM user_rating WHERE titleId = ?", arguments: [titleId])
        }
    }

    // MARK: Feedback

    func addFeedback(_ titleId: String, kind: FeedbackKind, until: Double?, now: Date = .now) async {
        _ = try? await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO title_feedback (titleId, kind, createdAt, until) VALUES (?, ?, ?, ?)
                ON CONFLICT(titleId, kind) DO UPDATE SET createdAt = excluded.createdAt, until = excluded.until
                """,
                arguments: [titleId, kind.rawValue, now.timeIntervalSince1970, until],
            )
        }
    }

    func removeFeedback(_ titleId: String, kind: FeedbackKind) async {
        _ = try? await database.write { db in
            try db.execute(sql: "DELETE FROM title_feedback WHERE titleId = ? AND kind = ?", arguments: [titleId, kind.rawValue])
        }
    }

    func activeFeedback(_ titleId: String, now: Date = .now) async -> Set<FeedbackKind> {
        let kinds: [String] = (try? await database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT kind FROM title_feedback WHERE titleId = ? AND (until IS NULL OR until > ?)",
                arguments: [titleId, now.timeIntervalSince1970],
            )
        }) ?? []
        return Set(kinds.compactMap(FeedbackKind.init(rawValue:)))
    }

    // MARK: Overrides

    func setOverride(_ override: TasteOverride) async {
        _ = try? await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO taste_override (feature, mode, until) VALUES (?, ?, ?)
                ON CONFLICT(feature) DO UPDATE SET mode = excluded.mode, until = excluded.until
                """,
                arguments: [override.feature.description, override.mode.rawValue, override.until],
            )
        }
    }

    func clearOverride(_ feature: FeatureKey) async {
        _ = try? await database.write { db in
            try db.execute(sql: "DELETE FROM taste_override WHERE feature = ?", arguments: [feature.description])
        }
    }

    /// The overrides in force.
    func overrides(now: Date = .now) async -> [TasteOverride] {
        (try? await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT feature, mode, until FROM taste_override WHERE until IS NULL OR until > ?",
                arguments: [now.timeIntervalSince1970],
            ).compactMap { row -> TasteOverride? in
                let feature: String = row["feature"]
                let mode: String = row["mode"]
                guard let key = Self.featureKey(feature), let mode = TasteOverride.Mode(rawValue: mode) else { return nil }
                return TasteOverride(feature: key, mode: mode, until: row["until"])
            }
        }) ?? []
    }

    // MARK: Impressions

    func recordImpressions(_ titleIds: [String], surface: String, now: Date = .now) async {
        let ids = Array(NSOrderedSet(array: titleIds).compactMap { $0 as? String })
        guard !ids.isEmpty else { return }
        let at = now.timeIntervalSince1970
        _ = try? await database.write { db in
            for id in ids {
                try db.execute(
                    sql: """
                    INSERT INTO rec_impression (titleId, surface, shownAt, opened)
                    SELECT ?, ?, ?, 0 WHERE NOT EXISTS (
                        SELECT 1 FROM rec_impression WHERE titleId = ? AND surface = ? AND shownAt > ?
                    )
                    """,
                    arguments: [id, surface, at, id, surface, at - Self.impressionDedupSeconds],
                )
            }
        }
    }

    /// The title was opened: its recent impressions count as clicked (no fatigue for them).
    func markOpened(_ titleId: String, now: Date = .now) async {
        _ = try? await database.write { db in
            try db.execute(
                sql: "UPDATE rec_impression SET opened = 1 WHERE titleId = ? AND shownAt >= ?",
                arguments: [titleId, now.timeIntervalSince1970 - 14 * Self.day],
            )
        }
    }

    /// Drops impressions older than half a year and service actions that ran out.
    func prune(now: Date = .now) async {
        let at = now.timeIntervalSince1970
        _ = try? await database.write { db in
            try db.execute(sql: "DELETE FROM rec_impression WHERE shownAt < ?", arguments: [at - Self.impressionRetentionDays * Self.day])
            try db.execute(sql: "DELETE FROM title_feedback WHERE until IS NOT NULL AND until < ?", arguments: [at])
            try db.execute(sql: "DELETE FROM taste_override WHERE until IS NOT NULL AND until < ?", arguments: [at])
        }
    }

    // MARK: Sessions

    /// One playing session; the voice-over is the one this Mac's history has for the title.
    func logSession(_ session: WatchSession) async {
        // Under 3 s it's no session at all (a reload, a voice-over switch).
        guard session.endedAt - session.startedAt >= 3 else { return }
        _ = try? await database.write { db in
            let acting = try String.fetchOne(db, sql: "SELECT acting FROM watch_history WHERE id = ?", arguments: [session.titleId])
            try db.execute(
                sql: """
                INSERT INTO watch_event (titleId, acting, season, episode, startedAt, endedAt, fromPos, toPos, duration, completed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    session.titleId, acting, session.season, session.episode, session.startedAt, session.endedAt,
                    session.fromPosition, session.toPosition, session.duration, session.completed ? 1 : 0,
                ],
            )
        }
    }

    // MARK: Account

    /// «Досмотреть» as the site shows it now (replaces the last snapshot).
    func replaceAccountList(_ items: [AccountListItem], now: Date = .now) async {
        _ = try? await database.write { db in
            try db.execute(sql: "DELETE FROM account_list")
            var seen: Set<String> = []
            for (position, item) in items.enumerated() where seen.insert(item.titleId).inserted {
                try db.execute(
                    sql: """
                    INSERT INTO account_list (titleId, position, watched, lastActivityAt, season, episode, episodesLeft, capturedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        item.titleId, position, item.watched ? 1 : 0, item.lastActivityAt, item.season, item.episode,
                        item.episodesLeft, now.timeIntervalSince1970,
                    ],
                )
            }
        }
    }

    /// Titles seen in a bookmark folder.
    func upsertBookmarks(_ titleIds: [String], folder: String, now: Date = .now) async {
        guard !titleIds.isEmpty, !folder.isEmpty else { return }
        _ = try? await database.write { db in
            for id in titleIds {
                try db.execute(
                    sql: """
                    INSERT INTO account_bookmark (titleId, folder, updatedAt) VALUES (?, ?, ?)
                    ON CONFLICT(titleId, folder) DO UPDATE SET updatedAt = excluded.updatedAt
                    """,
                    arguments: [id, folder, now.timeIntervalSince1970],
                )
            }
        }
    }

    /// Series the feed of new episodes marks as followed.
    func upsertFollowed(_ titleIds: [String], now: Date = .now) async {
        guard !titleIds.isEmpty else { return }
        _ = try? await database.write { db in
            for id in Set(titleIds) {
                try db.execute(
                    sql: "INSERT INTO account_followed (titleId, updatedAt) VALUES (?, ?) ON CONFLICT(titleId) DO UPDATE SET updatedAt = excluded.updatedAt",
                    arguments: [id, now.timeIntervalSince1970],
                )
            }
        }
    }

    // MARK: Cache and state

    struct CachedPayload: Sendable {
        var payload: Data
        var profileHash: String
        var builtAt: Double
    }

    func readCache(_ surface: String) async -> CachedPayload? {
        try? await database.read { db in
            try Row.fetchOne(db, sql: "SELECT payload, profileHash, builtAt FROM rec_cache WHERE surface = ?", arguments: [surface]).map { row in
                let payload: String = row["payload"]
                return CachedPayload(payload: Data(payload.utf8), profileHash: row["profileHash"], builtAt: row["builtAt"])
            }
        }
    }

    func writeCache(_ surface: String, _ cached: CachedPayload) async {
        _ = try? await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO rec_cache (surface, payload, profileHash, builtAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(surface) DO UPDATE SET payload = excluded.payload, profileHash = excluded.profileHash, builtAt = excluded.builtAt
                """,
                arguments: [surface, String(decoding: cached.payload, as: UTF8.self), cached.profileHash, cached.builtAt],
            )
        }
    }

    func state(_ key: String) async -> String? {
        try? await database.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM crawl_state WHERE key = ?", arguments: [key])
        }
    }

    func setState(_ key: String, _ value: String, now: Date = .now) async {
        _ = try? await database.write { db in
            try db.execute(
                sql: "INSERT INTO crawl_state (key, value, updatedAt) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
                arguments: [key, value, now.timeIntervalSince1970],
            )
        }
    }

    // MARK: Assembling

    /// Everything about the user for the engine. After «Сбросить вкус» what this Mac and the account knew from before
    /// stops shaping taste: titles watched to the end stay out of the recommendations (as «Уже смотрел»), the rest is
    /// forgotten until it's played again; ratings, feedback, overrides, bookmarks and followed series stay.
    func signals(signedIn: Bool, now: Date = .now) async -> UserSignals {
        let at = now.timeIntervalSince1970
        return (try? await database.read { db in
            let resetAt = try String.fetchOne(db, sql: "SELECT value FROM crawl_state WHERE key = ?", arguments: [StateKey.tasteResetAt]).flatMap(Double.init) ?? 0

            let sessions = try Self.sessions(db: db)
            let progress = try Self.progress(db: db, sessions: sessions, now: at)

            var accountList: [AccountListItem] = try Row.fetchAll(
                db,
                sql: "SELECT titleId, watched, lastActivityAt, season, episode, episodesLeft FROM account_list ORDER BY position",
            ).map { row in
                let watched: Int = row["watched"]
                return AccountListItem(
                    titleId: row["titleId"], watched: watched != 0, lastActivityAt: row["lastActivityAt"],
                    season: row["season"], episode: row["episode"], episodesLeft: row["episodesLeft"],
                )
            }

            let bookmarks = try Row.fetchAll(db, sql: "SELECT titleId, folder FROM account_bookmark ORDER BY updatedAt DESC").map { row in
                BookmarkItem(titleId: row["titleId"], folder: row["folder"])
            }
            let followed = try String.fetchAll(
                db,
                sql: "SELECT titleId FROM account_followed WHERE updatedAt >= ? ORDER BY updatedAt DESC",
                arguments: [at - Self.followedMemoryDays * Self.day],
            )
            let ratings = try Row.fetchAll(db, sql: "SELECT titleId, level, source, createdAt FROM user_rating").map { row in
                let source: String = row["source"]
                return ExplicitRating(titleId: row["titleId"], level: row["level"], source: ExplicitRating.Source(rawValue: source) ?? .app, createdAt: row["createdAt"])
            }
            var feedback: [Feedback] = try Row.fetchAll(
                db,
                sql: "SELECT titleId, kind, createdAt, until FROM title_feedback WHERE until IS NULL OR until > ?",
                arguments: [at],
            ).compactMap { row in
                let kind: String = row["kind"]
                guard let kind = FeedbackKind(rawValue: kind) else { return nil }
                return Feedback(titleId: row["titleId"], kind: kind, createdAt: row["createdAt"], until: row["until"])
            }
            let overrides: [TasteOverride] = try Row.fetchAll(
                db,
                sql: "SELECT feature, mode, until FROM taste_override WHERE until IS NULL OR until > ?",
                arguments: [at],
            ).compactMap { row in
                let feature: String = row["feature"]
                let mode: String = row["mode"]
                guard let key = Self.featureKey(feature), let mode = TasteOverride.Mode(rawValue: mode) else { return nil }
                return TasteOverride(feature: key, mode: mode, until: row["until"])
            }
            let impressions = try Row.fetchAll(
                db,
                sql: "SELECT titleId, surface, shownAt, opened FROM rec_impression WHERE shownAt >= ? ORDER BY shownAt",
                arguments: [at - Self.impressionWindowDays * Self.day],
            ).map { row in
                let opened: Int = row["opened"]
                return Impression(titleId: row["titleId"], surface: row["surface"], shownAt: row["shownAt"], opened: opened != 0)
            }

            var progressAfterReset = progress
            if resetAt > 0 {
                var seen: Set<String> = Set(feedback.filter { $0.kind == .seen }.map(\.titleId))
                for item in progress where item.updatedAt < resetAt && (item.filmFraction ?? 0) >= 0.85 && seen.insert(item.titleId).inserted {
                    feedback.append(Feedback(titleId: item.titleId, kind: .seen, createdAt: resetAt))
                }
                for item in accountList where (item.lastActivityAt ?? 0) < resetAt && item.watched && seen.insert(item.titleId).inserted {
                    feedback.append(Feedback(titleId: item.titleId, kind: .seen, createdAt: resetAt))
                }
                progressAfterReset = progress.filter { $0.updatedAt >= resetAt }
                accountList = accountList.filter { ($0.lastActivityAt ?? 0) >= resetAt }
            }

            return UserSignals(
                sessions: sessions.filter { $0.endedAt >= resetAt },
                progress: progressAfterReset,
                accountList: accountList,
                bookmarks: bookmarks,
                followed: followed,
                ratings: ratings,
                feedback: feedback,
                overrides: overrides,
                impressions: impressions,
                signedIn: signedIn,
            )
        }) ?? UserSignals(signedIn: signedIn)
    }

    /// The titles that make the user's taste, most recent first: this Mac's history, «Досмотреть», titles rated
    /// up, bookmarks. The background reader reads their pages first.
    func anchorIds(now: Date = .now) async -> [String] {
        (try? await database.read { db in
            var ids: [String] = []
            ids += try String.fetchAll(db, sql: "SELECT id FROM watch_history ORDER BY updatedAt DESC")
            ids += try String.fetchAll(db, sql: "SELECT titleId FROM watch_event GROUP BY titleId ORDER BY MAX(endedAt) DESC")
            ids += try String.fetchAll(db, sql: "SELECT titleId FROM account_list ORDER BY position")
            ids += try String.fetchAll(db, sql: "SELECT titleId FROM user_rating WHERE level > 0 ORDER BY createdAt DESC")
            ids += try String.fetchAll(db, sql: "SELECT titleId FROM account_bookmark ORDER BY updatedAt DESC")
            ids += try String.fetchAll(db, sql: "SELECT titleId FROM account_followed ORDER BY updatedAt DESC")
            ids += try String.fetchAll(db, sql: "SELECT DISTINCT id FROM player_positions")
            var seen: Set<String> = []
            return ids.filter { seen.insert($0).inserted }
        }) ?? []
    }

    // MARK: Reset

    /// «Сбросить вкус»: the session log and the impressions go, and what was known before now stops shaping taste
    /// (see `signals`). Ratings, feedback and overrides stay.
    func resetTaste(now: Date = .now) async {
        _ = try? await database.write { db in
            try db.execute(sql: "DELETE FROM watch_event")
            try db.execute(sql: "DELETE FROM rec_impression")
            try db.execute(sql: "DELETE FROM rec_cache")
            try db.execute(
                sql: "INSERT INTO crawl_state (key, value, updatedAt) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
                arguments: [StateKey.tasteResetAt, String(now.timeIntervalSince1970), now.timeIntervalSince1970],
            )
        }
    }

    /// «Очистить все данные рекомендаций»: everything about the user goes; the catalogue of titles, the cached pages
    /// and today's count of background reads stay (the count keeps the daily limit honest).
    func clearAll() async {
        _ = try? await database.write { db in
            for table in ["user_rating", "title_feedback", "taste_override", "rec_impression", "rec_cache", "watch_event", "account_list", "account_bookmark", "account_followed"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            try db.execute(sql: "DELETE FROM crawl_state WHERE key NOT IN (?, ?, ?, ?)", arguments: [StateKey.crawlDay, StateKey.crawlCount, StateKey.pausedUntil, StateKey.profileSalt])
        }
    }

    // MARK: Rows

    private static func sessions(db: Database) throws -> [WatchSession] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT titleId, season, episode, startedAt, endedAt, fromPos, toPos, duration, completed
            FROM watch_event ORDER BY endedAt DESC LIMIT \(sessionLimit)
            """,
        )
        .reversed()
        .map { row in
            let completed: Int = row["completed"]
            return WatchSession(
                titleId: row["titleId"], season: row["season"], episode: row["episode"], startedAt: row["startedAt"],
                endedAt: row["endedAt"], fromPosition: row["fromPos"], toPosition: row["toPos"], duration: row["duration"],
                completed: completed != 0,
            )
        }
    }

    /// What the player's saved places say per title: how far into a film (the watched mark counts as the end), or
    /// how many episodes were watched to the end and started, and the furthest season.
    private static func progress(db: Database, sessions: [WatchSession], now: Double) throws -> [LocalProgress] {
        struct Place {
            var season: String
            var episode: String
            var position: Double
            var duration: Double?
        }
        var places: [String: [Place]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, season, episode, position, duration FROM player_positions") {
            let id: String = row["id"]
            places[id, default: []].append(Place(season: row["season"], episode: row["episode"], position: row["position"], duration: row["duration"]))
        }

        var history: [String: Place] = [:]
        var updated: [String: Double] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, season, episode, position, duration, updatedAt FROM watch_history") {
            let id: String = row["id"]
            history[id] = Place(season: row["season"], episode: row["episode"], position: row["position"], duration: row["duration"])
            let at: Double = row["updatedAt"]
            updated[id] = at
        }
        for session in sessions {
            updated[session.titleId] = max(updated[session.titleId] ?? 0, session.endedAt)
        }

        // A film saved before lengths were kept: its page's length.
        let ids = Set(places.keys).union(history.keys)
        var pageMinutes: [String: Double] = [:]
        let missing = ids.filter { id in
            let film = places[id]?.first { $0.season.isEmpty && $0.episode.isEmpty }
            return film != nil && (film?.duration ?? 0) <= 0 && (history[id]?.duration ?? 0) <= 0
        }
        for chunk in Array(missing).recChunks(of: 500) where !chunk.isEmpty {
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, json_extract(features, '$.durationMin') AS minutes FROM title_meta WHERE id IN (\(TitleStore.placeholders(chunk.count)))",
                arguments: StatementArguments(chunk),
            )
            for row in rows {
                let id: String = row["id"]
                if let minutes: Double = row["minutes"], minutes > 0 { pageMinutes[id] = minutes * 60 }
            }
        }

        let longAgo = now - 365 * day
        var result: [LocalProgress] = []
        for id in ids.sorted() {
            let rows = places[id] ?? []
            let episodes = rows.filter { !$0.season.isEmpty || !$0.episode.isEmpty }
            let lastPlayed = history[id]
            let isSeries = !episodes.isEmpty || !(lastPlayed?.season.isEmpty ?? true) || !(lastPlayed?.episode.isEmpty ?? true)
            let updatedAt = updated[id] ?? longAgo

            if isSeries {
                var watched: Set<String> = []
                var started: Set<String> = []
                for place in episodes {
                    let key = "\(Int(place.season).map(String.init) ?? place.season)-\(Int(place.episode).map(String.init) ?? place.episode)"
                    if place.position >= PlayerFeature.watchedMark {
                        watched.insert(key)
                        started.insert(key)
                    } else if place.position >= 30 {
                        started.insert(key)
                    }
                }
                let lastSeason = (episodes.compactMap { Int($0.season) } + [lastPlayed.flatMap { Int($0.season) }].compactMap { $0 }).max()
                guard !started.isEmpty || lastPlayed != nil else { continue }
                result.append(LocalProgress(
                    titleId: id, filmFraction: nil, episodesWatched: watched.count, episodesStarted: max(started.count, lastPlayed == nil ? 0 : 1),
                    lastSeason: lastSeason, updatedAt: updatedAt,
                ))
            } else {
                let film = rows.first { $0.season.isEmpty && $0.episode.isEmpty } ?? lastPlayed
                guard let film else { continue }
                let fraction: Double?
                if film.position >= PlayerFeature.watchedMark {
                    fraction = 1
                } else if let duration = [film.duration, lastPlayed?.duration, pageMinutes[id]].compactMap({ $0 }).first(where: { $0 > 0 }) {
                    fraction = min(1, max(0, film.position / duration))
                } else {
                    fraction = nil
                }
                guard let fraction else { continue }
                result.append(LocalProgress(titleId: id, filmFraction: fraction, episodesWatched: 0, episodesStarted: 0, lastSeason: nil, updatedAt: updatedAt))
            }
        }
        return result
    }

    /// «genre:Драмы» → the feature.
    static func featureKey(_ text: String) -> FeatureKey? {
        guard let colon = text.firstIndex(of: ":"), let group = FeatureKey.Group(rawValue: String(text[..<colon])) else { return nil }
        let value = String(text[text.index(after: colon)...])
        return value.isEmpty ? nil : FeatureKey(group, value)
    }
}

/// The keys of `crawl_state`.
enum StateKey {
    /// The day (yyyy-MM-dd) the background reader's counter is for, and the count.
    static let crawlDay = "crawl.day"
    static let crawlCount = "crawl.count"
    /// The background reader waits until then (after repeated 403s).
    static let pausedUntil = "crawl.pausedUntil"
    /// When the weekly pool crawl last ran.
    static let poolCrawledAt = "pool.crawledAt"
    /// Titles whose pages failed to read, with when (JSON), so they aren't retried every minute.
    static let failedPages = "crawl.failed"
    /// «Сбросить вкус»: implicit signals before this moment don't count.
    static let tasteResetAt = "taste.resetAt"
    /// A random salt for the day's seed, so two Macs don't get the same «случайность».
    static let profileSalt = "profile.salt"
}
