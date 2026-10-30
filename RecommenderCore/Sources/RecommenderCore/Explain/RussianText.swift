import Foundation

/// Russian wording for reasons, tags and rows: plurals, quotes, ratings, durations, genre and country forms.
/// Phrases are built so names stay in the nominative («после фильма «Дюна»», «Режиссёр Дени Вильнёв»): the engine
/// can't decline arbitrary titles and names, and a wrong case reads worse than a careful construction.
enum RussianText {
    /// Card notes aim for this length (`KPPosterCard.note`).
    static let shortLimit = 28

    /// 1 серия, 2 серии, 5 серий.
    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n = abs(count) % 100
        let last = n % 10
        if n >= 11, n <= 14 { return many }
        if last == 1 { return one }
        if last >= 2, last <= 4 { return few }
        return many
    }

    /// «2 серии».
    static func count(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(count) \(plural(count, one, few, many))"
    }

    /// A name in «ёлочки», without quotes of its own, shortened with «…» to at most `limit` characters inside.
    static func quoted(_ name: String, limit: Int? = nil) -> String {
        var clean = name.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
            .replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let limit, clean.count > limit, limit >= 2 {
            clean = String(clean.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return "«\(clean)»"
    }

    /// The first variant that fits the card (≤ ~28 characters), else the shortest one.
    static func fit(_ variants: [String], limit: Int = shortLimit) -> String {
        if let fitting = variants.first(where: { $0.count <= limit }) { return fitting }
        return variants.min { $0.count < $1.count } ?? ""
    }

    /// A template with a quoted name, shortening the name until the line fits: `prefix + «name» + suffix`.
    static func fitQuoted(_ prefix: String, _ name: String, _ suffix: String = "", limit: Int = shortLimit) -> String {
        let full = prefix + quoted(name) + suffix
        if full.count <= limit { return full }
        let room = limit - prefix.count - suffix.count - 2
        guard room >= 6 else { return full }
        return prefix + quoted(name, limit: room) + suffix
    }

    /// 8,0 — one decimal, a comma.
    static func rating(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let whole = Int(rounded)
        let tenth = Int(((rounded - Double(whole)) * 10).rounded())
        return "\(whole),\(abs(tenth))"
    }

    /// 1 ч 38 мин, 45 мин, 2 ч.
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) мин" }
        if rest == 0 { return "\(hours) ч" }
        return "\(hours) ч \(rest) мин"
    }

    /// «2010-е».
    static func decade(_ decade: Int) -> String { "\(decade)-е" }

    /// «3-й».
    static func ordinal(_ number: Int) -> String { "\(number)-й" }

    static func kindPlural(_ kind: TitleKind) -> String {
        switch kind {
        case .film: "Фильмы"
        case .series: "Сериалы"
        case .cartoon: "Мультфильмы"
        case .anime: "Аниме"
        case .show: "ТВ-шоу"
        }
    }

    /// «фильма», «сериала» (after «после», «продолжение»): the noun keeps the title itself in the nominative.
    static func kindGenitive(_ kind: TitleKind?) -> String {
        switch kind {
        case .film, nil: "фильма"
        case .series: "сериала"
        case .cartoon: "мультфильма"
        case .anime: "аниме"
        case .show: "шоу"
        }
    }

    /// «фильм», «сериал» in the accusative («вы досмотрели этот сериал»).
    static func kindAccusative(_ kind: TitleKind?) -> String {
        switch kind {
        case .film, nil: "фильм"
        case .series: "сериал"
        case .cartoon: "мультфильм"
        case .anime: "аниме"
        case .show: "шоу"
        }
    }

    /// The site's plural genre name as a tag: «Детективы» → «детектив», «Ужасы» → «ужасы».
    static func genreTag(_ name: String) -> String {
        let key = TextKey.normalized(name)
        return genreTags[key] ?? key
    }

    /// The country as an adjective for «Что-то новое»: «Южная Корея» → «корейское кино» / «корейский сериал».
    static func countryPhrase(_ name: String, kind: TitleKind?) -> String {
        let key = TextKey.normalized(name)
        guard let neuter = countryAdjectives[key] else { return name }
        switch kind {
        case .series:
            return String(neuter.dropLast(2)) + "ий сериал"
        case .show:
            return neuter + " шоу"
        case .cartoon:
            return String(neuter.dropLast(2)) + "ий мультфильм"
        case .anime:
            return neuter + " аниме"
        case .film, nil:
            return neuter + " кино"
        }
    }

    /// The surname (the last word of a name), for tight card notes.
    static func surname(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }

    private static let genreTags: [String: String] = [
        "драмы": "драма", "драма": "драма", "комедии": "комедия", "комедия": "комедия", "детективы": "детектив",
        "детектив": "детектив", "триллеры": "триллер", "триллер": "триллер", "ужасы": "ужасы", "боевики": "боевик",
        "боевик": "боевик", "фантастика": "фантастика", "мелодрамы": "мелодрама", "мелодрама": "мелодрама",
        "криминал": "криминал", "приключения": "приключения", "фэнтези": "фэнтези", "мультфильмы": "мультфильм",
        "мультфильм": "мультфильм", "документальные": "документальное", "документальный": "документальное",
        "документальное": "документальное", "военные": "военный", "военный": "военный", "исторические": "исторический",
        "исторический": "исторический", "история": "история", "семейные": "семейный", "семейный": "семейный",
        "биографии": "биография", "биографические": "биография", "биография": "биография", "вестерны": "вестерн",
        "вестерн": "вестерн", "мюзиклы": "мюзикл", "мюзикл": "мюзикл", "музыкальные": "музыкальный",
        "музыка": "музыка", "мистика": "мистика", "спорт": "спорт", "спортивные": "спорт", "аниме": "аниме",
        "детские": "детское", "детский": "детское", "короткометражки": "короткометражка", "ситкомы": "ситком",
        "ситком": "ситком", "реалити-шоу": "реалити-шоу", "ток-шоу": "ток-шоу", "нуар": "нуар",
        "фильмы-нуар": "нуар", "катастрофы": "катастрофа", "психологические": "психологическое",
        "дорамы": "дорама", "дорама": "дорама", "сказки": "сказка", "сказка": "сказка", "аниме-сериалы": "аниме",
        "мультсериалы": "мультсериал", "молодежные": "молодёжное", "супергеройские": "супергерои",
        "супергерои": "супергерои", "киберпанк": "киберпанк", "антиутопия": "антиутопия", "зомби": "зомби",
    ]

    /// Neuter adjectives (all end in «-ое», so «-ий» gives the masculine form).
    private static let countryAdjectives: [String: String] = [
        "сша": "американское", "великобритания": "британское", "франция": "французское", "германия": "немецкое",
        "италия": "итальянское", "испания": "испанское", "япония": "японское", "южная корея": "корейское",
        "корея южная": "корейское", "корея": "корейское", "китай": "китайское", "индия": "индийское",
        "россия": "российское", "ссср": "советское", "швеция": "шведское", "норвегия": "норвежское",
        "дания": "датское", "финляндия": "финское", "исландия": "исландское", "турция": "турецкое",
        "канада": "канадское", "австралия": "австралийское", "мексика": "мексиканское", "бразилия": "бразильское",
        "аргентина": "аргентинское", "польша": "польское", "бельгия": "бельгийское", "нидерланды": "нидерландское",
        "ирландия": "ирландское", "иран": "иранское", "израиль": "израильское", "гонконг": "гонконгское",
        "тайвань": "тайваньское", "таиланд": "тайское", "новая зеландия": "новозеландское", "чехия": "чешское",
        "украина": "украинское", "казахстан": "казахстанское", "грузия": "грузинское", "австрия": "австрийское",
        "швейцария": "швейцарское", "португалия": "португальское", "греция": "греческое", "венгрия": "венгерское",
        "румыния": "румынское", "юар": "южноафриканское", "египет": "египетское", "колумбия": "колумбийское",
        "чили": "чилийское", "филиппины": "филиппинское", "индонезия": "индонезийское",
    ]
}
