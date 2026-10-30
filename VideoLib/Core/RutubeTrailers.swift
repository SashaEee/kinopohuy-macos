import Foundation

/// Trailers from Rutube: the site's own are YouTube embeds, which AVPlayer can't play; Rutube gives an HLS stream. Matching (checked
/// on 252 titles): one of the title's names standing on its own in the
/// video's title (not inside another one's: «Телефонные мошенники», «Декстер: Воскрешение», «Дэдпул 2»),
/// "трейлер" or "тизер", no other year than its own, and not a reaction, review or fan-made one. A near miss
/// gives no trailer rather than another film's.
enum RutubeTrailers {
    struct Trailer: Hashable, Sendable {
        let id: String
        let title: String
    }

    private static let base = URL(string: "https://rutube.ru")!

    /// names: Russian first, then the original. Searched with the year first, then without it (doramas and
    /// anime rarely give one).
    static func find(names: [String], year: String?, series: Bool) async -> Trailer? {
        let cleaned = names
            .flatMap { $0.components(separatedBy: " / ") }
            .map { $0.replacingOccurrences(of: "\\[[^\\]]*\\]|\\([^)]*\\)", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let name = cleaned.first else { return nil }

        let info = Info(names: cleaned, year: year, series: series)
        if let year, let hit = await search("\(name) \(year) трейлер", info) { return hit }
        return await search("\(name) трейлер", info)
    }

    /// The trailer's HLS master playlist.
    static func streamURL(id: String) async throws -> URL {
        var components = URLComponents(url: base.appending(path: "api/play/options/\(id)/"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "no_404", value: "true"), .init(name: "referer", value: base.absoluteString)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let options = try JSONDecoder().decode(PlayOptions.self, from: data)
        guard let master = options.video_balancer?.m3u8 ?? options.video_balancer?.default, let url = URL(string: master) else {
            throw URLError(.resourceUnavailable)
        }
        return url
    }

    // MARK: - Search and matching

    private struct Info {
        let names: [String]
        let year: String?
        let series: Bool
    }

    private struct SearchAnswer: Decodable {
        let results: [Video]
    }

    private struct Video: Decodable {
        let id: String
        let title: String
        let duration: Double?
        let hits: Double?
        let is_hidden: Bool?
        let is_deleted: Bool?
        let is_locked: Bool?
        let is_audio: Bool?
        let is_livestream: Bool?
        let is_paid: Bool?
        let is_official: Bool?
    }

    private struct PlayOptions: Decodable {
        struct Balancer: Decodable {
            let m3u8: String?
            let `default`: String?
        }

        let video_balancer: Balancer?
    }

    private static func search(_ query: String, _ info: Info) async -> Trailer? {
        var components = URLComponents(url: base.appending(path: "api/search/video/"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "per_page", value: "30"), .init(name: "query", value: query)]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let answer = try? JSONDecoder().decode(SearchAnswer.self, from: data)
        else { return nil }
        return pick(answer.results, info)
    }

    private static func norm(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "[^a-zа-я0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Words of a video's title that don't tell one title from another.
    private static let noise = try! NSRegularExpression(pattern: "^(трейлер\\S*|тизер\\S*|trailer|teaser|official|официальн\\S*|русск\\S*|на|в|и|с|от|дублированн\\S*|дубляж|озвучк\\S*|субтитр\\S*|сериал\\S*|фильм\\S*|мультфильм\\S*|мультсериал\\S*|мини|аниме|дорам\\S*|сезон\\S*|серия|серии|season|hd|4k|4к|full|fullhd|uhd|1080p|720p|новый|новые|финальн\\S*|второй|первый|основной|главный|полный|netflix|hbo|кинопоиск\\S*|premier|okko|иви|ivi|start|wink|amazon|prime|disney|apple|tv|series|the|of|часть|выход|выходит|скоро|дата|премьера|смотреть|смотрим|онлайн|г|год|\\d{4}|\\d{1,2}|ii|iii|iv)$")
    /// ...and ones that make it something else.
    private static let notATrailer = try! NSRegularExpression(pattern: "(реакци|обзор|разбор|пароди|концепт|concept|fan made|fanmade|фанатск|нейросет|\\bии\\b|\\bai\\b|как должен был|смешн|переозвуч|сравнени|геймплей|gameplay|\\bигра\\b|\\bgame\\b|\\bvs\\b|все трейлеры|подборк|\\bтоп \\d|лучшие|саундтрек|\\bost\\b|клип|интервью|за кадром|съемк|making of)")

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func pick(_ results: [Video], _ info: Info) -> Trailer? {
        let names = info.names.map(norm).filter { $0.count > 1 }
        let nameWords = Set(names.flatMap { $0.split(separator: " ").map(String.init) })
        var best: (trailer: Trailer, score: Double)?

        for video in results {
            if video.is_hidden == true || video.is_deleted == true || video.is_locked == true || video.is_audio == true
                || video.is_livestream == true || video.is_paid == true { continue }
            let duration = video.duration ?? 0
            guard duration >= 25, duration <= 330 else { continue }
            let t = " " + norm(video.title) + " "
            guard t.range(of: "(трейлер|тизер|trailer|teaser)", options: .regularExpression) != nil else { continue }

            guard let hit = names.enumerated().lazy.compactMap({ i, n in t.range(of: " \(n) ").map { (i, n, $0) } }).first else { continue }
            var other = t
            for n in names { other = other.replacingOccurrences(of: " \(n) ", with: " ") }
            if matches(notATrailer, other) { continue }

            // A word glued to the name makes it another title; so does a number after it that isn't a season.
            let before = t[..<hit.2.lowerBound].split(separator: " ").last.map(String.init)
            let after = t[hit.2.upperBound...].split(separator: " ").map(String.init)
            if let before, !matches(noise, before), !nameWords.contains(before) { continue }
            if let first = after.first, !matches(noise, first), !nameWords.contains(first) { continue }
            if let first = after.first, first.range(of: "^(\\d|ii|iii|iv)$", options: .regularExpression) != nil,
               !(after.dropFirst().first?.hasPrefix("сезон") ?? false), !(after.dropFirst().first?.hasPrefix("season") ?? false),
               !t[..<hit.2.lowerBound].suffix(12).contains("сезон"), !t[..<hit.2.lowerBound].suffix(12).contains("season") { continue }

            var score = 10.0
            for (k, n) in names.enumerated() where k != hit.0 && t.contains(" \(n) ") { score += 2 } // its other name too
            let years = t.matches(of: /\ (19|20)\d\d(?=\ )/).map { $0.output.0.trimmingCharacters(in: .whitespaces) }
            let yearHit = info.year.map { years.contains($0) } ?? false
            if yearHit {
                score += 3
            } else if let year = info.year, let y = Int(year), !years.isEmpty {
                // Another year: another title of the same name — unless it's a later season's trailer.
                let later = years.allSatisfy { (Int($0) ?? 0) > y }
                guard info.series, later, t.contains("сезон") || t.contains("season") else { continue }
                score -= 1
            }
            // A one-word name («Курьер», «Братья») alone could be any of a dozen titles: it needs the year too.
            if !hit.1.contains(" "), !yearHit, score < 12 { continue }
            let rest = other.split(separator: " ").map(String.init).filter { !matches(noise, $0) && !nameWords.contains($0) }
            score -= min(3, Double(rest.count) * 0.5)
            if t.contains("русск") || t.contains("дублир") { score += 1.5 }
            if t.contains("официальн") || t.contains("official") { score += 0.5 }
            if video.is_official == true { score += 1 }
            score += min(2, log10(1 + (video.hits ?? 0)) / 2.5)
            if best == nil || score > best!.score { best = (Trailer(id: video.id, title: video.title), score) }
        }
        guard let best, best.score >= 8 else { return nil }
        return best.trailer
    }
}
