import Foundation

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
