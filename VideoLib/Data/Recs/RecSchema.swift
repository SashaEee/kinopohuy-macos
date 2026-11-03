import Foundation
import GRDB

/// The recommender's tables beyond v3: what the account's lists last looked like, board sizes and when each was last
/// read, the genre names behind path slugs, the background reader's counters and the cached title pages.
enum RecSchema {
    /// What was looked up on the site for the data pack's viewer suggestions: the IMDb id, the title found (nil: not
    /// on the site), when. A title found here is that IMDb id from then on; nothing is searched twice.
    static func migrateV5(_ db: Database) throws {
        try db.create(table: "pack_lookup", options: [.ifNotExists, .strict]) { t in
            t.column("imdb", .integer).notNull().primaryKey()
            t.column("titleId", .text)
            t.column("searchedAt", .real).notNull()
        }
    }

    static func migrateV4(_ db: Database) throws {
        // «Досмотреть» as the site last showed it (one request gives the whole list, so it's replaced each time).
        try db.create(table: "account_list", options: [.ifNotExists, .strict]) { t in
            t.column("titleId", .text).notNull().primaryKey()
            t.column("position", .integer).notNull()
            t.column("watched", .integer).notNull()
            t.column("lastActivityAt", .real)
            t.column("season", .integer)
            t.column("episode", .integer)
            t.column("episodesLeft", .integer)
            t.column("capturedAt", .real).notNull()
        }

        // Titles seen in the account's bookmark folders (the folder's name tells intent from favourites).
        try db.create(table: "account_bookmark", options: [.ifNotExists, .strict]) { t in
            t.column("titleId", .text).notNull()
            t.column("folder", .text).notNull()
            t.column("updatedAt", .real).notNull()
            t.primaryKey(["titleId", "folder"])
        }

        // Series the account follows, as the feed of new episodes marks them.
        try db.create(table: "account_followed", options: [.ifNotExists, .strict]) { t in
            t.column("titleId", .text).notNull().primaryKey()
            t.column("updatedAt", .real).notNull()
        }

        // A board's name, its size when the site says it, and when the background reader last went through it.
        try db.create(table: "board_info", options: [.ifNotExists, .strict]) { t in
            t.column("boardKey", .text).notNull().primaryKey()
            t.column("name", .text).notNull()
            t.column("size", .integer)
            t.column("crawledAt", .real)
            t.column("updatedAt", .real).notNull()
        }

        // «drama» → «Драмы»: a «Досмотреть» row or a bare path names its genre only by slug.
        try db.create(table: "genre_slug", options: [.ifNotExists, .strict]) { t in
            t.column("slug", .text).notNull().primaryKey()
            t.column("name", .text).notNull()
            t.column("fromPage", .integer).notNull().defaults(to: 0)
        }

        // Counters and timestamps of the background work (today's pages, the weekly pool, a pause after 403s).
        try db.create(table: "crawl_state", options: [.ifNotExists, .strict]) { t in
            t.column("key", .text).notNull().primaryKey()
            t.column("value", .text).notNull()
            t.column("updatedAt", .real).notNull()
        }

        // Title pages read recently, whole (for the background reader's cache; the title page itself always reads
        // fresh). Kept small: the oldest go first.
        try db.create(table: "details_cache", options: [.ifNotExists, .strict]) { t in
            t.column("path", .text).notNull().primaryKey()
            t.column("payload", .text).notNull()
            t.column("fetchedAt", .real).notNull()
        }

        try db.create(index: "title_meta_level", on: "title_meta", columns: ["level", "fetchedAt"], ifNotExists: true)
        try db.create(index: "rec_impression_shown", on: "rec_impression", columns: ["shownAt"], ifNotExists: true)
        try db.create(index: "watch_event_ended", on: "watch_event", columns: ["endedAt"], ifNotExists: true)
    }
}
