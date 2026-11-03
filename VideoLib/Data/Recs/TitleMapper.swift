import Foundation
import RecommenderCore

/// One title's place in a board (a ranked list, a collection, a franchise, a person's filmography): the edges of the
/// site's graph, stored row by row in `board_member`.
struct BoardMember: Hashable, Sendable {
    var board: BoardRef
    var titleId: String
}

/// Turns what the app reads from the site (a title's page, a list card, a «Досмотреть» row) into the recommender's
/// `TitleFeatures`. A page fills everything it shows; a card only kind, year, country, primary genre and its rating
/// badge, and a card never overwrites what a page said.
enum TitleMapper {
    /// How a genre's slug in a path («drama») reads as the site's genre name («Драмы»), learned from pages and cards.
    typealias GenreNames = @Sendable (String) -> String?

    // MARK: Page

    static func features(from details: MovieDetailed, now: Date = .now) -> TitleFeatures? {
        guard let id = RecParsing.titleId(fromPath: details.movieId) else { return nil }

        let kind = RecParsing.kind(fromPath: details.movieId)
        let schedule = RecParsing.schedule(
            (details.schedule ?? []).flatMap(\.items).map { ($0.title, $0.releaseDate) },
            now: now,
        )
        let releasedAt = RecParsing.date(details.releaseDate, now: now) ?? schedule?.firstEpisodeAt
        let isSeries = details.series != nil || schedule != nil || kind == .series || kind == .show

        let franchise = franchiseParts(details, titleId: id)
        let franchiseId = franchise.sorted { $0.position < $1.position }.first { $0.titleId != nil }?.titleId

        var voiceOvers = unique((details.voiceActing ?? []).map(\.name))
        if voiceOvers.isEmpty { voiceOvers = unique((details.voiceActingRating ?? []).map(\.name)) }

        return TitleFeatures(
            id: id,
            path: details.movieId,
            level: .page,
            kind: kind,
            name: details.nameRussian.trimmingCharacters(in: .whitespacesAndNewlines),
            originalName: nonEmpty(details.nameOriginal),
            year: RecParsing.year(details.year) ?? RecParsing.year(details.releaseDate) ?? schedule?.firstEpisodeAt.map { Calendar.current.component(.year, from: $0) },
            genres: unique((details.genres ?? []).map(\.name)),
            countries: unique((details.countries ?? []).map(\.name)),
            durationMin: details.duration.flatMap { $0 > 0 ? $0 : nil },
            age: RecParsing.age(details.ageRestriction),
            directors: people(details.producer ?? [], limit: 6),
            actors: people(details.actors ?? [], limit: 8),
            kpId: RecParsing.kinopoiskId(fromLink: details.kpRating?.link),
            imdbId: RecParsing.imdbId(fromLink: details.imdbRating?.link),
            kpRating: details.kpRating.flatMap { $0.value > 0 ? Double($0.value) : nil },
            kpVotes: details.kpRating.flatMap { RecParsing.count($0.votesCount) },
            imdbRating: details.imdbRating.flatMap { $0.value > 0 ? Double($0.value) : nil },
            imdbVotes: details.imdbRating.flatMap { RecParsing.count($0.votesCount) },
            siteRating: details.rating.flatMap { $0 > 0 ? Double($0) : nil },
            siteVotes: RecParsing.count(details.votes),
            boards: boards(details),
            franchiseId: franchiseId,
            franchise: franchise,
            watchAlso: unique(details.watchAlsoMovies.compactMap { RecParsing.titleId(fromPath: $0.movieId) }.filter { $0 != id }),
            isSeries: isSeries,
            releasedEpisodes: schedule?.released,
            seasons: schedule?.seasons,
            lastEpisodeAt: schedule?.lastEpisodeAt?.timeIntervalSince1970,
            releasedAt: releasedAt?.timeIntervalSince1970,
            comingSoon: details.comingSoon,
            available: details.available,
            voiceOvers: voiceOvers,
            poster: nonEmpty(details.poster) ?? nonEmpty(details.hposter),
            synopsis: synopsis(details.description),
            fetchedAt: now.timeIntervalSince1970,
        )
    }

    /// The lists (with the title's place) and collections on its page.
    private static func boards(_ details: MovieDetailed) -> [BoardRef] {
        var boards: [BoardRef] = []
        var seen: Set<String> = []
        for list in details.lists ?? [] where !list.listId.isEmpty {
            let board = BoardRef(id: list.listId, kind: .list, name: list.name, rank: list.moviePosition)
            if seen.insert(board.key).inserted { boards.append(board) }
        }
        for collection in details.collections ?? [] where !collection.collectionId.isEmpty {
            let board = BoardRef(id: collection.collectionId, kind: .collection, name: collection.name, size: collection.count)
            if seen.insert(board.key).inserted { boards.append(board) }
        }
        return boards
    }

    /// The franchise as its page lists it; the part being shown links nowhere, so it gets this title's id.
    private static func franchiseParts(_ details: MovieDetailed, titleId: String) -> [FranchisePart] {
        (details.franchise ?? []).map { part in
            FranchisePart(
                titleId: part.current ? titleId : part.franchiseId.flatMap { RecParsing.titleId(fromPath: $0) },
                name: part.name,
                year: RecParsing.year(part.year),
                position: part.position,
                isCurrent: part.current,
            )
        }
    }

    /// Everything a page connects its title to, as board rows: lists, collections, the franchise, the directors and
    /// the first five actors.
    static func boardMembers(of features: TitleFeatures) -> [BoardMember] {
        var members = features.boards.map { BoardMember(board: $0, titleId: features.id) }
        if let franchiseId = features.franchiseId {
            let ordered = features.franchise.sorted { $0.position < $1.position }
            let name = ordered.first?.name ?? features.name
            for part in ordered {
                guard let titleId = part.titleId else { continue }
                members.append(BoardMember(
                    board: BoardRef(id: franchiseId, kind: .franchise, name: name, rank: part.position, size: ordered.count),
                    titleId: titleId,
                ))
            }
        }
        for person in features.directors {
            members.append(BoardMember(board: BoardRef(id: person.id, kind: .director, name: person.name), titleId: features.id))
        }
        for person in features.actors.prefix(5) {
            members.append(BoardMember(board: BoardRef(id: person.id, kind: .actor, name: person.name), titleId: features.id))
        }
        return members
    }

    /// The page's genre links («films/drama/» → «Драмы»): how a path's slug reads.
    static func genreSlugs(of details: MovieDetailed) -> [(slug: String, name: String)] {
        (details.genres ?? []).compactMap { genre in
            RecParsing.genreSlug(fromGenreLink: genre.genreId).map { ($0, genre.name) }
        }
    }

    // MARK: Card

    static func features(from card: MovieSimple, genreNames: GenreNames, now: Date = .now) -> TitleFeatures? {
        guard let id = RecParsing.titleId(fromPath: card.movieId) else { return nil }
        let caption = CardCaptionParser.parse(card.details)
        let kind = RecParsing.kind(fromPath: card.movieId) ?? card.cat.map(titleKind)
        let genre = caption.genre ?? RecParsing.genreSlug(fromPath: card.movieId).flatMap(genreNames)

        var seasons: Int?
        if case let .series(season, _) = card.info { seasons = season }

        return TitleFeatures(
            id: id,
            path: card.movieId,
            level: .card,
            kind: kind,
            name: (card.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            year: caption.year,
            genres: genre.map { [$0] } ?? [],
            countries: caption.countries,
            siteRating: card.cat?.rating.flatMap { $0 > 0 ? Double($0) : nil },
            isSeries: kind == .series || kind == .show || card.info != nil || caption.isOngoing || caption.endYear != nil,
            seasons: seasons,
            poster: nonEmpty(card.poster),
            fetchedAt: now.timeIntervalSince1970,
        )
    }

    /// The card's path slug and its caption's genre name, when both are there («drama» → «Драмы»).
    static func genreSlug(of card: MovieSimple) -> (slug: String, name: String)? {
        guard let slug = RecParsing.genreSlug(fromPath: card.movieId), let genre = CardCaptionParser.parse(card.details).genre else { return nil }
        return (slug, genre)
    }

    private static func titleKind(_ cat: MovieSimple.Cat) -> TitleKind {
        switch cat {
        case .film: .film
        case .series: .series
        case .anime: .anime
        case .cartoon: .cartoon
        case .show: .show
        }
    }

    /// The cards of a page in a board: a ranked list gives each its place (`board.rank` is the first card's place on
    /// this page, 1 when missing); a collection or a filmography has no order.
    static func boardMembers(of cards: [MovieSimple], board: BoardRef) -> [BoardMember] {
        let first = board.rank ?? 1
        return cards.compactMap { RecParsing.titleId(fromPath: $0.movieId) }
            .enumerated()
            .map { index, titleId in
                var placed = board
                placed.rank = board.kind == .list || board.kind == .franchise ? first + index : nil
                return BoardMember(board: placed, titleId: titleId)
            }
    }

    // MARK: «Досмотреть»

    static func features(from item: MovieWatchLater, genreNames: GenreNames, now: Date = .now) -> TitleFeatures? {
        guard let id = RecParsing.titleId(fromPath: item.watchLaterId) else { return nil }
        let kind = RecParsing.kind(fromPath: item.watchLaterId)
        let years = CardCaptionParser.years(in: item.years)
        return TitleFeatures(
            id: id,
            path: item.watchLaterId,
            level: .card,
            kind: kind,
            name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
            year: years?.start ?? RecParsing.year(item.details),
            genres: RecParsing.genreSlug(fromPath: item.watchLaterId).flatMap(genreNames).map { [$0] } ?? [],
            isSeries: item.isSeries || kind == .series || kind == .show,
            seasons: item.watchingEpisode?.season,
            poster: nonEmpty(item.cover),
            fetchedAt: now.timeIntervalSince1970,
        )
    }

    static func accountItem(from item: MovieWatchLater, now: Date = .now) -> AccountListItem? {
        guard let id = RecParsing.titleId(fromPath: item.watchLaterId) else { return nil }
        let place = item.watchingEpisode
        return AccountListItem(
            titleId: id,
            watched: item.watched,
            lastActivityAt: RecParsing.date(item.date, now: now)?.timeIntervalSince1970,
            season: place?.season,
            episode: place?.episode,
            episodesLeft: RecParsing.episodesLeft(item.buttonText),
        )
    }

    // MARK: Merging

    /// What to store when a title is seen again. A page replaces what was known (keeping what only other sources
    /// add: critics, ids the page didn't show this time); a card fills gaps of an older card and never touches a page.
    static func merge(existing: TitleFeatures?, incoming: TitleFeatures) -> TitleFeatures {
        guard let existing else { return incoming }

        switch (existing.level, incoming.level) {
        case (_, .page):
            var merged = incoming
            merged.kpId = incoming.kpId ?? existing.kpId
            merged.imdbId = incoming.imdbId ?? existing.imdbId
            merged.rtCritic = incoming.rtCritic ?? existing.rtCritic
            merged.metacritic = incoming.metacritic ?? existing.metacritic
            merged.poster = incoming.poster ?? existing.poster
            merged.kind = incoming.kind ?? existing.kind
            merged.year = incoming.year ?? existing.year
            return merged

        case (.page, .card):
            var kept = existing
            if kept.poster == nil { kept.poster = incoming.poster }
            if kept.kind == nil { kept.kind = incoming.kind }
            return kept

        case (.card, .card):
            var merged = existing
            if !incoming.name.isEmpty { merged.name = incoming.name }
            merged.kind = incoming.kind ?? existing.kind
            merged.year = incoming.year ?? existing.year
            if !incoming.genres.isEmpty { merged.genres = incoming.genres }
            if !incoming.countries.isEmpty { merged.countries = incoming.countries }
            merged.siteRating = incoming.siteRating ?? existing.siteRating
            merged.isSeries = existing.isSeries || incoming.isSeries
            merged.seasons = max(incoming.seasons ?? 0, existing.seasons ?? 0) > 0 ? max(incoming.seasons ?? 0, existing.seasons ?? 0) : nil
            merged.poster = incoming.poster ?? existing.poster
            merged.fetchedAt = incoming.fetchedAt
            return merged
        }
    }

    /// Whether a merge changed anything worth a write (a card seen again within a day only refreshes its date).
    static func needsWrite(existing: TitleFeatures?, merged: TitleFeatures) -> Bool {
        guard let existing else { return true }
        var a = existing, b = merged
        a.fetchedAt = 0
        b.fetchedAt = 0
        return a != b || merged.fetchedAt - existing.fetchedAt > 86400
    }

    // MARK: Helpers

    private static func people(_ people: [PersonSimple], limit: Int) -> [PersonRef] {
        var seen: Set<String> = []
        var refs: [PersonRef] = []
        for person in people {
            let id = RecParsing.personKey(fromPath: person.personId) ?? person.personId
            guard !id.isEmpty, !person.name.isEmpty, seen.insert(id).inserted else { continue }
            refs.append(PersonRef(id: id, name: person.name))
            if refs.count == limit { break }
        }
        return refs
    }

    /// The description as one paragraph (nil when the site shows «-»).
    static func synopsis(_ text: String) -> String? {
        let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty || text == "-" ? nil : text
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
