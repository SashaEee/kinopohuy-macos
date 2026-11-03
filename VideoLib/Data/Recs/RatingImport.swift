import Foundation

/// «Импорт оценок»: the CSV files IMDb and Letterboxd give out, read into the three-level scale (9–10 «Обожаю», 7–8
/// «Нравится», 5–6 «смотрел», 4 and less «Не моё», as with the site's own stars). IMDb rows carry the IMDb id; Letterboxd
/// rows only a name and a year, matched later through the data pack.
enum RatingImport {
    enum Format: Equatable, Sendable {
        case imdb
        case letterboxd
    }

    struct Entry: Equatable, Sendable {
        var imdb: Int?
        var name: String?
        var year: Int?
        var level: Double
        var ratedAt: Double?
    }

    /// The file's rows, or nil when it's neither an IMDb nor a Letterboxd export.
    static func parse(_ text: String) -> (format: Format, entries: [Entry])? {
        let rows = csv(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { return nil }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }

        // IMDb: Const, Your Rating, Date Rated, Title, …, Year
        if let const = column("const"), let rating = column("your rating") {
            let date = column("date rated")
            let entries: [Entry] = rows.dropFirst().compactMap { row in
                guard row.indices.contains(rating), row.indices.contains(const),
                      let imdb = Int(row[const].trimmingCharacters(in: .whitespaces).dropFirst(2)),
                      let score = Int(row[rating].trimmingCharacters(in: .whitespaces)), let level = SiteRatingMirror.level(for: score)
                else { return nil }
                return Entry(imdb: imdb, level: level, ratedAt: date.flatMap { row.indices.contains($0) ? day(row[$0]) : nil })
            }
            return (.imdb, entries)
        }

        // Letterboxd: Date, Name, Year, Letterboxd URI, Rating (½…5 stars) — ratings.csv or diary.csv.
        if let name = column("name"), let year = column("year"), let rating = column("rating") {
            let date = column("watched date") ?? column("date")
            let entries: [Entry] = rows.dropFirst().compactMap { row in
                guard row.indices.contains(rating), row.indices.contains(name),
                      let stars = Double(row[rating].trimmingCharacters(in: .whitespaces)), stars > 0,
                      let level = SiteRatingMirror.level(for: Int((stars * 2).rounded()))
                else { return nil }
                let title = row[name].trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return nil }
                return Entry(
                    name: title, year: row.indices.contains(year) ? Int(row[year].trimmingCharacters(in: .whitespaces)) : nil,
                    level: level, ratedAt: date.flatMap { row.indices.contains($0) ? day(row[$0]) : nil },
                )
            }
            return (.letterboxd, entries)
        }
        return nil
    }

    /// «2024-03-17» → the day's start (UTC), as seconds.
    private static func day(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))?.timeIntervalSince1970
    }

    /// RFC 4180: commas, quoted fields with "" for a quote and line breaks inside quotes.
    static func csv(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        func next() -> Unicode.Scalar? {
            if let scalar = pending {
                pending = nil
                return scalar
            }
            return iterator.next()
        }
        while let scalar = next() {
            if quoted {
                if scalar == "\"" {
                    let following = next()
                    if following == "\"" {
                        field.unicodeScalars.append("\"")
                    } else {
                        // The closing quote: what followed it is read again outside the quotes.
                        quoted = false
                        pending = following
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"":
                quoted = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r":
                if scalar == "\r", let following = next(), following != "\n" { pending = following }
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            default:
                field.unicodeScalars.append(scalar)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
