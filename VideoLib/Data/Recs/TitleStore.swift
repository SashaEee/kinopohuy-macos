import Foundation
import GRDB
import RecommenderCore

/// How long what a page said stays true enough (the plan's §6.5): a running series' schedule a day, a new title
/// three days, ratings, votes, «Смотрите также» and lists two weeks; titles nobody is waiting for keep their genres,
/// people and description for three months.
enum TitleFreshness {
    static let day: TimeInterval = 86400
    /// Genres, people, the description.
    static let staticLifetime: TimeInterval = 90 * day
    /// A board's members and a person's filmography.
    static let boardLifetime: TimeInterval = 30 * day

    /// How soon a page is worth reading again for a title that matters now (history, «Досмотреть», top candidates).
    static func lifetime(of title: TitleFeatures, now: Date = .now) -> TimeInterval {
        let now = now.timeIntervalSince1970
        if title.isSeries, !title.comingSoon, let last = title.lastEpisodeAt, now - last < 60 * day { return day }
        if let released = title.releasedAt, now - released < 60 * day { return 3 * day }
        if title.comingSoon { return 3 * day }
        return 14 * day
    }

    /// Whether a page should be read again: soon for a title that matters, otherwise only once its static part ages.
    static func isStale(_ title: TitleFeatures, important: Bool, now: Date = .now) -> Bool {
        guard title.level == .page else { return true }
        let age = now.timeIntervalSince1970 - title.fetchedAt
        return age > (important ? lifetime(of: title, now: now) : staticLifetime)
    }
}

/// The local catalogue: every title the app has seen on the site, as a list card or a whole page, plus the boards
/// that tie them together (lists with places, collections, franchises, filmographies) and a name index for «как X».
/// Only titles the site really has get in, so the recommender can't suggest anything that isn't there.
struct TitleStore: Sendable {
    let database: any DatabaseWriter

    /// Board rows not seen again for half a year are left out (a list that dropped the title).
    private static let boardMemoryDays: Double = 180

    // MARK: Capture

    /// A title's page, read by the user or in the background. Returns what's stored now.
    @discardableResult
    func upsertPage(_ details: MovieDetailed, now: Date = .now) async -> TitleFeatures? {
        guard let incoming = TitleMapper.features(from: details, now: now) else { return nil }
        let slugs = TitleMapper.genreSlugs(of: details)
        let watchAlso = details.watchAlsoMovies

        return try? await database.write { db in
            let coder = Coder()
            for (slug, name) in slugs {
                try Self.learnGenre(slug: slug, name: name, fromPage: true, db: db)
            }
            let stored = try Self.upsert(incoming, db: db, coder: coder) ?? Self.fetch(id: incoming.id, db: db, coder: coder)
            if let stored {
                try Self.upsertMembers(TitleMapper.boardMembers(of: stored), now: now, db: db)
            }
            // «Смотрите также» comes as cards: the pool grows along the site's own links.
            let names = try Self.genreNames(db: db)
            for card in watchAlso {
                guard let features = TitleMapper.features(from: card, genreNames: names, now: now) else { continue }
                try Self.upsert(features, db: db, coder: coder)
            }
            return stored
        }
    }

    /// Cards from a list, a collection, the search, a filmography; `board` ties them to it (a ranked list's
    /// `rank` is the first card's place on this page). Returns how many titles were new or changed.
    @discardableResult
    func upsertCards(_ cards: [MovieSimple], board: BoardRef?, now: Date = .now) async -> Int {
        guard !cards.isEmpty else { return 0 }
        return (try? await database.write { db in
            let coder = Coder()
            for card in cards {
                if let pair = TitleMapper.genreSlug(of: card) {
                    try Self.learnGenre(slug: pair.slug, name: pair.name, fromPage: false, db: db)
                }
            }
            let names = try Self.genreNames(db: db)
            var changed = 0
            for card in cards {
                guard let features = TitleMapper.features(from: card, genreNames: names, now: now) else { continue }
                if try Self.upsert(features, db: db, coder: coder) != nil { changed += 1 }
            }
            if let board {
                try Self.upsertMembers(TitleMapper.boardMembers(of: cards, board: board), now: now, db: db)
            }
            return changed
        }) ?? 0
    }

    /// The titles of «Досмотреть» as cards (their paths give kind and genre right away).
    func upsertAccountTitles(_ items: [MovieWatchLater], now: Date = .now) async {
        guard !items.isEmpty else { return }
        _ = try? await database.write { db in
            let coder = Coder()
            let names = try Self.genreNames(db: db)
            for item in items {
                guard let features = TitleMapper.features(from: item, genreNames: names, now: now) else { continue }
                try Self.upsert(features, db: db, coder: coder)
            }
        }
    }

    /// Notes when a board was last read in the background (and its size when the site says it).
    func markCrawled(_ board: BoardRef, size: Int? = nil, now: Date = .now) async {
        _ = try? await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO board_info (boardKey, name, size, crawledAt, updatedAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(boardKey) DO UPDATE SET name = excluded.name, size = COALESCE(excluded.size, board_info.size),
                    crawledAt = excluded.crawledAt, updatedAt = excluded.updatedAt
                """,
                arguments: [board.key, board.name, size ?? board.size, now.timeIntervalSince1970, now.timeIntervalSince1970],
            )
        }
    }

    /// When each board was last read in the background.
    func crawledAt(_ boardKeys: [String]) async -> [String: Double] {
        guard !boardKeys.isEmpty else { return [:] }
        return (try? await database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT boardKey, crawledAt FROM board_info WHERE crawledAt IS NOT NULL AND boardKey IN (\(Self.placeholders(boardKeys.count)))",
                arguments: StatementArguments(boardKeys),
            )
            var result: [String: Double] = [:]
            for row in rows {
                let key: String = row["boardKey"]
                let at: Double = row["crawledAt"]
                result[key] = at
            }
            return result
        }) ?? [:]
    }

    // MARK: Reading

    /// The whole pool, as the engine takes it: each title with the boards and people other pages told about it
    /// (a card in a list gets that list; a card in a director's filmography gets the director; a card in a
    /// franchise gets its parts).
    func pool(now: Date = .now) async -> [TitleFeatures] {
        (try? await database.read { db in
            let coder = Coder()
            let since = now.timeIntervalSince1970 - Self.boardMemoryDays * TitleFreshness.day
            let rows = try Row.fetchAll(db, sql: "SELECT id, path, level, kind, name, originalName, year, features, fetchedAt FROM title_meta")
            var titles = rows.map { Self.decode($0, coder: coder) }

            let memberRows = try Row.fetchAll(db, sql: "SELECT boardKey, titleId, rank, name FROM board_member WHERE updatedAt >= ?", arguments: [since])
            let declared = try Row.fetchAll(db, sql: "SELECT boardKey, size FROM board_info WHERE size IS NOT NULL")
            let genreNames = try Self.genreNames(db: db)

            var sizes: [String: Int] = [:]
            var byTitle: [String: [(key: String, rank: Int?, name: String)]] = [:]
            for row in memberRows {
                let key: String = row["boardKey"]
                let titleId: String = row["titleId"]
                sizes[key, default: 0] += 1
                let rank: Int? = row["rank"]
                let name: String = row["name"]
                byTitle[titleId, default: []].append((key, rank, name))
            }
            for row in declared {
                let key: String = row["boardKey"]
                let size: Int = row["size"]
                sizes[key] = max(sizes[key] ?? 0, size)
            }

            // A franchise's parts as any of its pages lists them, for parts known only as cards.
            var franchises: [String: [FranchisePart]] = [:]
            for title in titles where title.level == .page {
                if let id = title.franchiseId, !title.franchise.isEmpty, franchises[id] == nil {
                    franchises[id] = title.franchise
                }
            }

            for index in titles.indices {
                Self.enrich(&titles[index], members: byTitle[titles[index].id] ?? [], sizes: sizes, franchises: franchises, genreNames: genreNames)
            }
            return titles
        }) ?? []
    }

    func title(_ id: String) async -> TitleFeatures? {
        try? await database.read { db in try Self.fetch(id: id, db: db, coder: Coder()) }
    }

    func titles(_ ids: [String]) async -> [String: TitleFeatures] {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return [:] }
        return (try? await database.read { db in
            let coder = Coder()
            var result: [String: TitleFeatures] = [:]
            for chunk in ids.recChunks(of: 500) {
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT id, path, level, kind, name, originalName, year, features, fetchedAt FROM title_meta WHERE id IN (\(Self.placeholders(chunk.count)))",
                    arguments: StatementArguments(chunk),
                )
                for row in rows {
                    let title = Self.decode(row, coder: coder)
                    result[title.id] = title
                }
            }
            return result
        }) ?? [:]
    }

    /// «как X»: titles whose name (Russian or original) starts with the typed words, the exact name first, then
    /// whole pages, then the most voted.
    func search(_ text: String, limit: Int = 8) async -> [TitleFeatures] {
        guard let query = RecParsing.ftsQuery(text) else { return [] }
        let wanted = RecParsing.normalized(text)
        let found: [TitleFeatures] = (try? await database.read { db in
            let coder = Coder()
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT title_meta.id, title_meta.path, title_meta.level, title_meta.kind, title_meta.name,
                       title_meta.originalName, title_meta.year, title_meta.features, title_meta.fetchedAt
                FROM title_fts JOIN title_meta ON title_meta.id = title_fts.id
                WHERE title_fts MATCH ?
                ORDER BY bm25(title_fts)
                LIMIT 60
                """,
                arguments: [query],
            )
            return rows.map { Self.decode($0, coder: coder) }
        }) ?? []

        func exact(_ title: TitleFeatures) -> Bool {
            RecParsing.normalized(title.name) == wanted || title.originalName.map(RecParsing.normalized) == wanted
        }
        func votes(_ title: TitleFeatures) -> Int { title.kpVotes ?? title.imdbVotes ?? title.siteVotes ?? 0 }

        return found.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element, r = rhs.element
                if exact(l) != exact(r) { return exact(l) }
                if (l.level == .page) != (r.level == .page) { return l.level == .page }
                if votes(l) != votes(r) { return votes(l) > votes(r) }
                return lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map(\.element)
    }

    /// Titles known and titles read as whole pages.
    func counts() async -> (known: Int, pages: Int) {
        (try? await database.read { db in
            let known = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM title_meta") ?? 0
            let pages = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM title_meta WHERE level = 'page'") ?? 0
            return (known, pages)
        }) ?? (0, 0)
    }

    /// For the background reader: the titles that share a board with these (lists, collections, franchises,
    /// filmographies), known only as cards, the ones tied to more of them and by stronger boards first.
    func boardMates(of anchors: [String], limit: Int) async -> [String] {
        let anchors = Array(Set(anchors))
        guard !anchors.isEmpty else { return [] }
        let anchorSet = Set(anchors)
        return (try? await database.read { db in
            var score: [String: Double] = [:]
            for chunk in anchors.recChunks(of: 500) {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT b2.boardKey, b2.titleId, b2.rank FROM board_member b1
                    JOIN board_member b2 ON b2.boardKey = b1.boardKey
                    JOIN title_meta m ON m.id = b2.titleId
                    WHERE b1.titleId IN (\(Self.placeholders(chunk.count))) AND m.level = 'card'
                    """,
                    arguments: StatementArguments(chunk),
                )
                for row in rows {
                    let titleId: String = row["titleId"]
                    guard !anchorSet.contains(titleId) else { continue }
                    let key: String = row["boardKey"]
                    let rank: Int? = row["rank"]
                    let kind = key.split(separator: ":").first.map(String.init) ?? ""
                    let weight: Double = switch kind {
                    case BoardKind.franchise.rawValue: 1.0
                    case BoardKind.list.rawValue: 0.8 * (rank.map { $0 <= 20 ? 1.5 : 1.0 } ?? 1.0)
                    case BoardKind.collection.rawValue: 0.6
                    case BoardKind.director.rawValue: 0.5
                    default: 0.25
                    }
                    score[titleId, default: 0] += weight
                }
            }
            return score.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map(\.key)
        }) ?? []
    }

    /// The boards these titles are in (of the given kinds), the ones holding more of them first: for the pool
    /// crawl, the lists and collections around what the user watched.
    func boards(of titleIds: [String], kinds: Set<BoardKind>, limit: Int) async -> [BoardRef] {
        let ids = Array(Set(titleIds))
        guard !ids.isEmpty, limit > 0 else { return [] }
        return (try? await database.read { db in
            var counts: [String: (name: String, count: Int)] = [:]
            for chunk in ids.recChunks(of: 500) {
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT boardKey, MAX(name) AS name, COUNT(*) AS n FROM board_member WHERE titleId IN (\(Self.placeholders(chunk.count))) GROUP BY boardKey",
                    arguments: StatementArguments(chunk),
                )
                for row in rows {
                    let key: String = row["boardKey"]
                    let name: String = row["name"]
                    let n: Int = row["n"]
                    counts[key] = (name, (counts[key]?.count ?? 0) + n)
                }
            }
            return counts
                .compactMap { key, value -> (BoardRef, Int)? in
                    guard let colon = key.firstIndex(of: ":"), let kind = BoardKind(rawValue: String(key[..<colon])), kinds.contains(kind) else { return nil }
                    return (BoardRef(id: String(key[key.index(after: colon)...]), kind: kind, name: value.name), value.count)
                }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.key < $1.0.key }
                .prefix(limit)
                .map(\.0)
        }) ?? []
    }

    // MARK: Rows

    /// Encoding of the stored features, made once per transaction.
    private struct Coder {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
    }

    /// Writes a title if anything changed; returns what's stored then (nil when nothing was written).
    @discardableResult
    private static func upsert(_ incoming: TitleFeatures, db: Database, coder: Coder) throws -> TitleFeatures? {
        guard !incoming.name.isEmpty || incoming.level == .page else {
            // A nameless card (a broken caption) only adds to a title already known.
            guard try fetch(id: incoming.id, db: db, coder: coder) != nil else { return nil }
            return nil
        }
        let existing = try fetch(id: incoming.id, db: db, coder: coder)
        let merged = TitleMapper.merge(existing: existing, incoming: incoming)
        guard TitleMapper.needsWrite(existing: existing, merged: merged) else { return nil }

        let json = try String(decoding: coder.encoder.encode(merged), as: UTF8.self)
        try db.execute(
            sql: """
            INSERT INTO title_meta (id, path, level, kind, primaryGenre, name, originalName, year, kpId, imdbId, features, fetchedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET path = excluded.path, level = excluded.level, kind = excluded.kind,
                primaryGenre = excluded.primaryGenre, name = excluded.name, originalName = excluded.originalName,
                year = excluded.year, kpId = excluded.kpId, imdbId = excluded.imdbId, features = excluded.features,
                fetchedAt = excluded.fetchedAt
            """,
            arguments: [
                merged.id, merged.path, merged.level.rawValue, merged.kind?.rawValue, merged.genres.first, merged.name,
                merged.originalName, merged.year, merged.kpId, merged.imdbId, json, merged.fetchedAt,
            ],
        )

        if existing == nil || existing?.name != merged.name || existing?.originalName != merged.originalName {
            try syncNameIndex(merged, db: db)
        }
        return merged
    }

    /// The name index for «как X» (normalized: lower case, «ё» as «е»), one row per title by its number.
    private static func syncNameIndex(_ title: TitleFeatures, db: Database) throws {
        guard let rowid = Int64(title.id) else { return }
        try db.execute(sql: "DELETE FROM title_fts WHERE rowid = ?", arguments: [rowid])
        try db.execute(
            sql: "INSERT INTO title_fts (rowid, id, name, originalName) VALUES (?, ?, ?, ?)",
            arguments: [rowid, title.id, RecParsing.normalized(title.name), title.originalName.map(RecParsing.normalized) ?? ""],
        )
    }

    private static func upsertMembers(_ members: [BoardMember], now: Date, db: Database) throws {
        let at = now.timeIntervalSince1970
        var boards: [String: BoardRef] = [:]
        for member in members {
            try db.execute(
                sql: """
                INSERT INTO board_member (boardKey, titleId, rank, name, updatedAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(boardKey, titleId) DO UPDATE SET rank = COALESCE(excluded.rank, board_member.rank),
                    name = excluded.name, updatedAt = excluded.updatedAt
                """,
                arguments: [member.board.key, member.titleId, member.board.rank, member.board.name, at],
            )
            boards[member.board.key] = member.board
        }
        for board in boards.values {
            try db.execute(
                sql: """
                INSERT INTO board_info (boardKey, name, size, updatedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(boardKey) DO UPDATE SET name = excluded.name, size = COALESCE(excluded.size, board_info.size),
                    updatedAt = excluded.updatedAt
                """,
                arguments: [board.key, board.name, board.size, at],
            )
        }
    }

    private static func learnGenre(slug: String, name: String, fromPage: Bool, db: Database) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, !name.isEmpty else { return }
        if fromPage {
            try db.execute(
                sql: "INSERT INTO genre_slug (slug, name, fromPage) VALUES (?, ?, 1) ON CONFLICT(slug) DO UPDATE SET name = excluded.name, fromPage = 1",
                arguments: [slug, name],
            )
        } else {
            // A card's caption only names a slug no page has named yet.
            try db.execute(
                sql: "INSERT INTO genre_slug (slug, name, fromPage) VALUES (?, ?, 0) ON CONFLICT(slug) DO UPDATE SET name = excluded.name WHERE genre_slug.fromPage = 0",
                arguments: [slug, name],
            )
        }
    }

    private static func genreNames(db: Database) throws -> TitleMapper.GenreNames {
        let rows = try Row.fetchAll(db, sql: "SELECT slug, name FROM genre_slug")
        var map: [String: String] = [:]
        for row in rows {
            let slug: String = row["slug"]
            let name: String = row["name"]
            map[slug] = name
        }
        return { [map] slug in map[slug] }
    }

    private static func fetch(id: String, db: Database, coder: Coder) throws -> TitleFeatures? {
        try Row.fetchOne(
            db,
            sql: "SELECT id, path, level, kind, name, originalName, year, features, fetchedAt FROM title_meta WHERE id = ?",
            arguments: [id],
        ).map { decode($0, coder: coder) }
    }

    /// A stored title; one whose JSON no longer reads (an older shape) comes back as a card from its columns, dated
    /// long ago, so the background reader fetches its page again.
    private static func decode(_ row: Row, coder: Coder) -> TitleFeatures {
        let json: String = row["features"]
        if let features = try? coder.decoder.decode(TitleFeatures.self, from: Data(json.utf8)) {
            return features
        }
        let kind: String? = row["kind"]
        return TitleFeatures(
            id: row["id"],
            path: row["path"],
            level: .card,
            kind: kind.flatMap(TitleKind.init(rawValue:)),
            name: row["name"],
            originalName: row["originalName"],
            year: row["year"],
            fetchedAt: 0,
        )
    }

    /// Adds what other pages said about a title: its lists and collections with sizes, and for a card its directors,
    /// actors, franchise and the genre its path names.
    private static func enrich(
        _ title: inout TitleFeatures, members: [(key: String, rank: Int?, name: String)], sizes: [String: Int],
        franchises: [String: [FranchisePart]], genreNames: TitleMapper.GenreNames,
    ) {
        var keys = Set(title.boards.map(\.key))
        for index in title.boards.indices where title.boards[index].size == nil {
            title.boards[index].size = sizes[title.boards[index].key]
        }
        for member in members {
            guard let colon = member.key.firstIndex(of: ":"),
                  let kind = BoardKind(rawValue: String(member.key[..<colon]))
            else { continue }
            let id = String(member.key[member.key.index(after: colon)...])
            switch kind {
            case .list, .collection:
                guard keys.insert(member.key).inserted else { continue }
                title.boards.append(BoardRef(id: id, kind: kind, name: member.name, rank: member.rank, size: sizes[member.key]))
            case .director:
                if title.level == .card, !title.directors.contains(where: { $0.id == id }) {
                    title.directors.append(PersonRef(id: id, name: member.name))
                }
            case .actor:
                if title.level == .card, title.actors.count < 5, !title.actors.contains(where: { $0.id == id }) {
                    title.actors.append(PersonRef(id: id, name: member.name))
                }
            case .franchise:
                if title.franchiseId == nil {
                    title.franchiseId = id
                    title.franchise = (franchises[id] ?? []).map { part in
                        var part = part
                        part.isCurrent = part.titleId == title.id
                        return part
                    }
                }
            }
        }
        if title.genres.isEmpty, let slug = RecParsing.genreSlug(fromPath: title.path), let name = genreNames(slug) {
            title.genres = [name]
        }
    }

    // MARK: Pack lookups

    /// Every IMDb id looked up on the site so far, with the title found (nil: not there).
    func packLookups() async -> [Int: String?] {
        (try? await database.read { db in
            var result: [Int: String?] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT imdb, titleId FROM pack_lookup") {
                result[row["imdb"]] = row["titleId"] as String?
            }
            return result
        }) ?? [:]
    }

    func recordPackLookup(imdb: Int, titleId: String?, now: Date = .now) async {
        _ = try? await database.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO pack_lookup (imdb, titleId, searchedAt) VALUES (?, ?, ?)",
                arguments: [imdb, titleId, now.timeIntervalSince1970],
            )
        }
    }

    static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}

extension Array {
    /// Slices of at most `size` (SQLite's variables per statement are limited).
    func recChunks(of size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: Swift.max(1, size)).map { self[$0 ..< Swift.min($0 + size, count)] }
    }
}
