import Foundation
import GRDB

/// Title pages kept whole for a while, so the background reader doesn't read again a page the user (or the reader)
/// just saw. How long one stays depends on what's in it (`TitleFreshness`): a running series' schedule a day, a new
/// title three days, everything else two weeks. The newest 400 are kept.
struct DetailsCacheStore: Sendable {
    let database: any DatabaseWriter

    static let capacity = 400

    /// The page, if it's still fresh enough to use instead of reading the site.
    func fresh(_ path: String, now: Date = .now) async -> MovieDetailed? {
        let row: (payload: String, fetchedAt: Double)? = try? await database.read { db in
            try Row.fetchOne(db, sql: "SELECT payload, fetchedAt FROM details_cache WHERE path = ?", arguments: [path]).map { row in
                (row["payload"], row["fetchedAt"])
            }
        }
        guard let row, let details = try? JSONDecoder().decode(MovieDetailed.self, from: Data(row.payload.utf8)) else { return nil }
        let lifetime = TitleMapper.features(from: details, now: now).map { TitleFreshness.lifetime(of: $0, now: now) } ?? TitleFreshness.day
        return now.timeIntervalSince1970 - row.fetchedAt <= lifetime ? details : nil
    }

    func store(_ details: MovieDetailed, now: Date = .now) async {
        guard let data = try? JSONEncoder().encode(details) else { return }
        let payload = String(decoding: data, as: UTF8.self)
        _ = try? await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO details_cache (path, payload, fetchedAt) VALUES (?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET payload = excluded.payload, fetchedAt = excluded.fetchedAt
                """,
                arguments: [details.movieId, payload, now.timeIntervalSince1970],
            )
            try db.execute(
                sql: "DELETE FROM details_cache WHERE path NOT IN (SELECT path FROM details_cache ORDER BY fetchedAt DESC LIMIT ?)",
                arguments: [Self.capacity],
            )
        }
    }

    func clear() async {
        _ = try? await database.write { db in try db.execute(sql: "DELETE FROM details_cache") }
    }
}

/// The title-page repository with a cache in front of `getMovieDetails`. The background reader uses it (with its
/// own way of reading the site in `fetchDetails`); the title page itself keeps reading fresh, and what it reads goes
/// into the cache too. Everything else is the wrapped repository's.
struct CachingMovieDetailsRepository: MovieDetailsRepository {
    let base: any MovieDetailsRepository
    let cache: DetailsCacheStore
    /// How a page is read when the cache has none fresh (the wrapped repository's, unless given).
    let fetchDetails: (@Sendable (String) async throws -> MovieDetailed)?

    init(base: any MovieDetailsRepository, cache: DetailsCacheStore, fetchDetails: (@Sendable (String) async throws -> MovieDetailed)? = nil) {
        self.base = base
        self.cache = cache
        self.fetchDetails = fetchDetails
    }

    func getMovieDetails(movieId: String) async throws -> MovieDetailed {
        if let cached = await cache.fresh(movieId) {
            return cached
        }
        let details = if let fetchDetails {
            try await fetchDetails(movieId)
        } else {
            try await base.getMovieDetails(movieId: movieId)
        }
        await cache.store(details)
        return details
    }

    func getMovieBookmarks(movieId: String) async throws -> [Bookmark] {
        try await base.getMovieBookmarks(movieId: movieId)
    }

    func getMovieVideo(voiceActing: MovieVoiceActing, season: MovieSeason?, episode: MovieEpisode?, favs: String) async throws -> MovieVideo {
        try await base.getMovieVideo(voiceActing: voiceActing, season: season, episode: episode, favs: favs)
    }

    func getMovieThumbnails(path: String) async throws -> WebVTT {
        try await base.getMovieThumbnails(path: path)
    }

    func getSeriesSeasons(movieId: String, voiceActing: MovieVoiceActing, favs: String) async throws -> [MovieSeason] {
        try await base.getSeriesSeasons(movieId: movieId, voiceActing: voiceActing, favs: favs)
    }

    func getMovieTrailerId(movieId: String) async throws -> String {
        try await base.getMovieTrailerId(movieId: movieId)
    }

    func getCommentsPage(movieId: String, page: Int) async throws -> [Comment] {
        try await base.getCommentsPage(movieId: movieId, page: page)
    }

    func getComment(movieId: String, commentId: String) async throws -> Comment {
        try await base.getComment(movieId: movieId, commentId: commentId)
    }

    func toggleLikeComment(id: String) async throws -> (Int, Bool) {
        try await base.toggleLikeComment(id: id)
    }

    func reportComment(id: String, issue: Int, text: String) async throws -> Bool {
        try await base.reportComment(id: id, issue: issue, text: text)
    }

    func deleteComment(id: String, hash: String) async throws -> (Bool, String?) {
        try await base.deleteComment(id: id, hash: hash)
    }

    func sendComment(id: String?, postId: String, name: String?, text: String, adb: String?, type: String?) async throws -> SendCommentResult {
        try await base.sendComment(id: id, postId: postId, name: name, text: text, adb: adb, type: type)
    }

    func getLikes(id: String) async throws -> [Like] {
        try await base.getLikes(id: id)
    }

    func rate(id: String, rating: Int) async throws -> (Float?, String?)? {
        try await base.rate(id: id, rating: rating)
    }
}
