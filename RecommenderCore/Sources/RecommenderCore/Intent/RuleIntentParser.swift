import Foundation

/// Reads a free-text request in Russian into a `WatchIntent` without any model (well under 5 ms): «лёгкое на полтора
/// часа, смотрим вдвоём» → лёгкое · до 1,5 ч · вдвоём. Titles («как «Мост»») and people («с Ди Каприо») come back as
/// queries for the app to look up in the catalogue; requests about something else («какая погода») are flagged so the
/// sheet can say what it does instead.
public enum RuleIntentParser {
    public static func parse(_ text: String, context: EngineContext) -> ParsedRequest {
        parse(text, context: context, lexicon: .current)
    }

    static func parse(_ text: String, context: EngineContext, lexicon: CompiledLexicon) -> ParsedRequest {
        var run = IntentParserRun(text: text, year: IntentCalendar.year(of: context.now), lexicon: lexicon)
        return run.parse()
    }

    /// Ways to look a typed title or name up («Интерстеллара» → also «Интерстеллар»), for the app's catalogue search.
    public static func searchVariants(for query: String) -> [String] {
        NameForms.searchVariants(query)
    }
}

/// One pass of the parser over one request.
struct IntentParserRun {
    private let text: String
    private let tokens: [IntentToken]
    private let year: Int
    private let lex: CompiledLexicon
    private var used: [Bool]

    private var kindsPositive: Set<TitleKind> = []
    private var kindsNegative: Set<TitleKind> = []
    private var kindConfidence = 0.0
    private var moods: [Mood: Double] = [:]
    private var moodConfidence = 0.0
    private var companies: [Company: Double] = [:]
    private var timeCandidates: [(budget: TimeBudget, confidence: Double)] = []
    private var genresIncluded: [String] = []
    private var genresExcluded: [String] = []
    private var countriesIncluded: Set<String> = []
    private var countriesExcluded: Set<String> = []
    private var yearFrom: Int?
    private var yearTo: Int?
    private var yearConfidence = 0.0
    private var rating: RatingFloor?
    private var ratingConfidence = 0.0
    private var wantsHighRating = false
    private var ratingSourceMention: RatingFloor.Source?
    private var familiarity: Double?
    private var similar: [String] = []
    private var similarConfidence = 0.0
    private var people: [String] = []
    private var peopleConfidence = 0.0
    private var avoid: [String] = []
    private var offTopicHits = 0
    private var matches: [LexMatch] = []

    init(text: String, year: Int, lexicon: CompiledLexicon) {
        self.text = text
        self.tokens = IntentTokenizer.tokenize(text)
        self.year = year
        self.lex = lexicon
        self.used = Array(repeating: false, count: tokens.count)
    }

    mutating func parse() -> ParsedRequest {
        extractTitles()
        extractTimes()
        extractRatings()
        extractYears()
        matchLexicon()
        applyMatches()
        extractPeople()

        let intent = buildIntent()
        if isOffTopic(intent) {
            return ParsedRequest(intent: .empty, chips: [], offTopic: true)
        }
        var chips = IntentChips.chips(for: intent, titleNames: [:], currentYear: year)
        chips += similar.map { IntentChip(id: IntentChips.similarQueryPrefix + $0, field: .similarTo, label: "как «\($0)»") }
        chips += people.map { IntentChip(id: IntentChips.personQueryPrefix + $0, field: .people, label: $0) }
        return ParsedRequest(intent: intent, chips: chips, similarQueries: similar, peopleQueries: people)
    }

    // MARK: - Helpers

    private func usable(_ index: Int) -> Bool {
        index >= 0 && index < tokens.count && !used[index] && tokens[index].quote == nil
    }

    private func sameClause(_ a: Int, _ b: Int) -> Bool {
        a >= 0 && b >= 0 && a < tokens.count && b < tokens.count && tokens[a].clause == tokens[b].clause
    }

    private mutating func consume(_ range: Range<Int>) {
        for index in range where index >= 0 && index < tokens.count { used[index] = true }
    }

    /// The original text of tokens `range` (spacing and punctuation inside kept: «Ocean's Eleven»).
    private func original(_ range: Range<Int>) -> String {
        guard let first = range.first, let last = range.last else { return "" }
        let chars = Array(text)
        let start = tokens[first].offset
        let end = min(chars.count, tokens[last].offset + tokens[last].raw.count)
        return String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A number at `index`: digits («40», «1,5») or words («сорок», «двадцать пять», «полтора», «два с половиной»).
    private func readNumber(at index: Int) -> (value: Double, length: Int)? {
        guard usable(index) else { return nil }
        var value: Double
        var length = 1
        if let number = tokens[index].number {
            guard tokens[index].numberSuffix == nil else { return nil }
            value = number
        } else if let word = lex.numbers[tokens[index].norm] {
            value = word
            // «сто двадцать», «двадцать пять».
            while usable(index + length), let next = lex.numbers[tokens[index + length].norm] {
                let isTens = value.truncatingRemainder(dividingBy: 10) == 0 && value >= 20
                guard isTens, next < (value >= 100 ? 100 : 10), next >= 1, next.rounded() == next else { break }
                value += next
                length += 1
            }
        } else if tokens[index].norm.contains("-") {
            // «полтора-два»: a range in one word; the upper end counts.
            let parts = tokens[index].norm.split(separator: "-").map(String.init)
            let values = parts.compactMap { lex.numbers[$0] }
            guard values.count == parts.count, let upper = values.max() else { return nil }
            value = upper
        } else {
            return nil
        }
        // «два с половиной».
        if usable(index + length + 1), tokens[index + length].norm == "с", tokens[index + length + 1].norm.hasPrefix("половин") {
            value += 0.5
            length += 2
        }
        return (value, length)
    }

    private func isHourWord(_ index: Int) -> Bool {
        usable(index) && CompiledLexicon.any(lex.hourWords, tokens[index])
    }

    private func isMinuteWord(_ index: Int) -> Bool {
        usable(index) && CompiledLexicon.any(lex.minuteWords, tokens[index])
    }

    /// «в 9 часов», «через 20 минут», «к 11»: a clock time or a delay, not how long to watch.
    private func isClockTime(numberAt index: Int) -> Bool {
        guard index > 0 else { return false }
        return ["в", "во", "к", "через", "после", "с", "со"].contains(tokens[index - 1].norm)
    }

    private func matchIndex(startingAt index: Int) -> Int? {
        matches.firstIndex { $0.start == index }
    }

    // MARK: - Titles: «как «Мост»», «похожее на Во все тяжкие», «что-то вроде интерстеллара»

    /// Words that end an unquoted title («как Мост, но смешнее»; «типа Шерлока на вечер»).
    private static let titleStops: Set<String> = [
        "но", "а", "и", "или", "либо", "только", "чтобы", "чтоб", "без", "кроме", "не", "на", "с", "со", "для", "от",
        "до", "где", "который", "которая", "которое", "которые", "что", "плюс", "минус", "пожалуйста", "сегодня",
        "вечером", "сейчас", "желательно", "лучше", "можно", "хочу", "хотим", "посмотреть", "смотреть", "чем", "но",
        "ну", "плиз", "please", "тоже", "только", "чтоб", "поновее", "постарше", "покороче", "подлиннее",
    ]

    private mutating func extractTitles() {
        var index = 0
        while index < tokens.count {
            guard let marker = lex.match(tokens, at: index, usable: { !used[$0] && tokens[$0].quote == nil },
                                         where: { $0 == .similarStrong || $0 == .similarWeak })
            else {
                index += 1
                continue
            }
            let strong = marker.effects.contains(.similarStrong)
            var next = marker.end
            var found = false
            // «как Во все тяжкие»: «как во» is a marker too, but here «Во» starts the title.
            if !strong, marker.length > 1, titleSpan(at: next, strong: strong, afterMarker: marker.start) == nil,
               titleSpan(at: marker.start + 1, strong: strong, afterMarker: marker.start) != nil {
                next = marker.start + 1
            }
            while let span = titleSpan(at: next, strong: strong, afterMarker: marker.start) {
                similar.append(span.title)
                similarConfidence = max(similarConfidence, span.quoted ? 0.95 : 0.8)
                consume(marker.start..<marker.end)
                consume(span.range)
                found = true
                // «как «Мост» или «Убийство»», «как Мост и Убийство».
                guard span.range.upperBound < tokens.count,
                      ["или", "и", "либо"].contains(tokens[span.range.upperBound].norm),
                      span.range.upperBound + 1 < tokens.count
                else { break }
                let after = span.range.upperBound + 1
                guard tokens[after].quote != nil || (tokens[after].isCapitalized && !tokens[after].isAbbreviation) else { break }
                consume(span.range.upperBound..<after)
                next = after
            }
            index = found ? max(index + 1, next) : index + 1
        }

        // Quoted spans nobody introduced: a title all the same («хочу что-то после «Мост»»), unless a person marker
        // stands before it.
        var quoteIndex = 0
        while quoteIndex < tokens.count {
            guard let quote = tokens[quoteIndex].quote, !used[quoteIndex] else {
                quoteIndex += 1
                continue
            }
            var end = quoteIndex
            while end < tokens.count, tokens[end].quote == quote { end += 1 }
            let title = original(quoteIndex..<end)
            if !title.isEmpty, !similar.contains(title) {
                similar.append(title)
                similarConfidence = max(similarConfidence, 0.7)
            }
            consume(quoteIndex..<end)
            quoteIndex = end
        }
    }

    private func titleSpan(at start: Int, strong: Bool, afterMarker markerStart: Int) -> (title: String, range: Range<Int>, quoted: Bool)? {
        guard start < tokens.count, !used[start] else { return nil }
        if let quote = tokens[start].quote {
            var end = start
            while end < tokens.count, tokens[end].quote == quote { end += 1 }
            let title = original(start..<end)
            return title.isEmpty ? nil : (title, start..<end, true)
        }
        guard sameClause(start, markerStart), !tokens[start].isNumber else { return nil }
        let first = tokens[start]
        if strong {
            // Lowercase is fine after «похожее на», but not a word we know («что-то вроде комедии»).
            guard first.isCapitalized || (!lex.isKnownWord(tokens, at: start) && !lex.isStopword(first)) else { return nil }
        } else {
            guard first.isCapitalized, !first.isAbbreviation, !first.sentenceStart else { return nil }
        }
        var end = start + 1
        while end < tokens.count, end - start < 6, !used[end], tokens[end].quote == nil, sameClause(end, start),
              !tokens[end].isNumber {
            let token = tokens[end]
            if Self.titleStops.contains(token.norm) { break }
            if !token.isCapitalized, lex.startsAspect(tokens, at: end) { break }
            if !token.isCapitalized, lex.isStopword(token), !["в", "во", "все", "из", "под", "над", "за", "о", "об"].contains(token.norm) {
                break
            }
            end += 1
        }
        // Trailing filler words are not part of the title.
        while end > start + 1, lex.isStopword(tokens[end - 1]), !tokens[end - 1].isCapitalized { end -= 1 }
        let title = original(start..<end)
        return title.isEmpty ? nil : (title, start..<end, false)
    }

    // MARK: - Time: «полтора часа», «минут на сорок», «до 90 минут», «полчаса»

    private mutating func addTime(_ budget: TimeBudget, confidence: Double) {
        timeCandidates.append((budget, confidence))
    }

    /// Consumes a limiter («до», «не больше») or an approximator («около») right before `start`; tells which.
    private mutating func modifiers(before start: Int) -> (limited: Bool, approximate: Bool) {
        var cursor = start
        var limited = false
        var approximate = false
        for _ in 0..<2 {
            let approx = CompiledLexicon.longestEnding(lex.approximators, tokens, before: cursor)
            if approx > 0, (cursor - approx..<cursor).allSatisfy(usable) {
                approximate = true
                consume(cursor - approx..<cursor)
                cursor -= approx
                continue
            }
            let limiter = CompiledLexicon.longestEnding(lex.limiters, tokens, before: cursor)
            if limiter > 0, (cursor - limiter..<cursor).allSatisfy(usable) {
                limited = true
                consume(cursor - limiter..<cursor)
                cursor -= limiter
                continue
            }
            break
        }
        return (limited, approximate)
    }

    private mutating func recordHours(_ hours: Double, limited: Bool) {
        guard hours > 0, hours <= 5 else { return }
        let half = hours.truncatingRemainder(dividingBy: 1) != 0
        let minutes = Int((hours * 60).rounded()) + (half ? 5 : 0)
        addTime(.maxMinutes(minutes), confidence: 0.9)
    }

    private mutating func recordMinutes(_ minutes: Double, limited: Bool, approximate: Bool) {
        guard minutes >= 5, minutes <= 300 else { return }
        let value = Int(minutes.rounded())
        if limited {
            addTime(.maxMinutes(value), confidence: 0.9)
        } else if value <= 60 {
            addTime(.episode(0...(approximate ? value + 5 : value)), confidence: 0.85)
        } else {
            addTime(.maxMinutes(approximate ? value + 5 : value), confidence: 0.85)
        }
    }

    private mutating func extractTimes() {
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard usable(index) else { continue }
            let token = tokens[index]

            // «полчаса», «пол часа».
            if CompiledLexicon.any(lex.halfHourWords, token) || (token.norm == "пол" && isHourWord(index + 1)) {
                let length = token.norm == "пол" ? 2 : 1
                let mods = modifiers(before: index)
                consume(index..<index + length)
                recordMinutes(30, limited: mods.limited, approximate: false)
                continue
            }

            if let number = readNumber(at: index), !isClockTime(numberAt: index) {
                var value = number.value
                var end = index + number.length
                // «20-30 минут», «1-2 часа»: the upper end counts.
                if let upper = readNumber(at: end), upper.value > value,
                   isHourWord(end + upper.length) || isMinuteWord(end + upper.length) {
                    value = upper.value
                    end += upper.length
                }
                if isHourWord(end) {
                    if end + 1 < tokens.count, ["ночи", "дня", "назад", "утра"].contains(tokens[end + 1].norm) { continue }
                    let mods = modifiers(before: index)
                    consume(index..<end + 1)
                    recordHours(value, limited: mods.limited)
                    index = end
                } else if isMinuteWord(end) {
                    if end + 1 < tokens.count, tokens[end + 1].norm == "назад" { continue }
                    let mods = modifiers(before: index)
                    consume(index..<end + 1)
                    recordMinutes(value, limited: mods.limited, approximate: mods.approximate)
                    index = end
                }
                continue
            }

            if isHourWord(index) {
                // «часа полтора», «часика на два».
                var next = index + 1
                if next < tokens.count, tokens[next].norm == "на" { next += 1 }
                if let number = readNumber(at: next), number.value <= 5 {
                    let mods = modifiers(before: index)
                    consume(index..<next + number.length)
                    recordHours(number.value, limited: mods.limited)
                    index = next + number.length - 1
                    continue
                }
                // «на час», «за часик».
                if ["час", "часик", "часок", "часочек"].contains(token.norm) {
                    let previous = index > 0 ? tokens[index - 1].norm : ""
                    let following = index + 1 < tokens.count ? tokens[index + 1].norm : ""
                    if ["через", "в", "к", "после", "каждый"].contains(previous) || ["ночи", "дня", "назад", "утра"].contains(following) {
                        continue
                    }
                    let mods = modifiers(before: index)
                    // «час с небольшим» ≈ 80 minutes.
                    let more = index + 2 < tokens.count && tokens[index + 1].norm == "с"
                        && tokens[index + 2].norm.hasPrefix("небольш")
                    consume(index..<index + (more ? 3 : 1))
                    if more {
                        addTime(.maxMinutes(80), confidence: 0.85)
                    } else {
                        recordHours(1, limited: mods.limited)
                    }
                }
                continue
            }

            if isMinuteWord(index) {
                // «минут на сорок», «минут 40», «минут по 20», «минут 30-40»: about that long.
                var next = index + 1
                if next < tokens.count, ["на", "по"].contains(tokens[next].norm) { next += 1 }
                if let number = readNumber(at: next) {
                    var value = number.value
                    var end = next + number.length
                    if let upper = readNumber(at: end), upper.value > value {
                        value = upper.value
                        end += upper.length
                    }
                    let mods = modifiers(before: index)
                    consume(index..<end)
                    recordMinutes(value, limited: mods.limited, approximate: true)
                    index = end - 1
                }
            }
        }
    }

    // MARK: - Rating: «КП от 7», «рейтинг выше 8», «IMDb 7+»

    private func ratingSources(at index: Int) -> (sources: [RatingFloor.Source], length: Int)? {
        guard let match = lex.match(tokens, at: index, usable: usable, where: {
            if case .rating = $0 { return true }
            return false
        }) else { return nil }
        let sources = match.effects.compactMap { effect -> RatingFloor.Source? in
            if case .rating(let source) = effect { return source }
            return nil
        }
        return (sources, match.length)
    }

    private func specific(_ a: RatingFloor.Source, _ b: RatingFloor.Source) -> RatingFloor.Source {
        a == .any ? b : a
    }

    private mutating func extractRatings() {
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard let found = ratingSources(at: index), var source = found.sources.first else { continue }
            var cursor = index + found.length
            var consumedEnd = cursor
            // Forward: comparators, a more specific source («рейтинг на кинопоиске от 7»), then the number.
            var value: Double?
            for _ in 0..<4 {
                guard cursor < tokens.count, sameClause(cursor, index) else { break }
                let comparator = CompiledLexicon.longest(lex.comparators, tokens, at: cursor)
                if comparator > 0, (cursor..<cursor + comparator).allSatisfy(usable) {
                    cursor += comparator
                    continue
                }
                if let more = ratingSources(at: cursor), let moreSource = more.sources.first {
                    source = specific(source, moreSource)
                    cursor += more.length
                    consumedEnd = cursor
                    continue
                }
                if let number = readNumber(at: cursor), validRating(number.value, source: source, percent: tokens[cursor].percent) {
                    value = number.value
                    cursor += number.length
                    consumedEnd = cursor
                    // «8 и выше».
                    if cursor + 1 < tokens.count, ["и", "или"].contains(tokens[cursor].norm),
                       ["выше", "больше", "более"].contains(tokens[cursor + 1].norm) {
                        cursor += 2
                        consumedEnd = cursor
                    }
                    // «рейтинг выше 8 на IMDb»: the source can come after the number.
                    var after = cursor
                    if after < tokens.count, ["на", "по", "в", "у"].contains(tokens[after].norm) { after += 1 }
                    if sameClause(after, index), let more = ratingSources(at: after), let moreSource = more.sources.first {
                        source = specific(source, moreSource)
                        consumedEnd = after + more.length
                    }
                }
                break
            }
            var start = index
            if value == nil {
                // Backward: «7+ на кп», «от 7 на кинопоиске», «8 по IMDb».
                var back = index - 1
                if back >= 0, ["на", "по", "в", "у"].contains(tokens[back].norm) { back -= 1 }
                if back >= 0, sameClause(back, index), let number = tokens[back].number, tokens[back].numberSuffix == nil,
                   usable(back), validRating(number, source: source, percent: tokens[back].percent) {
                    value = number
                    start = back
                    let comparator = CompiledLexicon.longestEnding(lex.comparators, tokens, before: back)
                    if comparator > 0 { start = back - comparator }
                }
            }
            if let value {
                rating = RatingFloor(source: source, value: value)
                ratingConfidence = 0.9
                consume(start..<max(consumedEnd, index + found.length))
                index = max(index, consumedEnd - 1)
            } else if source != .any {
                ratingSourceMention = source
            }
        }
    }

    private func validRating(_ value: Double, source: RatingFloor.Source, percent: Bool) -> Bool {
        if source == .rt || percent { return value >= 1 && value <= 100 }
        return value >= 1 && value <= 10
    }

    // MARK: - Years: «90-х», «2000-х», «после 2010», «до 2000», «2015–2020»

    private mutating func setYears(from: Int?, to: Int?, confidence: Double) {
        if let from { yearFrom = max(yearFrom ?? from, from) }
        if let to { yearTo = min(yearTo ?? to, to) }
        yearConfidence = max(yearConfidence, confidence)
    }

    private mutating func extractYears() {
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard usable(index), let raw = tokens[index].number, raw.rounded() == raw else { continue }
            let value = Int(raw)
            var end = index + 1
            if let suffix = tokens[index].numberSuffix {
                guard ["х", "е", "ых", "ые", "x", "s"].contains(suffix), value % 10 == 0 else { continue }
                let start: Int
                if value < 100 {
                    start = value >= 30 ? 1900 + value : 2000 + value
                } else if (1900...2090).contains(value) {
                    start = value
                } else {
                    continue
                }
                if end < tokens.count, CompiledLexicon.any(lex.yearWords, tokens[end]) { end += 1 }
                consume(index..<end)
                setYears(from: start, to: min(start + 9, year), confidence: 0.9)
                index = end - 1
                continue
            }
            guard (1900...(year + 1)).contains(value) else { continue }
            // «2015–2020», «с 2015 по 2020».
            var upper: Int?
            if end < tokens.count, let next = tokens[end].number, (1900...(year + 1)).contains(Int(next)), Int(next) > value {
                upper = Int(next)
                end += 1
            } else if end + 1 < tokens.count, tokens[end].norm == "по", let next = tokens[end + 1].number,
                      (1900...(year + 1)).contains(Int(next)), Int(next) > value {
                upper = Int(next)
                end += 2
            }
            if end < tokens.count, CompiledLexicon.any(lex.yearWords, tokens[end]) { end += 1 }
            let fromWords = CompiledLexicon.longestEnding(lex.yearFromWords, tokens, before: index)
            let toWords = CompiledLexicon.longestEnding(lex.yearToWords, tokens, before: index)
            if let upper {
                consume(index - fromWords..<end)
                setYears(from: value, to: upper, confidence: 0.9)
            } else if fromWords > 0 {
                consume(index - fromWords..<end)
                setYears(from: value, to: year, confidence: 0.9)
            } else if toWords > 0 {
                let words = (index - toWords..<index).map { tokens[$0].norm }
                let inclusive = words.contains("позже") || words.contains("позднее")
                consume(index - toWords..<end)
                setYears(from: 1900, to: inclusive ? value : value - 1, confidence: 0.9)
            } else {
                consume(index..<end)
                setYears(from: value, to: value, confidence: 0.9)
            }
            index = end - 1
        }
    }

    // MARK: - Lexicon and negation

    private mutating func matchLexicon() {
        var index = 0
        while index < tokens.count {
            if let match = lex.match(tokens, at: index, usable: usable) {
                matches.append(match)
                consume(match.start..<match.end)
                index = match.end
            } else {
                index += 1
            }
        }
    }

    private static func isGenreOrMood(_ effect: LexEffect) -> Bool {
        switch effect {
        case .genre, .mood: true
        default: false
        }
    }

    private func isNegator(_ match: LexMatch) -> Bool {
        match.effects.contains { if case .negator = $0 { return true } else { return false } }
    }

    private func isThemeNegator(_ match: LexMatch) -> Bool { match.effects.contains(.negator(theme: true)) }

    /// «ужасно смешное»: the intensifier isn't a mood when a mood or genre follows it.
    private func isIntensifierOnly(_ matchIndex: Int) -> Bool {
        let match = matches[matchIndex]
        guard match.effects.contains(.intensifier) else { return false }
        guard match.isAspect else { return true }
        if let next = self.matchIndex(startingAt: match.end), matches[next].isAspect { return true }
        // «жутко интересный»: an adjective after it, so «жутко» only says «very».
        guard match.end < tokens.count, sameClause(match.end, match.start) else { return false }
        return Self.looksLikeAdjective(tokens[match.end].norm)
    }

    private static let adjectiveEndings = ["ый", "ий", "ой", "ое", "ее", "ая", "яя", "ые", "ие", "ого", "его", "ую", "юю", "ых", "их"]

    static func looksLikeAdjective(_ word: String) -> Bool {
        word.count > 3 && adjectiveEndings.contains { word.hasSuffix($0) }
    }

    private mutating func applyMatches() {
        var negated = Set<Int>()
        var skipped = Set<Int>()
        for index in matches.indices where isIntensifierOnly(index) { skipped.insert(index) }

        for index in matches.indices where isNegator(matches[index]) {
            let negator = matches[index]
            let theme = isThemeNegator(negator)
            var cursor = negator.end
            while cursor < tokens.count, sameClause(cursor, negator.start), lex.fillers.contains(tokens[cursor].norm) {
                if let filler = matchIndex(startingAt: cursor), matches[filler].isAspect { break }
                cursor += 1
            }
            if let target = matchIndex(startingAt: cursor), sameClause(cursor, negator.start),
               matches[target].isAspect, !skipped.contains(target) {
                negated.insert(target)
                // «без тяжёлых драм»: a genre or mood right after the negated word shares the negation.
                var adjacent = matches[target].end
                while let next = matchIndex(startingAt: adjacent), sameClause(adjacent, negator.start),
                      matches[next].effects.contains(where: Self.isGenreOrMood) {
                    negated.insert(next)
                    adjacent = matches[next].end
                }
                // «без ужасов и драм», «не сериал и не аниме».
                var tail = adjacent
                while tail + 1 < tokens.count, ["и", "или", "ни"].contains(tokens[tail].norm), sameClause(tail, negator.start) {
                    var next = tail + 1
                    while next < tokens.count, lex.fillers.contains(tokens[next].norm), matchIndex(startingAt: next) == nil { next += 1 }
                    guard let more = matchIndex(startingAt: next), matches[more].isAspect else { break }
                    negated.insert(more)
                    tail = matches[more].end
                }
                continue
            }
            if theme, cursor < tokens.count, sameClause(cursor, negator.start) {
                // «без зомби», «не про вампиров», «без Ди Каприо»: a theme the lexicon doesn't know.
                let preposition = tokens[negator.end - 1].norm
                let prefix = ["про", "о", "об", "тему"].contains(preposition) ? "про " : ""
                var start = cursor
                while start < tokens.count {
                    guard let phrase = avoidPhrase(at: start, clauseOf: negator.start) else { break }
                    avoid.append(prefix + original(phrase))
                    consume(phrase)
                    guard phrase.upperBound + 1 < tokens.count, ["и", "или", "ни"].contains(tokens[phrase.upperBound].norm) else { break }
                    start = phrase.upperBound + 1
                }
                continue
            }
            // «ужасы не надо», «сериалы не предлагай»: the negation looks back.
            let verbFollows = matchIndex(startingAt: negator.end).map { matches[$0].effects.contains(.negationVerb) } ?? false
            if verbFollows || cursor >= tokens.count || !sameClause(cursor, negator.start) {
                if let target = matches.indices.last(where: {
                    $0 < index && matches[$0].isAspect && sameClause(matches[$0].start, negator.start)
                        && negator.start - matches[$0].end <= 3 && !negated.contains($0)
                }) {
                    negated.insert(target)
                }
            }
        }

        for index in matches.indices where !skipped.contains(index) {
            apply(matches[index], negated: negated.contains(index))
        }
    }

    /// Up to three unknown words after a theme negator, as typed.
    private func avoidPhrase(at start: Int, clauseOf anchor: Int) -> Range<Int>? {
        var end = start
        while end < tokens.count, end - start < 3, sameClause(end, anchor), !used[end], tokens[end].quote == nil,
              !tokens[end].isNumber {
            let token = tokens[end]
            if ["и", "или", "ни", "но", "а"].contains(token.norm) { break }
            if lex.isStopword(token), !token.isCapitalized { break }
            end += 1
        }
        guard end > start else { return nil }
        // «но не глупое»: a lone adjective is a quality, not a theme to filter by.
        if (start..<end).allSatisfy({ !tokens[$0].isCapitalized && Self.looksLikeAdjective(tokens[$0].norm) }) { return nil }
        return start..<end
    }

    private mutating func apply(_ match: LexMatch, negated: Bool) {
        let lexicon = lex.lexicon
        for effect in match.effects {
            switch effect {
            case .kind(let kind, let confidence):
                if negated {
                    kindsNegative.insert(kind)
                    kindConfidence = max(kindConfidence, 0.8)
                } else {
                    kindsPositive.insert(kind)
                    kindConfidence = max(kindConfidence, confidence)
                }
            case .mood(let mood):
                guard let entry = lexicon.mood(mood) else { continue }
                if negated {
                    applyMoodNegation(entry.negation)
                } else {
                    moods[mood] = 1
                    moodConfidence = max(moodConfidence, 0.85)
                }
            case .genre(let id):
                guard let entry = lexicon.genre(id) else { continue }
                if negated {
                    if !genresExcluded.contains(id) { genresExcluded.append(id) }
                } else if let mood = entry.mood {
                    moods[mood] = 1
                    moodConfidence = max(moodConfidence, 0.9)
                } else if !genresIncluded.contains(id) {
                    genresIncluded.append(id)
                }
            case .company(let company):
                guard !negated else { continue }
                if company == .solo, !isSolo(match) { continue }
                companies[company] = company == .solo ? 0.75 : 0.9
            case .countryGroup(let id):
                guard let group = lexicon.countryGroups.first(where: { $0.id == id }) else { continue }
                if negated {
                    countriesExcluded.formUnion(group.members)
                } else {
                    countriesIncluded.formUnion(group.members)
                }
            case .era(let id):
                guard let era = lexicon.eras.first(where: { $0.id == id }) else { continue }
                applyEra(era, negated: negated)
            case .time(let word):
                applyTimeWord(word, negated: negated)
            case .rating(let source):
                if source != .any { ratingSourceMention = source }
            case .highRating:
                if !negated { wantsHighRating = true }
            case .familiar:
                familiarity = 0
            case .discover:
                familiarity = 1
            case .offTopic:
                offTopicHits += 1
            case .negator, .negationVerb, .intensifier, .ignored, .similarStrong, .similarWeak, .personInstrumental,
                 .personGenitive, .personNominative:
                break
            }
        }
    }

    private mutating func applyMoodNegation(_ negation: Lexicon.MoodNegation) {
        for genre in negation.exclude where !genresExcluded.contains(genre) { genresExcluded.append(genre) }
        if let mood = negation.mood {
            moods[mood] = max(moods[mood] ?? 0, 0.6)
            moodConfidence = max(moodConfidence, 0.6)
        }
    }

    /// «один»/«одна» is the company only when it stands alone («смотрю один», «я одна дома»), not as a number
    /// («один фильм», «одна серия»).
    private func isSolo(_ match: LexMatch) -> Bool {
        let word = tokens[match.start].norm
        guard word == "один" || word == "одна" else { return true }
        let previous = match.start > 0 ? tokens[match.start - 1].norm : ""
        if ["я", "сегодня", "смотрю", "буду", "сижу", "дома", "остался", "осталась", "совсем"].contains(previous) { return true }
        let next = match.end
        guard next < tokens.count, sameClause(next, match.start) else { return true }
        return ["дома", "сегодня", "вечером", "ночью", "смотрю", "смотреть", "буду", "посмотрю", "и", "но", "а", "хочу",
                "сижу", "остался", "осталась", "без"].contains(tokens[next].norm)
    }

    private mutating func applyEra(_ era: Lexicon.EraEntry, negated: Bool) {
        if negated {
            if let from = era.negatedFrom { setYears(from: from, to: year, confidence: 0.7) }
            if let to = era.negatedTo { setYears(from: 1900, to: to, confidence: 0.7) }
            if let back = era.negatedToYearsBack { setYears(from: 1900, to: year - back, confidence: 0.7) }
            if !era.countries.isEmpty, era.negatedFrom == nil { countriesExcluded.formUnion(era.countries) }
            return
        }
        if let back = era.yearsBack {
            setYears(from: year - back, to: year, confidence: 0.75)
        } else {
            setYears(from: era.from ?? 1900, to: era.to ?? year, confidence: era.countries.isEmpty ? 0.8 : 0.9)
        }
        countriesIncluded.formUnion(era.countries)
    }

    private mutating func applyTimeWord(_ word: Lexicon.TimeWord, negated: Bool) {
        switch (word, negated) {
        case (.short, false): addTime(.maxMinutes(90), confidence: 0.7)
        case (.filmNight, false): addTime(.filmNight, confidence: 0.8)
        case (.weekendSeries, false): addTime(.weekendSeries, confidence: 0.8)
        case (.long, true): addTime(.maxMinutes(90), confidence: 0.7)
        case (.hourLong, false): addTime(.maxMinutes(60), confidence: 0.85)
        case (.hourAndHalfLong, false): addTime(.maxMinutes(95), confidence: 0.85)
        case (.twoHoursLong, false): addTime(.maxMinutes(120), confidence: 0.85)
        default: break
        }
    }

    // MARK: - People: «Нолан», «с Ди Каприо», «режиссёр Финчер», «с Томом Харди»

    private func personMarker(before start: Int) -> NameForms.Case? {
        for length in stride(from: 3, through: 1, by: -1) where start - length >= 0 {
            guard sameClause(start - length, start) else { continue }
            if let match = lex.match(tokens, at: start - length, usable: { _ in true }, where: {
                $0 == .personInstrumental || $0 == .personGenitive || $0 == .personNominative
            }), match.end == start {
                if match.effects.contains(.personNominative) { return .nominative }
                if match.effects.contains(.personInstrumental) { return .instrumental }
                return .genitive
            }
        }
        return nil
    }

    /// Endings of Russian adjectives and verbs: a capitalised first word with one is the sentence, not a name.
    private static let nonNameEndings = [
        "ть", "ться", "тся", "йте", "ите", "ся", "сь", "ое", "ая", "ые", "ие", "ий", "ый", "ой", "ее", "ую", "юю",
        "ого", "его", "ешь", "ишь", "ем", "им",
    ]

    private func looksLikeName(_ token: IntentToken) -> Bool {
        guard token.raw.count >= 3, !token.isAbbreviation, !lex.isStopword(token) else { return false }
        // Surnames like «Тарковский», «Кончаловский» look like adjectives but are names.
        if token.norm.hasSuffix("ский") || token.norm.hasSuffix("цкий") { return true }
        return !Self.nonNameEndings.contains { token.norm.hasSuffix($0) }
    }

    private mutating func extractPeople() {
        var index = 0
        while index < tokens.count {
            guard usable(index), tokens[index].isCapitalized, !tokens[index].isNumber, !tokens[index].isAbbreviation,
                  !lex.isStopword(tokens[index])
            else {
                index += 1
                continue
            }
            var end = index + 1
            while end < tokens.count, usable(end), sameClause(end, index) {
                if tokens[end].isCapitalized, !tokens[end].isAbbreviation {
                    end += 1
                } else if lex.isParticle(tokens[end]), end + 1 < tokens.count, usable(end + 1), tokens[end + 1].isCapitalized {
                    end += 2
                } else {
                    break
                }
            }
            let marker = personMarker(before: index)
            let first = tokens[index]
            let accepted: Bool
            if marker != nil {
                accepted = true
            } else if !first.sentenceStart {
                accepted = true
            } else {
                accepted = looksLikeName(first) && (end - index >= 2 || !lex.isKnownWord(tokens, at: index))
            }
            if accepted {
                let name = NameForms.nominative(original(index..<end), from: marker ?? .nominative)
                if !people.contains(name) { people.append(name) }
                peopleConfidence = max(peopleConfidence, marker != nil ? 0.85 : (first.sentenceStart ? 0.55 : 0.7))
                consume(index..<end)
            }
            index = end
        }
    }

    // MARK: - The result

    /// «2+2», «15 * 4», «x = 3»: sums, not a film request.
    private var hasArithmetic: Bool {
        text.range(of: #"\d\s*[*/×÷=]\s*\d|\d\+\d|\d \+ \d"#, options: .regularExpression) != nil
    }

    private func isOffTopic(_ intent: WatchIntent) -> Bool {
        let understood = intent.kinds != nil || !intent.moods.isEmpty || intent.company != nil || intent.time != nil
            || !intent.genres.isEmpty || !intent.countries.isEmpty || intent.years != nil || intent.minRating != nil
            || intent.familiarity != nil || !intent.avoid.isEmpty || !similar.isEmpty || !people.isEmpty
        if understood { return false }
        return offTopicHits > 0 || hasArithmetic
    }

    private func buildIntent() -> WatchIntent {
        var confidence: [WatchIntent.Field: Double] = [:]

        var kinds: Set<TitleKind>?
        if !kindsPositive.isEmpty {
            kinds = kindsPositive.subtracting(kindsNegative)
        } else if !kindsNegative.isEmpty {
            kinds = Set(TitleKind.allCases).subtracting(kindsNegative)
        }
        if kinds?.isEmpty == true { kinds = nil }
        if kinds != nil { confidence[.kinds] = kindConfidence }

        var time = timeCandidates.max { $0.confidence < $1.confidence }
        if let chosen = time {
            switch chosen.budget {
            case .filmNight where kinds == [.series]:
                // «сериал на вечер»: an evening of episodes, not a film night.
                time = nil
            case .weekendSeries where kinds == [.film]:
                // «фильм на выходные».
                time = (.filmNight, chosen.confidence)
            default:
                break
            }
        }
        if let time { confidence[.time] = time.confidence }

        let company = [Company.family, .friends, .couple, .solo].first { companies[$0] != nil }
        if let company { confidence[.company] = companies[company] }
        if !moods.isEmpty { confidence[.moods] = moodConfidence }

        let excludedGenres = Set(genresExcluded)
        let genres = Facets(include: Set(genresIncluded).subtracting(excludedGenres), exclude: excludedGenres)
        if !genres.isEmpty { confidence[.genres] = 0.9 }
        let countries = Facets(include: countriesIncluded.subtracting(countriesExcluded), exclude: countriesExcluded)
        if !countries.isEmpty { confidence[.countries] = 0.9 }

        var years: ClosedRange<Int>?
        if yearFrom != nil || yearTo != nil {
            let from = yearFrom ?? 1900
            let to = yearTo ?? year
            if from <= to { years = from...to }
        }
        if years != nil { confidence[.years] = yearConfidence }

        var minRating = rating
        if minRating == nil, wantsHighRating {
            minRating = RatingFloor(source: ratingSourceMention ?? .any, value: lex.lexicon.highRatingValue)
        }
        if minRating != nil { confidence[.minRating] = rating != nil ? ratingConfidence : 0.7 }
        if familiarity != nil { confidence[.familiarity] = 0.8 }
        if !similar.isEmpty { confidence[.similarTo] = similarConfidence }
        if !people.isEmpty { confidence[.people] = peopleConfidence }
        if !avoid.isEmpty { confidence[.avoid] = 0.85 }

        let leftover = tokens.indices
            .filter { !used[$0] && !tokens[$0].isNumber && !lex.isStopword(tokens[$0]) }
            .map { tokens[$0].raw }
        return WatchIntent(
            kinds: kinds, moods: moods, company: company, time: time?.budget, genres: genres, countries: countries,
            years: years, minRating: minRating, familiarity: familiarity, similarTo: [], people: [], avoid: avoid,
            freeText: leftover.isEmpty ? nil : leftover.joined(separator: " "), confidence: confidence,
        )
    }
}
