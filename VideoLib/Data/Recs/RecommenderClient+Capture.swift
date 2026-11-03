import Foundation
import RecommenderCore

/// The capture calls features make, in the app's own terms, so the reducers that load lists, people and the player
/// don't need RecommenderCore's types (whose `Picker` would clash with SwiftUI's).
extension RecommenderClient {
    /// A ranked list's page: its cards in their places (`firstPlace` is the first card's, 1 on the first page).
    func captureList(_ cards: [MovieSimple], list: MovieList, title: String?, firstPlace: Int) async {
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? list.name
        await captureCards(cards, BoardRef(id: list.listId, kind: .list, name: name, rank: max(1, firstPlace)))
    }

    /// A collection's page: its cards as members (a collection has no order).
    func captureCollection(_ cards: [MovieSimple], collection: MoviesCollection) async {
        await captureCards(cards, BoardRef(id: collection.collectionId, kind: .collection, name: collection.name, size: collection.count))
    }

    /// A person's page: what they directed and played in become their filmography boards; other roles are just
    /// cards for the pool.
    func captureFilmography(_ details: PersonDetailed, personPath: String, name: String) async {
        let id = RecParsing.personKey(fromPath: personPath) ?? personPath
        let shown = details.nameRu.isEmpty ? name : details.nameRu
        await captureCards(details.directorMovies ?? [], BoardRef(id: id, kind: .director, name: shown))
        await captureCards((details.actorMovies ?? []) + (details.actressMovies ?? []), BoardRef(id: id, kind: .actor, name: shown))
        let others = [details.producerMovies, details.screenwriterMovies, details.operatorMovies, details.editorMovies, details.artistMovies, details.composerMovies]
            .compactMap { $0 }
            .flatMap { $0 }
        await captureCards(others, nil)
    }

    /// A stretch of playback, as the player knows it (`titleId` is the title's number on the site).
    func logPlayback(
        titleId: String, season: String?, episode: String?, startedAt: Double, endedAt: Double, from: Double, to: Double,
        duration: Double, completed: Bool,
    ) async {
        await logSession(WatchSession(
            titleId: titleId, season: season, episode: episode, startedAt: startedAt, endedAt: endedAt,
            fromPosition: from, toPosition: to, duration: duration, completed: completed,
        ))
    }
}
