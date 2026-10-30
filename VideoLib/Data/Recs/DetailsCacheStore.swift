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
