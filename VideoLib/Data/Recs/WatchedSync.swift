import Dependencies
import Foundation

/// «Оценил фильм — значит посмотрел»: a film rated (or marked «Уже смотрел») that still waits unwatched in the site's
/// «Досмотреть» is marked watched there too, so the site, the TV and «Продолжить просмотр» all agree. A series isn't:
/// a rating there is «so far». Taking the rating back in the same session takes the mark back.
actor WatchedSync {
    /// The site's list as last read, by title id.
    private var items: [String: MovieWatchLater] = [:]
    /// What this session marked watched (and may unmark).
    private var marked: Set<String> = []

    func update(_ list: [MovieWatchLater]) {
        var byId: [String: MovieWatchLater] = [:]
        for item in list {
            guard let id = item.watchLaterId.id, byId[id] == nil else { continue }
            byId[id] = item
        }
        items = byId
    }

    /// Marks the film watched on the site when it's in the list unwatched; true when it did.
    @discardableResult
    func filmDone(_ titleId: String) async -> Bool {
        guard var item = items[titleId], !item.watched, !item.isSeries else { return false }
        @Dependency(\.switchWatchedItemUseCase) var switchWatched
        guard (try? await switchWatched(item: item)) == true else { return false }
        item.watched = true
        items[titleId] = item
        marked.insert(titleId)
        return true
    }

    /// Puts back a mark this session made (the rating or «Уже смотрел» was taken back).
    func undo(_ titleId: String) async {
        guard marked.contains(titleId), var item = items[titleId], item.watched else { return }
        @Dependency(\.switchWatchedItemUseCase) var switchWatched
        guard (try? await switchWatched(item: item)) == true else { return }
        item.watched = false
        items[titleId] = item
        marked.remove(titleId)
    }
}
