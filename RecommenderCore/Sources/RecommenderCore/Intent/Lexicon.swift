import Foundation

/// The rules parser's vocabulary: which Russian words mean a kind, a mood, a genre, company, a country, an era, a time
/// budget, a rating source, a negation… Shared with the TV (`Resources/lexicon_ru.json`), and compiled into the app
/// (`Lexicon.builtIn`) so parsing works even if the resource is missing or broken.
///
/// A pattern is one or more words separated by spaces; a word ending in `*` matches by prefix («смешн*» → «смешное»,
/// «смешнее»), any other word matches exactly. Text is lowercased and «ё» → «е» before matching.
public struct Lexicon: Codable, Sendable, Hashable {
    public struct KindEntry: Codable, Sendable, Hashable {
        public var kind: TitleKind
        public var patterns: [String]
        /// «серию» says «series» less surely than «сериал».
        public var confidence: Double
    }

    /// What «не» does to a mood: «не страшное» → no horror; «не напряжное» → something light.
    public struct MoodNegation: Codable, Sendable, Hashable {
        public var exclude: [String]
        public var mood: Mood?
    }

    public struct MoodEntry: Codable, Sendable, Hashable {
        public var mood: Mood
        /// The chip («посмеяться», «лёгкое»).
        public var label: String
        public var patterns: [String]
        public var negation: MoodNegation
    }

    public struct GenreEntry: Codable, Sendable, Hashable {
        /// The facet value the parser writes («фантастика»).
        public var id: String
        /// The chip when included («фантастика»).
        public var label: String
        /// The chip when excluded («без фантастики»).
        public var without: String
        /// Stems the site's genre names are matched by («фантаст» → «Фантастика», «Научная фантастика»).
        public var stems: [String]
        public var patterns: [String]
        /// Genre words that are really a mood («комедию» → посмеяться): positive use sets the mood, negation excludes
        /// the genre.
        public var mood: Mood?
    }

    public struct CompanyEntry: Codable, Sendable, Hashable {
        public var company: Company
        public var label: String
        public var patterns: [String]
    }

    /// A country as the site names it, with the stems its spellings share («Корея Южная», «Южная Корея» → «коре»).
    public struct CountryEntry: Codable, Sendable, Hashable {
        public var name: String
        public var stems: [String]
    }

    /// What the user says about countries («корейское», «скандинавское» → several countries).
    public struct CountryGroup: Codable, Sendable, Hashable {
        public var id: String
        /// The chip («корейское»); negated: «не корейское».
        public var label: String
        public var members: [String]
        public var patterns: [String]
    }

    /// An era: fixed years, «the last N years» (`yearsBack`), or Soviet (years and the country).
    public struct EraEntry: Codable, Sendable, Hashable {
        public var id: String
        public var patterns: [String]
        public var from: Int?
        public var to: Int?
        /// From the current year minus this, to the current year («посвежее»).
        public var yearsBack: Int?
        public var countries: [String]
        /// «не старое» → from 2000; «не новинки» → up to the current year minus four.
        public var negatedFrom: Int?
        public var negatedTo: Int?
        public var negatedToYearsBack: Int?
    }

    public enum TimeWord: String, Codable, Sendable, Hashable {
        /// «короткое», «недолго» → up to 90 minutes.
        case short
        /// «на вечер».
        case filmNight
        /// «на выходные», «залпом», «запоем».
        case weekendSeries
        /// «длинное»: only meaningful negated («не длинное» → short).
        case long
        /// «часовое» → an hour, «полуторачасовое» → 1,5 hours.
        case hourLong
        case hourAndHalfLong
        case twoHoursLong
    }

    public struct TimeEntry: Codable, Sendable, Hashable {
        public var word: TimeWord
        public var patterns: [String]
    }

    public struct RatingEntry: Codable, Sendable, Hashable {
        public var source: RatingFloor.Source
        public var patterns: [String]
    }

    public var version: Int
    public var kinds: [KindEntry]
    public var moods: [MoodEntry]
    public var genres: [GenreEntry]
    public var company: [CompanyEntry]
    public var countries: [CountryEntry]
    public var countryGroups: [CountryGroup]
    public var eras: [EraEntry]
    public var times: [TimeEntry]
    public var ratings: [RatingEntry]
    /// «высокий рейтинг» → any rating from 7,5.
    public var highRating: [String]
    public var highRatingValue: Double
    /// «из закладок», «из своего» → familiar (0); «что-то незнакомое» → discoveries (1).
    public var familiar: [String]
    public var discover: [String]
    /// Words that start a negation («не», «без», «кроме»).
    public var negators: [String]
    /// Negators that also take a theme nobody listed («без зомби», «не про войну»).
    public var themeNegators: [String]
    /// «ужасы не надо»: a verb after «не» that turns the negation back onto the word before.
    public var negationVerbs: [String]
    /// Words skipped between a negator and what it negates («не очень страшное», «без всяких ужасов»).
    public var negationFillers: [String]
    /// «ужасно смешное»: an intensifier before a mood word is not a mood itself.
    public var intensifiers: [String]
    /// Phrases consumed and ignored («добрый вечер», «не скучное»).
    public var ignored: [String]
    /// «похожее на», «в духе», «что-то вроде»: a title follows, even in lowercase.
    public var similarStrong: [String]
    /// «как», «типа», «вроде»: a title follows only if it's capitalised or quoted.
    public var similarWeak: [String]
    /// «с Томом Харди»: the name is in the instrumental case.
    public var personInstrumental: [String]
    /// «фильмы Нолана», «от Финчера»: the genitive.
    public var personGenitive: [String]
    /// «режиссёр Финчер», «актёр Харди»: as is.
    public var personNominative: [String]
    /// Particles inside names («Леонардо ди Каприо», «Ларс фон Триер»).
    public var nameParticles: [String]
    public var offTopic: [String]
    /// Words that are never a name, a title or leftover text.
    public var stopwords: [String]
    /// Number words («сорок», «полтора»).
    public var numbers: [String: Double]
    public var hourWords: [String]
    public var minuteWords: [String]
    /// «полчаса».
    public var halfHourWords: [String]
    /// «до», «не больше»: a number of minutes after them is a ceiling, not an episode length.
    public var timeLimiters: [String]
    /// «около», «примерно»: give the number five minutes of slack.
    public var approximators: [String]
    /// Rating comparators skipped between a rating word and its number («от», «выше», «не ниже»).
    public var ratingComparators: [String]
    /// «после», «с», «начиная с» before a year → from that year.
    public var yearFrom: [String]
    /// «до» before a year → before that year.
    public var yearTo: [String]
    /// «года», «год», «г»: confirm a bare number is a year.
    public var yearWords: [String]

    /// The lexicon in use: the bundled JSON when it decodes, otherwise the compiled-in copy.
    public static let current: Lexicon = loadBundled() ?? builtIn

    /// Reads `lexicon_ru.json` from the package's resources.
    public static func loadBundled() -> Lexicon? {
        guard let url = Bundle.module.url(forResource: "lexicon_ru", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Lexicon.self, from: data)
    }

    public func genre(_ id: String) -> GenreEntry? { genres.first { $0.id == id } }
    public func mood(_ mood: Mood) -> MoodEntry? { moods.first { $0.mood == mood } }
}

// MARK: - Compiled form

/// One word of a pattern.
struct WordPattern: Sendable, Hashable {
    var text: String
    var prefix: Bool

    init(_ source: String) {
        if source.hasSuffix("*") {
            text = IntentText.normalize(String(source.dropLast()))
            prefix = true
        } else {
            text = IntentText.normalize(source)
            prefix = false
        }
    }

    func matches(_ word: String) -> Bool { prefix ? word.hasPrefix(text) : word == text }
}

/// What a lexicon match means.
enum LexEffect: Sendable, Hashable {
    case kind(TitleKind, Double)
    case mood(Mood)
    case genre(String)
    case company(Company)
    case countryGroup(String)
    case era(String)
    case time(Lexicon.TimeWord)
    case rating(RatingFloor.Source)
    case highRating
    case familiar
    case discover
    case negator(theme: Bool)
    case negationVerb
    case intensifier
    case ignored
    case similarStrong
    case similarWeak
    case personInstrumental
    case personGenitive
    case personNominative
    case offTopic

    /// Effects that say something about what to watch (not grammar).
    var isAspect: Bool {
        switch self {
        case .kind, .mood, .genre, .company, .countryGroup, .era, .time, .rating, .highRating, .familiar, .discover:
            true
        default:
            false
        }
    }
}

struct LexMatch: Sendable, Hashable {
    var start: Int
    var length: Int
    var effects: [LexEffect]

    var end: Int { start + length }
    var isAspect: Bool { effects.contains { $0.isAspect } }
}

/// The lexicon turned into patterns ready to match against tokens.
struct CompiledLexicon: Sendable {
    let lexicon: Lexicon
    private let entries: [(pattern: [WordPattern], effect: LexEffect)]
    private let exactFirst: [String: [Int]]
    private let prefixFirst: [String: [Int]]
    private let shortPrefixFirst: [String: [Int]]
    private let stopwords: Set<String>
    private let particles: Set<String>
    let fillers: Set<String>
    let numbers: [String: Double]
    let hourWords: [WordPattern]
    let minuteWords: [WordPattern]
    let halfHourWords: [WordPattern]
    let yearWords: [WordPattern]
    let limiters: [[WordPattern]]
    let approximators: [[WordPattern]]
    let comparators: [[WordPattern]]
    let yearFromWords: [[WordPattern]]
    let yearToWords: [[WordPattern]]

    static let current = CompiledLexicon(Lexicon.current)

    init(_ lexicon: Lexicon) {
        self.lexicon = lexicon
        func phrases(_ list: [String]) -> [[WordPattern]] {
            list.map { $0.split(separator: " ").map { WordPattern(String($0)) } }.filter { !$0.isEmpty }
        }
        self.fillers = Set(lexicon.negationFillers.map(IntentText.normalize))
        self.numbers = Dictionary(lexicon.numbers.map { (IntentText.normalize($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.hourWords = lexicon.hourWords.map(WordPattern.init)
        self.minuteWords = lexicon.minuteWords.map(WordPattern.init)
        self.halfHourWords = lexicon.halfHourWords.map(WordPattern.init)
        self.yearWords = lexicon.yearWords.map(WordPattern.init)
        self.limiters = phrases(lexicon.timeLimiters)
        self.approximators = phrases(lexicon.approximators)
        self.comparators = phrases(lexicon.ratingComparators)
        self.yearFromWords = phrases(lexicon.yearFrom)
        self.yearToWords = phrases(lexicon.yearTo)
        var entries: [(pattern: [WordPattern], effect: LexEffect)] = []
        func add(_ patterns: [String], _ effect: LexEffect) {
            for pattern in patterns {
                let words = pattern.split(separator: " ").map { WordPattern(String($0)) }
                if !words.isEmpty { entries.append((words, effect)) }
            }
        }
        for entry in lexicon.kinds { add(entry.patterns, .kind(entry.kind, entry.confidence)) }
        for entry in lexicon.moods { add(entry.patterns, .mood(entry.mood)) }
        for entry in lexicon.genres { add(entry.patterns, .genre(entry.id)) }
        for entry in lexicon.company { add(entry.patterns, .company(entry.company)) }
        for group in lexicon.countryGroups { add(group.patterns, .countryGroup(group.id)) }
        for era in lexicon.eras { add(era.patterns, .era(era.id)) }
        for time in lexicon.times { add(time.patterns, .time(time.word)) }
        for rating in lexicon.ratings { add(rating.patterns, .rating(rating.source)) }
        add(lexicon.highRating, .highRating)
        add(lexicon.familiar, .familiar)
        add(lexicon.discover, .discover)
        add(lexicon.themeNegators, .negator(theme: true))
        add(lexicon.negators, .negator(theme: false))
        add(lexicon.negationVerbs, .negationVerb)
        add(lexicon.intensifiers, .intensifier)
        add(lexicon.ignored, .ignored)
        add(lexicon.similarStrong, .similarStrong)
        add(lexicon.similarWeak, .similarWeak)
        add(lexicon.personInstrumental, .personInstrumental)
        add(lexicon.personGenitive, .personGenitive)
        add(lexicon.personNominative, .personNominative)
        add(lexicon.offTopic, .offTopic)
        self.entries = entries
        // Index by the first word, so a match looks at a handful of patterns instead of all of them.
        var exactFirst: [String: [Int]] = [:]
        var prefixFirst: [String: [Int]] = [:]
        var shortPrefixFirst: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            guard let word = entry.pattern.first else { continue }
            if !word.prefix {
                exactFirst[word.text, default: []].append(index)
            } else if word.text.count >= 2 {
                prefixFirst[String(word.text.prefix(2)), default: []].append(index)
            } else {
                shortPrefixFirst[word.text, default: []].append(index)
            }
        }
        self.exactFirst = exactFirst
        self.prefixFirst = prefixFirst
        self.shortPrefixFirst = shortPrefixFirst
        self.stopwords = Set(lexicon.stopwords.map(IntentText.normalize))
        self.particles = Set(lexicon.nameParticles.map(IntentText.normalize))
    }

    func isStopword(_ token: IntentToken) -> Bool { stopwords.contains(token.norm) }
    func isParticle(_ token: IntentToken) -> Bool { particles.contains(token.norm) }

    static func any(_ words: [WordPattern], _ token: IntentToken) -> Bool {
        !token.isNumber && words.contains { $0.matches(token.norm) }
    }

    /// The longest phrase from `list` that starts at `index`.
    static func longest(_ list: [[WordPattern]], _ tokens: [IntentToken], at index: Int) -> Int {
        var best = 0
        for phrase in list where phrase.count > best && index >= 0 && index + phrase.count <= tokens.count {
            if phrase.indices.allSatisfy({ phrase[$0].matches(tokens[index + $0].norm) }) { best = phrase.count }
        }
        return best
    }

    /// The longest phrase from `list` that ends right before `end` («не больше» before «90 минут»).
    static func longestEnding(_ list: [[WordPattern]], _ tokens: [IntentToken], before end: Int) -> Int {
        var best = 0
        for phrase in list where phrase.count > best && end - phrase.count >= 0 && end <= tokens.count {
            let start = end - phrase.count
            if phrase.indices.allSatisfy({ phrase[$0].matches(tokens[start + $0].norm) }) { best = phrase.count }
        }
        return best
    }

    /// The longest pattern starting at `index` (within one clause, over words not yet used), with every effect that
    /// pattern has (one phrase can mean two things: «дорама» is a series and Korean).
    func match(_ tokens: [IntentToken], at index: Int, usable: (Int) -> Bool, where filter: (LexEffect) -> Bool = { _ in true }) -> LexMatch? {
        guard index < tokens.count, usable(index), !tokens[index].isNumber else { return nil }
        let first = tokens[index].norm
        var candidates = exactFirst[first] ?? []
        candidates += prefixFirst[String(first.prefix(2))] ?? []
        candidates += shortPrefixFirst[String(first.prefix(1))] ?? []
        guard !candidates.isEmpty else { return nil }
        var bestLength = 0
        var effects: [LexEffect] = []
        for candidate in candidates.sorted() {
            let entry = entries[candidate]
            guard filter(entry.effect) else { continue }
            let length = entry.pattern.count
            guard length >= bestLength, index + length <= tokens.count else { continue }
            var ok = true
            for offset in 0..<length {
                let token = tokens[index + offset]
                if !usable(index + offset) || token.clause != tokens[index].clause || !entry.pattern[offset].matches(token.norm) {
                    ok = false
                    break
                }
            }
            guard ok else { continue }
            if length > bestLength {
                bestLength = length
                effects = [entry.effect]
            } else if !effects.contains(entry.effect) {
                effects.append(entry.effect)
            }
        }
        return bestLength > 0 ? LexMatch(start: index, length: bestLength, effects: effects) : nil
    }

    /// Whether a word starts something the lexicon knows about what to watch (a kind, a mood, a time…): titles after
    /// «как» stop there («как Мост, но смешнее»).
    func startsAspect(_ tokens: [IntentToken], at index: Int) -> Bool {
        match(tokens, at: index, usable: { _ in true }, where: { $0.isAspect }) != nil
    }

    /// Whether a single word is any lexicon word at all (aspects and grammar alike).
    func isKnownWord(_ tokens: [IntentToken], at index: Int) -> Bool {
        match(tokens, at: index, usable: { _ in true }) != nil
    }
}
