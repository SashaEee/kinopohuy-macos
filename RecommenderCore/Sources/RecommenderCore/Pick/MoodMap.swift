import Foundation

/// Moods and company as boosts and penalties over the site's genres (the plan's §4.9 table), until mood axes and
/// embeddings arrive. Genres are matched by lowercase stems («комеди» → «Комедии», «Комедийная драма»), so the site's
/// spelling doesn't matter. Shared with the TV as `Resources/mood_map.json`; `MoodMap.builtIn` is the compiled-in copy.
public struct MoodMap: Codable, Sendable, Hashable {
    /// One genre's push: positive raises titles of that genre, negative lowers them.
    public struct Effect: Codable, Sendable, Hashable {
        public var stem: String
        public var weight: Double
        /// The boost counts only for titles rated at least this (фантастика for «подумать» — the good kind).
        public var minQuality: Double?

        public init(stem: String, weight: Double, minQuality: Double? = nil) {
            self.stem = stem
            self.weight = weight
            self.minQuality = minQuality
        }
    }

    /// Hard limits and extra pulls that come with a mood or a company.
    public struct Rules: Codable, Sendable, Hashable {
        /// «Семья» → 12+, «уютное» → 16+ (titles with an unknown age pass).
        public var maxAge: Int?
        /// Genres never shown («Семья»: no horror, no erotica).
        public var excludeStems: [String]
        /// «Компания» → films up to 130 minutes.
        public var maxDurationMin: Int?
        /// Boosts halve for titles rated below this («уютное» wants Q ≥ 7).
        public var minQuality: Double?
        /// «Вдвоём»: broadly liked titles (many votes) get this much more.
        public var popularityBoost: Double?
        /// «Подумать»: the rating itself matters, up to this much.
        public var qualityBoost: Double?

        public init(
            maxAge: Int? = nil, excludeStems: [String] = [], maxDurationMin: Int? = nil, minQuality: Double? = nil,
            popularityBoost: Double? = nil, qualityBoost: Double? = nil
        ) {
            self.maxAge = maxAge
            self.excludeStems = excludeStems
            self.maxDurationMin = maxDurationMin
            self.minQuality = minQuality
            self.popularityBoost = popularityBoost
            self.qualityBoost = qualityBoost
        }
    }

    public struct Entry: Codable, Sendable, Hashable {
        public var effects: [Effect]
        public var rules: Rules

        public init(effects: [Effect], rules: Rules = Rules()) {
            self.effects = effects
            self.rules = rules
        }
    }

    public var version: Int
    /// By `Mood.rawValue`.
    public var moods: [String: Entry]
    /// By `Company.rawValue`.
    public var company: [String: Entry]
    /// How much a full mood match adds to a candidate's score (engine scores are roughly 0…1.5).
    public var moodWeight: Double
    public var companyWeight: Double
    /// «как «Мост»»: a title linked to the reference adds up to this much.
    public var similarWeight: Double
    /// «с Ди Каприо»: a title with the person adds this much.
    public var peopleWeight: Double
    /// A mood the user asked for (confidence at least this) must match before the picker lets it go; context moods
    /// only nudge.
    public var moodRequirementConfidence: Double

    public static let current: MoodMap = loadBundled() ?? builtIn

    public static func loadBundled() -> MoodMap? {
        guard let url = Bundle.module.url(forResource: "mood_map", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(MoodMap.self, from: data)
    }

    public func entry(_ mood: Mood) -> Entry? { moods[mood.rawValue] }
    public func entry(_ company: Company) -> Entry? { self.company[company.rawValue] }

    // MARK: - Scores

    /// How well a title fits the asked moods: for each mood, its best matching boost plus every penalty, averaged by
    /// the moods' strengths. Also tells which moods the title matches at all.
    func moodFit(_ title: TitleFeatures, moods: [Mood: Double]) -> (score: Double, matched: Set<Mood>) {
        moodFit(title, genreWords: title.genres.flatMap(IntentText.words), moods: moods)
    }

    /// The same with the title's genre words already split (the picker scores thousands of titles per tap).
    func moodFit(_ title: TitleFeatures, genreWords: [String], moods: [Mood: Double]) -> (score: Double, matched: Set<Mood>) {
        var total = 0.0
        var weight = 0.0
        var matched = Set<Mood>()
        let quality = TitleMatch.quality(title)
        for mood in Mood.allCases {
            guard let strength = moods[mood], strength > 0, let entry = entry(mood) else { continue }
            let fit = Self.fit(title, genreWords: genreWords, entry: entry, quality: quality)
            if fit.positive > 0 { matched.insert(mood) }
            total += strength * fit.score
            weight += strength
        }
        return (weight > 0 ? total / weight : 0, matched)
    }

    func companyFit(_ title: TitleFeatures, company: Company) -> Double {
        companyFit(title, genreWords: title.genres.flatMap(IntentText.words), company: company)
    }

    func companyFit(_ title: TitleFeatures, genreWords: [String], company: Company) -> Double {
        guard let entry = entry(company) else { return 0 }
        return Self.fit(title, genreWords: genreWords, entry: entry, quality: TitleMatch.quality(title)).score
    }

    private static func fit(_ title: TitleFeatures, genreWords: [String], entry: Entry, quality: Double?) -> (score: Double, positive: Double) {
        var positive = 0.0
        var negative = 0.0
        for effect in entry.effects where genreWords.contains(where: { $0.hasPrefix(effect.stem) }) {
            if effect.weight > 0 {
                if let minimum = effect.minQuality, (quality ?? 0) < minimum { continue }
                positive = max(positive, effect.weight)
            } else {
                negative += effect.weight
            }
        }
        if let minimum = entry.rules.minQuality, let quality, quality < minimum { positive *= 0.5 }
        var score = positive + negative
        if let boost = entry.rules.qualityBoost, let quality {
            score += boost * min(1, max(0, (quality - 5) / 4))
        }
        if let boost = entry.rules.popularityBoost {
            let votes = Double(max(title.kpVotes ?? 0, title.imdbVotes ?? 0, title.siteVotes ?? 0))
            if votes > 0 { score += boost * min(1, log10(votes + 1) / 6) }
        }
        return (score, positive)
    }

    // MARK: - Hard rules

    /// The hard limits a mood set and a company bring: the strictest age, the excluded genres, the longest film.
    func rules(moods: [Mood: Double], company: Company?) -> Rules {
        var combined = Rules()
        var entries: [Entry] = []
        for mood in Mood.allCases where (moods[mood] ?? 0) >= 0.5 {
            if let entry = entry(mood) { entries.append(entry) }
        }
        if let company, let entry = entry(company) { entries.append(entry) }
        for entry in entries {
            if let age = entry.rules.maxAge { combined.maxAge = min(combined.maxAge ?? age, age) }
            if let minutes = entry.rules.maxDurationMin {
                combined.maxDurationMin = min(combined.maxDurationMin ?? minutes, minutes)
            }
            combined.excludeStems += entry.rules.excludeStems.filter { !combined.excludeStems.contains($0) }
        }
        return combined
    }
}

extension MoodMap {
    public static let builtIn = MoodMap(
        version: 1,
        moods: [
            Mood.laugh.rawValue: Entry(effects: [
                Effect(stem: "комеди", weight: 1), Effect(stem: "комедийн", weight: 1), Effect(stem: "ситком", weight: 1),
                Effect(stem: "мульт", weight: 0.4), Effect(stem: "анимац", weight: 0.4),
                Effect(stem: "ужас", weight: -1), Effect(stem: "хоррор", weight: -1), Effect(stem: "драм", weight: -0.3),
            ]),
            Mood.tension.rawValue: Entry(effects: [
                Effect(stem: "триллер", weight: 1), Effect(stem: "детектив", weight: 0.9),
                Effect(stem: "криминал", weight: 0.8), Effect(stem: "боевик", weight: 0.6),
            ]),
            Mood.think.rawValue: Entry(effects: [
                Effect(stem: "драм", weight: 0.6), Effect(stem: "документ", weight: 0.8),
                Effect(stem: "фантаст", weight: 0.6, minQuality: 7), Effect(stem: "биограф", weight: 0.5),
                Effect(stem: "истор", weight: 0.4),
            ], rules: Rules(qualityBoost: 0.3)),
            Mood.cozy.rawValue: Entry(effects: [
                Effect(stem: "семей", weight: 1), Effect(stem: "детск", weight: 0.8), Effect(stem: "комеди", weight: 0.8),
                Effect(stem: "мелодрам", weight: 0.6), Effect(stem: "мульт", weight: 0.6), Effect(stem: "анимац", weight: 0.6),
                Effect(stem: "ужас", weight: -1), Effect(stem: "хоррор", weight: -1), Effect(stem: "триллер", weight: -0.5),
                Effect(stem: "боевик", weight: -0.3), Effect(stem: "криминал", weight: -0.3), Effect(stem: "военн", weight: -0.4),
            ], rules: Rules(maxAge: 16, minQuality: 7)),
            Mood.cry.rawValue: Entry(effects: [
                Effect(stem: "драм", weight: 1), Effect(stem: "мелодрам", weight: 0.9),
            ]),
            Mood.scare.rawValue: Entry(effects: [
                Effect(stem: "ужас", weight: 1), Effect(stem: "хоррор", weight: 1), Effect(stem: "мистик", weight: 0.7),
                Effect(stem: "мистич", weight: 0.7), Effect(stem: "триллер", weight: 0.3),
            ]),
        ],
        company: [
            Company.family.rawValue: Entry(effects: [
                Effect(stem: "семей", weight: 1), Effect(stem: "детск", weight: 0.9), Effect(stem: "мульт", weight: 0.8),
                Effect(stem: "анимац", weight: 0.8), Effect(stem: "приключен", weight: 0.6), Effect(stem: "фэнтез", weight: 0.4),
            ], rules: Rules(maxAge: 12, excludeStems: ["ужас", "хоррор", "эрот"])),
            Company.couple.rawValue: Entry(effects: [
                Effect(stem: "мелодрам", weight: 0.6), Effect(stem: "комеди", weight: 0.5),
            ], rules: Rules(popularityBoost: 0.3)),
            Company.friends.rawValue: Entry(effects: [
                Effect(stem: "комеди", weight: 0.7), Effect(stem: "боевик", weight: 0.6), Effect(stem: "ужас", weight: 0.5),
                Effect(stem: "хоррор", weight: 0.5),
            ], rules: Rules(maxDurationMin: 130)),
            Company.solo.rawValue: Entry(effects: []),
        ],
        moodWeight: 0.6,
        companyWeight: 0.35,
        similarWeight: 0.6,
        peopleWeight: 0.5,
        moodRequirementConfidence: 0.5,
    )
}
