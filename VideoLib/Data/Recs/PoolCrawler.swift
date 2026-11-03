import Alamofire
import Foundation
import RecommenderCore

/// Once a week, a few dozen list pages (never title pages) widen the pool the recommender picks from: the site's best
/// lists for each kind in the user's top genres, the newest, the hot slider and «смотрят сейчас», the lists and
/// collections the user's titles are in, and the filmographies of their favourite people. Every page goes through
/// the background queue (one at a time, 1.5 s apart, within the daily limit), and its cards are stored with the
/// board they came from, so a list's places and a collection's members become edges of the graph.
struct PoolCrawler: Sendable {
    let titles: TitleStore
    let signals: SignalStore
    let queue: SiteQueue

    static let interval: TimeInterval = 7 * TitleFreshness.day
    /// At most this many pages per weekly run.
    static let maxRequests = 80
    static let topGenres = 6
    static let anchorBoards = 15
    static let people = 5

    /// What to look for: the user's favourite genres and people, their titles, the kinds they don't want.
    struct Plan: Sendable {
        var topGenres: [String]
        var people: [PersonRef]
        var anchors: [String]
        var excludedKinds: Set<TitleKind>
    }

    func isDue(now: Date = .now) async -> Bool {
        guard let last = await signals.state(StateKey.poolCrawledAt).flatMap(Double.init) else { return true }
        return now.timeIntervalSince1970 - last >= Self.interval
    }

    /// One weekly run. Stops early (rethrowing) when the user signed out, the site isn't set, the day's limit is
    /// used up or the reader is stopped; a page that fails otherwise is skipped.
    func run(_ plan: Plan, now: Date = .now) async throws {
        // Counted from the start: a run cut short by the daily limit picks up next week, not in a loop.
        await signals.setState(StateKey.poolCrawledAt, String(now.timeIntervalSince1970), now: now)
        let titles = titles
        let queue = queue
        var budget = Self.maxRequests

        func fetch<T: Sendable>(_ request: (any URLRequestConvertible)?, _ parse: @escaping @Sendable (String) throws -> T) async throws -> T? {
            guard let request, budget > 0 else { return nil }
            budget -= 1
            do {
                return try await queue.read(request, parse: parse)
            } catch let failure as SiteFailure {
                switch failure {
                case .signedOut, .notConfigured, .dailyLimit, .cancelled: throw failure
                default: return nil
                }
            }
        }

        /// The first page of a ranked list, its cards in their places (skipped when read within 30 days).
        func crawlList(id: String, fallbackName: String) async throws {
            let crawled = await titles.crawledAt(["\(BoardKind.list.rawValue):\(id)"])
            guard now.timeIntervalSince1970 - (crawled.values.first ?? 0) > TitleFreshness.boardLifetime else { return }
            guard let page = try await fetch(Self.listRequest(id, page: 1), { try MovieListsParser.parse(from: $0) }) else { return }
            let board = BoardRef(id: id, kind: .list, name: page.0.isEmpty ? fallbackName : page.0, rank: 1)
            await titles.upsertCards(page.1, board: board, now: now)
            await titles.markCrawled(board, now: now)
        }

        // The site's best lists for each kind, in the user's top genres (and overall).
        if let types = try await fetch(SearchService.categories, { try SearchParser.parseCategories(from: $0) }) {
            for type in types {
                guard let kind = RecParsing.kind(fromPath: type.typeId), !plan.excludedKinds.contains(kind) else { continue }
                var lists: [MovieGenre] = []
                if let overall = type.best.genres.first(where: { $0.genreId.split(separator: "/").last == "best" }) {
                    lists.append(overall)
                }
                for genre in plan.topGenres.prefix(Self.topGenres) {
                    if let match = type.best.genres.first(where: { Self.sameGenre($0.name, genre) }), !lists.contains(match) {
                        lists.append(match)
                    }
                }
                for list in lists {
                    try await crawlList(id: list.genreId, fallbackName: "\(type.name): \(list.name)")
                }
            }
        }

        // What's new and what's watched now.
        if let page = try await fetch(MovieListsService.getNewestMovies(page: 1, filter: "popular", genre: 0), { try MovieListsParser.parse(from: $0) }) {
            await titles.upsertCards(page.1, board: nil, now: now)
        }
        if let cards = try await fetch(MovieListsService.getHotMovies(genre: 0), { try MovieListsParser.parseHotMovies(from: $0) }) {
            await titles.upsertCards(cards, board: nil, now: now)
        }
        for filter in ["watching", "popular"] {
            if let page = try await fetch(MovieListsService.getMovieList1(page: 1, filter: filter, genre: 0), { try MovieListsParser.parse(from: $0) }) {
                await titles.upsertCards(page.1, board: nil, now: now)
            }
        }

        // The lists and collections the user's titles are in.
        let boards = await titles.boards(of: plan.anchors, kinds: [.list, .collection], limit: Self.anchorBoards * 2)
        let crawled = await titles.crawledAt(boards.map(\.key))
        let due = boards.filter { now.timeIntervalSince1970 - (crawled[$0.key] ?? 0) > TitleFreshness.boardLifetime }.prefix(Self.anchorBoards)
        for board in due {
            switch board.kind {
            case .list:
                try await crawlList(id: board.id, fallbackName: board.name)
            case .collection:
                let request = CollectionsService.getMoviesInCollectionWithFilter(collectionId: board.id, page: 1, filter: "popular")
                if let cards = try await fetch(request, { try CollectionsParser.parseMoviesInCollection(from: $0) }) {
                    await titles.upsertCards(cards, board: board, now: now)
                    await titles.markCrawled(board, now: now)
                }
            default:
                break
            }
        }

        // Favourite people's filmographies.
        let people = Array(plan.people.prefix(Self.people))
        let peopleCrawled = await titles.crawledAt(people.flatMap { [Self.key(.director, $0.id), Self.key(.actor, $0.id)] })
        for person in people {
            let keys = [Self.key(.director, person.id), Self.key(.actor, person.id)]
            guard keys.allSatisfy({ now.timeIntervalSince1970 - (peopleCrawled[$0] ?? 0) > TitleFreshness.boardLifetime }) else { continue }
            guard let details = try await fetch(PeopleService.getPersonDetails(id: person.id), { try PeopleParser.parse(from: $0) }) else { continue }
            let name = details.nameRu.isEmpty ? person.name : details.nameRu
            let directed = BoardRef(id: person.id, kind: .director, name: name)
            let acted = BoardRef(id: person.id, kind: .actor, name: name)
            await titles.upsertCards(details.directorMovies ?? [], board: directed, now: now)
            await titles.upsertCards((details.actorMovies ?? []) + (details.actressMovies ?? []), board: acted, now: now)
            await titles.markCrawled(directed, now: now)
            await titles.markCrawled(acted, now: now)
        }
    }

    private static func key(_ kind: BoardKind, _ id: String) -> String {
        "\(kind.rawValue):\(id)"
    }

    /// A list's page as the app's own repository asks for it («films/best/drama/2020/»).
    static func listRequest(_ listId: String, page: Int) -> MovieListsService? {
        let list = listId.pathParts
        guard list.count > 1 else { return nil }
        let genre = list.count > 2 && !list[2].isNumber ? list[2] : nil
        let year = list.count > 3 ? list[3] : (list.count > 2 && list[2].isNumber ? list[2] : nil)
        return .getMovieList2(type: list[0], listType: list[1], genre: genre, year: year, page: page)
    }

    /// «Драмы» and «драмы», «Фантастика» and «Фантастические» are one genre for this.
    static func sameGenre(_ lhs: String, _ rhs: String) -> Bool {
        let a = RecParsing.normalized(lhs), b = RecParsing.normalized(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let sa = RecParsing.stem(a), sb = RecParsing.stem(b)
        return sa.count >= 5 && sb.count >= 5 && (sa.hasPrefix(sb) || sb.hasPrefix(sa))
    }
}
