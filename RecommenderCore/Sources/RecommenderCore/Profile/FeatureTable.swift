import Foundation

/// Every title's taste features, interned to integers, with document frequencies over the pool (§4.3): genres,
/// countries, decade, directors, the top five actors, kind, a duration bucket, collections and ranked lists.
/// Card-level titles simply have fewer features; nothing here needs a full page.
struct FeatureTable: Sendable {
    /// The site files every title under one of these besides its genres («Зарубежные», «Русские»): sections of its
    /// catalogue, not taste (the country and the kind already say it).
    static let siteSections: Set<String> = ["зарубежные", "русские", "полнометражные", "фильмы", "сериалы"]

    private(set) var keys: [FeatureKey] = []
    /// Display names («Детективы», «Скандинавия», «2010-е», «Дэвид Финчер»).
    private(set) var names: [String] = []
    private(set) var index: [FeatureKey: Int] = [:]
    /// Feature ids per title (by title index), unique and ascending.
    let ofTitle: [[Int]]
    /// The first genre's feature id per title (its main genre, for the genre cap).
    let primaryGenre: [Int?]
    /// Genre feature ids per title, ascending (for similarity).
    let genres: [[Int]]
    let df: [Int]
    let idf: [Double]
    /// g_f: the group's weight from `Weights.groupWeights`.
    let groupWeight: [Double]

    var count: Int { keys.count }

    init(titles: [TitleFeatures], weights: Weights) {
        var keys: [FeatureKey] = []
        var names: [String] = []
        var index: [FeatureKey: Int] = [:]
        var normalizedCache: [String: String] = [:]
        func normalized(_ text: String) -> String {
            if let cached = normalizedCache[text] { return cached }
            let value = TextKey.normalized(text)
            normalizedCache[text] = value
            return value
        }
        func intern(_ key: FeatureKey, _ name: String) -> Int {
            if let id = index[key] { return id }
            let id = keys.count
            keys.append(key)
            names.append(name)
            index[key] = id
            return id
        }

        var ofTitle: [[Int]] = []
        var primaryGenre: [Int?] = []
        var genres: [[Int]] = []
        ofTitle.reserveCapacity(titles.count)
        for title in titles {
            var ids = Set<Int>()
            var titleGenres: [Int] = []
            var first: Int?
            for genre in title.genres where !genre.trimmingCharacters(in: .whitespaces).isEmpty {
                let key = normalized(genre)
                guard !Self.siteSections.contains(key) else { continue }
                let id = intern(FeatureKey(.genre, key), genre)
                if first == nil { first = id }
                if ids.insert(id).inserted { titleGenres.append(id) }
            }
            for country in title.countries where !country.trimmingCharacters(in: .whitespaces).isEmpty {
                ids.insert(intern(FeatureKey(.country, normalized(country)), country))
            }
            if let year = title.year, year > 1800 {
                let decade = year / 10 * 10
                ids.insert(intern(FeatureKey(.decade, String(decade)), RussianText.decade(decade)))
            }
            for person in title.directors where !person.id.isEmpty {
                ids.insert(intern(FeatureKey(.director, person.id), person.name))
            }
            for person in title.actors.prefix(5) where !person.id.isEmpty {
                ids.insert(intern(FeatureKey(.actor, person.id), person.name))
            }
            if let kind = Self.kind(of: title) {
                ids.insert(intern(FeatureKey(.kind, kind.rawValue), RussianText.kindPlural(kind)))
            }
            if let bucket = Self.durationBucket(title) {
                ids.insert(intern(FeatureKey(.duration, bucket.key), bucket.name))
            }
            for board in title.boards {
                switch board.kind {
                case .collection: ids.insert(intern(FeatureKey(.collection, board.id), board.name))
                case .list: ids.insert(intern(FeatureKey(.list, board.id), board.name))
                case .franchise, .director, .actor: break
                }
            }
            ofTitle.append(ids.sorted())
            primaryGenre.append(first)
            genres.append(titleGenres.sorted())
        }

        var df = [Int](repeating: 0, count: keys.count)
        for ids in ofTitle {
            for id in ids { df[id] += 1 }
        }
        let n = Double(titles.count)
        self.keys = keys
        self.names = names
        self.index = index
        self.ofTitle = ofTitle
        self.primaryGenre = primaryGenre
        self.genres = genres
        self.df = df
        // Smoothed IDF, always ≥ 1: «Драмы» on half the pool weighs ~1.7, a rare director ~9.
        idf = df.map { log((n + 1) / (Double($0) + 1)) + 1 }
        groupWeight = keys.map { weights.group($0.group) }
    }

    /// The id of a feature as the app names it (normalised the same way), nil when no title has it.
    func id(of key: FeatureKey) -> Int? {
        switch key.group {
        case .genre, .country:
            index[FeatureKey(key.group, TextKey.normalized(key.value))]
        default:
            index[key]
        }
    }

    /// The kind as the site would group it: an unknown kind of a series is a series.
    static func kind(of title: TitleFeatures) -> TitleKind? {
        title.kind ?? (title.isSeries ? .series : nil)
    }

    /// Films: up to 1.5 h, 1.5–2 h, 2–2.5 h, longer. Series by episode: up to 30 min, 30–50 min, longer.
    static func durationBucket(_ title: TitleFeatures) -> (key: String, name: String)? {
        guard let minutes = title.durationMin, minutes > 0 else { return nil }
        if title.isSeries {
            if minutes <= 30 { return ("ep30", "серии до 30 мин") }
            if minutes <= 50 { return ("ep50", "серии 30–50 мин") }
            return ("ep50+", "серии дольше 50 мин")
        }
        if minutes <= 90 { return ("f90", "до 1,5 ч") }
        if minutes <= 120 { return ("f120", "1,5–2 ч") }
        if minutes <= 150 { return ("f150", "2–2,5 ч") }
        return ("f150+", "дольше 2,5 ч")
    }
}
