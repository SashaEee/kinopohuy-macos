import Foundation
import GRDB
import RecommenderCore

/// The open data pack (built by scripts/datapack, shipped inside the app): critics' scores from Wikidata (Rotten
/// Tomatoes, Metacritic), Kinopoisk ↔ IMDb ids, Russian titles, and «those who liked X also liked Y» by IMDb id.
/// Read-only; the pool's titles are matched by IMDb id, else by Kinopoisk id, else (a bare card) by name and year.
actor RecsPack {
    struct Facts: Sendable {
        let imdb: Int
        let rt: Int?
        let mc: Int?
    }

    private let database: DatabaseQueue?
    /// Title id → IMDb number (nil: looked up, not in the pack), so a pool of thousands is matched once.
    private var imdbByTitle: [String: Int?] = [:]
    private var facts: [Int: Facts] = [:]
    private var neighbours: [Int: [Neighbour]] = [:]

    struct Neighbour: Sendable {
        let imdb: Int
        let score: Double
    }

    /// A film the viewers of the user's titles liked that the pool doesn't have yet: to look for on the site.
    struct Suggestion: Sendable {
        let imdb: Int
        let ru: String?
        let en: String?
        let year: Int?
        let score: Double
    }

    /// The IMDb ids of the pool as last enriched.
    private var poolImdbs: Set<Int> = []

    private struct Loaded: Sendable {
        var facts: [Int: Facts] = [:]
        var neighbours: [Int: [Neighbour]] = [:]
    }

    /// The pack in Application Support/RecsPack when there is one (a newer one placed there by hand while developing),
    /// else the one inside the app; none at all, and everything here quietly returns nothing.
    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "RecsPack/recs-pack.sqlite")
        let candidates = [support, Bundle.main.url(forResource: "recs-pack", withExtension: "sqlite")].compactMap(\.self)
        var configuration = Configuration()
        configuration.readonly = true
        database = candidates.lazy
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .compactMap { try? DatabaseQueue(path: $0.path, configuration: configuration) }
            .first
    }

    var isAvailable: Bool { database != nil }

    /// Titles found on the site by an IMDb id (the lookups): they are that id whatever their name says.
    func remember(_ matches: [String: Int]) {
        for (titleId, imdb) in matches { imdbByTitle[titleId] = imdb }
    }

    /// What viewers of the user's titles liked that the pool lacks, best first: each seed's neighbours by the seed's
    /// weight times their score, without the pool's titles and what was already looked up.
    func suggestions(seeds: [(titleId: String, weight: Double)], excluding looked: Set<Int>, limit: Int) async -> [Suggestion] {
        guard let database, limit > 0 else { return [] }
        var score: [Int: Double] = [:]
        for seed in seeds {
            guard let imdb = imdbByTitle[seed.titleId] ?? nil else { continue }
            for neighbour in neighbours[imdb] ?? [] where !poolImdbs.contains(neighbour.imdb) && !looked.contains(neighbour.imdb) {
                score[neighbour.imdb, default: 0] += seed.weight * neighbour.score
            }
        }
        let best = score.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit)
        guard !best.isEmpty else { return [] }
        let list = best.map { String($0.key) }.joined(separator: ",")
        let names: [Int: (ru: String?, en: String?, year: Int?)] = (try? await database.read { db in
            var names: [Int: (ru: String?, en: String?, year: Int?)] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT imdb, ru, en, year FROM title WHERE imdb IN (\(list))") {
                names[row["imdb"]] = (row["ru"], row["en"], row["year"])
            }
            return names
        }) ?? [:]
        return best.compactMap { imdb, value in
            guard let name = names[imdb], name.ru != nil || name.en != nil else { return nil }
            return Suggestion(imdb: imdb, ru: name.ru, en: name.en, year: name.year, score: value)
        }
    }

    /// The pool with what the pack adds (an IMDb id the card didn't have, the critics' scores), and the viewer
    /// neighbours among the pool's titles.
    func enrich(_ titles: [TitleFeatures]) async -> (titles: [TitleFeatures], neighbours: [String: [ViewerNeighbour]]) {
        guard let database else { return (titles, [:]) }

        // 1. Each title's IMDb number, once.
        let unknown = titles.filter { imdbByTitle[$0.id] == nil }
        if !unknown.isEmpty {
            let found: [String: Int?] = (try? await database.read { db in
                var found: [String: Int?] = [:]
                for title in unknown {
                    found[title.id] = try Self.imdb(for: title, db)
                }
                return found
            }) ?? [:]
            imdbByTitle.merge(found) { _, new in new }
        }

        // 2. Facts and neighbours for the numbers not seen yet.
        let numbers = Set(titles.compactMap { imdbByTitle[$0.id] ?? nil })
        let missing = numbers.filter { facts[$0] == nil }
        if !missing.isEmpty {
            let loaded: Loaded = (try? await database.read { db in
                var loaded = Loaded()
                for chunk in Array(missing).chunked(500) {
                    let list = chunk.map(String.init).joined(separator: ",")
                    for row in try Row.fetchAll(db, sql: "SELECT imdb, rt, mc FROM title WHERE imdb IN (\(list))") {
                        let imdb: Int = row["imdb"]
                        loaded.facts[imdb] = Facts(imdb: imdb, rt: row["rt"], mc: row["mc"])
                    }
                    for row in try Row.fetchAll(db, sql: "SELECT imdb, other, score FROM neighbour WHERE imdb IN (\(list)) ORDER BY imdb, score DESC") {
                        let imdb: Int = row["imdb"]
                        loaded.neighbours[imdb, default: []].append(Neighbour(imdb: row["other"], score: row["score"]))
                    }
                }
                return loaded
            }) ?? Loaded()
            for imdb in missing {
                facts[imdb] = loaded.facts[imdb] ?? Facts(imdb: imdb, rt: nil, mc: nil)
                neighbours[imdb] = loaded.neighbours[imdb] ?? []
            }
        }

        // 3. The pool as the engine gets it.
        poolImdbs = numbers
        var titleByImdb: [Int: String] = [:]
        let enriched = titles.map { title in
            guard let imdb = imdbByTitle[title.id] ?? nil else { return title }
            var title = title
            if titleByImdb[imdb] == nil { titleByImdb[imdb] = title.id }
            if title.imdbId == nil { title.imdbId = String(format: "tt%07d", imdb) }
            if let fact = facts[imdb] {
                title.rtCritic = title.rtCritic ?? fact.rt
                title.metacritic = title.metacritic ?? fact.mc
            }
            return title
        }
        var result: [String: [ViewerNeighbour]] = [:]
        for (imdb, id) in titleByImdb {
            let near = (neighbours[imdb] ?? []).compactMap { pair in
                titleByImdb[pair.imdb].map { ViewerNeighbour(titleId: $0, score: pair.score) }
            }
            if !near.isEmpty { result[id] = near }
        }
        return (enriched, result)
    }

    /// The critics' scores for one IMDb id (the title page's chips).
    func critics(imdb: Int) async -> Facts? {
        if let known = facts[imdb] { return known }
        guard let database else { return nil }
        let fact = (try? await database.read { db -> Facts in
            let row = try Row.fetchOne(db, sql: "SELECT rt, mc FROM title WHERE imdb = ?", arguments: [imdb])
            return Facts(imdb: imdb, rt: row?["rt"], mc: row?["mc"])
        }) ?? Facts(imdb: imdb, rt: nil, mc: nil)
        facts[imdb] = fact
        return fact
    }

    /// IMDb id from the title, else its Kinopoisk id, else its Russian name and year (±1: the site and Wikidata may
    /// count a film's year differently).
    private static func imdb(for title: TitleFeatures, _ db: Database) throws -> Int? {
        if let id = title.imdbId, let number = Int(id.dropFirst(2)) { return number }
        if let kp = title.kpId, let number = try Int.fetchOne(db, sql: "SELECT imdb FROM title WHERE kp = ?", arguments: [kp]) {
            return number
        }
        guard let year = title.year else { return nil }
        // «Собачьи звёзды / Созвездие пса»: the whole name, then its first half.
        let names = [title.name] + (title.name.contains(" / ") ? [String(title.name.components(separatedBy: " / ")[0])] : [])
        for key in names.map(fold) where !key.isEmpty {
            let matches = try Int.fetchAll(
                db, sql: "SELECT imdb FROM title WHERE ru_key = ? AND year BETWEEN ? AND ?", arguments: [key, year - 1, year + 1],
            )
            if matches.count == 1 { return matches[0] }
        }
        return nil
    }

    /// As the pack folds Russian titles: lower case, ё → е, letters and digits only.
    static func fold(_ text: String) -> String {
        String(text.lowercased().replacingOccurrences(of: "ё", with: "е").unicodeScalars.filter { scalar in
            ("0" ... "9").contains(scalar) || ("a" ... "z").contains(scalar) || ("а" ... "я").contains(scalar)
        }.map(Character.init))
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
