import Foundation

/// The default intent for the moment, so the card is ready the second the sheet opens (the plan's §4.9):
/// - weekday evening (Sun–Thu, 19:00–23:29): a film up to 110 minutes or an episode; after 21:00 up to 90 minutes;
/// - Friday and Saturday from 19:00: a film night;
/// - after 23:30 (and until 5:00): an episode of 20–45 minutes;
/// - daytime: something light and short.
///
/// Every field it sets has low confidence (0.3), so anything the user types or taps wins (`IntentMerge`).
public enum ContextDefaults {
    public static let confidence = 0.3

    public static func intent(for context: EngineContext) -> WatchIntent {
        let minutes = context.hour * 60 + context.minute
        var intent = WatchIntent()
        if minutes >= 23 * 60 + 30 || context.hour < 5 {
            intent.time = .episode(20...45)
        } else if context.hour >= 19 {
            if context.weekday == 5 || context.weekday == 6 {
                intent.time = .filmNight
            } else {
                intent.time = .maxMinutes(context.hour >= 21 ? 90 : 110)
            }
        } else {
            intent.time = .maxMinutes(90)
            intent.moods = [.cozy: 0.5]
            intent.confidence[.moods] = confidence
        }
        intent.confidence[.time] = confidence
        return intent
    }
}

/// Puts what the user said over what was there (the context defaults, or the previous turn): a field the user set
/// replaces the old one unless the old one was surer; exclusions and themes to avoid add up.
public enum IntentMerge {
    public static func merge(_ update: WatchIntent, over base: WatchIntent) -> WatchIntent {
        var result = base
        func wins(_ field: WatchIntent.Field) -> Bool {
            (update.confidence[field] ?? 0.5) >= (base.confidence[field] ?? 0)
        }
        func take(_ field: WatchIntent.Field) {
            if let value = update.confidence[field] { result.confidence[field] = value }
        }
        if update.kinds != nil, wins(.kinds) { result.kinds = update.kinds; take(.kinds) }
        if !update.moods.isEmpty, wins(.moods) { result.moods = update.moods; take(.moods) }
        if update.company != nil, wins(.company) { result.company = update.company; take(.company) }
        if update.time != nil, wins(.time) { result.time = update.time; take(.time) }
        if !update.genres.isEmpty {
            result.genres.exclude = result.genres.exclude.subtracting(update.genres.include).union(update.genres.exclude)
            result.genres.include = result.genres.include.subtracting(update.genres.exclude).union(update.genres.include)
            take(.genres)
        }
        if !update.countries.isEmpty {
            result.countries.exclude = result.countries.exclude.subtracting(update.countries.include)
                .union(update.countries.exclude)
            result.countries.include = result.countries.include.subtracting(update.countries.exclude)
                .union(update.countries.include)
            take(.countries)
        }
        if update.years != nil, wins(.years) { result.years = update.years; take(.years) }
        if update.minRating != nil, wins(.minRating) { result.minRating = update.minRating; take(.minRating) }
        if update.familiarity != nil { result.familiarity = update.familiarity; take(.familiarity) }
        if !update.similarTo.isEmpty { result.similarTo = update.similarTo; take(.similarTo) }
        if !update.people.isEmpty { result.people = update.people; take(.people) }
        for term in update.avoid where !result.avoid.contains(term) { result.avoid.append(term) }
        if !update.avoid.isEmpty { take(.avoid) }
        if update.freeText != nil { result.freeText = update.freeText }
        return result
    }
}

/// The critique buttons under the pick (the plan's §4.9): each turns the intent a notch.
public enum CritiqueOps {
    public static func apply(_ critique: Critique, to intent: WatchIntent, current: TitleFeatures?, context: EngineContext) -> WatchIntent {
        var result = intent
        let year = IntentCalendar.year(of: context.now)
        switch critique {
        case .lighter:
            // «Полегче»: no thrillers or horror, more comedy and family films; «уютное» also caps the age at 16+.
            for mood in [Mood.tension, .scare, .cry] { result.moods[mood] = nil }
            result.moods[.cozy] = max(result.moods[.cozy] ?? 0, 0.8)
            result.moods[.laugh] = max(result.moods[.laugh] ?? 0, 0.5)
            result.genres.include.subtract(["триллер", "ужасы"])
            result.genres.exclude.formUnion(["триллер", "ужасы"])
            result.confidence[.moods] = 1
            result.confidence[.genres] = 1
        case .darker:
            // «Помрачнее»: the opposite — tension and drama, no family films.
            for mood in [Mood.cozy, .laugh] { result.moods[mood] = nil }
            result.moods[.tension] = max(result.moods[.tension] ?? 0, 0.8)
            result.moods[.cry] = max(result.moods[.cry] ?? 0, 0.4)
            result.genres.exclude.subtract(["триллер", "ужасы", "драма"])
            result.genres.include.subtract(["комедия", "семейный", "мультфильм"])
            result.genres.exclude.insert("семейный")
            result.confidence[.moods] = 1
            result.confidence[.genres] = 1
        case .shorter:
            result.time = shorter(than: current, time: intent.time)
            if case .episode = result.time, result.kinds == [.film] { result.kinds = nil }
            result.confidence[.time] = 1
        case .newer:
            let base = baseYear(current: current, intent: intent, currentYear: year)
            let from = min(base + 1, year)
            result.years = from...year
            result.confidence[.years] = 1
        case .older:
            let base = baseYear(current: current, intent: intent, currentYear: year)
            result.years = 1900...max(1900, base - 1)
            result.confidence[.years] = 1
        case .notAbout(let term):
            result = notAbout(term, in: result)
        case .moreLikeThis:
            if let current {
                result.similarTo = [current.id]
                result.confidence[.similarTo] = 1
            }
        }
        return result
    }

    /// «Покороче»: a quarter shorter than what's on screen, or an episode once that's under an hour.
    private static func shorter(than current: TitleFeatures?, time: TimeBudget?) -> TimeBudget {
        func cut(_ minutes: Int) -> TimeBudget {
            let target = Int((Double(minutes) * 0.75).rounded())
            return target >= 60 ? .maxMinutes(target) : .episode(0...max(20, target))
        }
        if let current {
            let minutes = TitleTiming.minutes(of: current).value
            if current.isSeries { return .episode(0...max(15, Int((Double(minutes) * 0.75).rounded()))) }
            return cut(minutes)
        }
        switch time {
        case .maxMinutes(let minutes): return cut(minutes)
        case .episode(let range): return .episode(0...max(15, Int((Double(range.upperBound) * 0.75).rounded())))
        case .filmNight: return .maxMinutes(100)
        case .weekendSeries: return .episode(0...45)
        case nil: return .maxMinutes(90)
        }
    }

    private static func baseYear(current: TitleFeatures?, intent: WatchIntent, currentYear: Int) -> Int {
        if let year = current?.year { return year }
        if let years = intent.years { return (years.lowerBound + years.upperBound) / 2 }
        return currentYear - 10
    }

    /// «Не про…»: a genre, a mood, a kind or a country the lexicon knows is excluded as such; anything else becomes a
    /// theme to avoid in genres and names.
    static func notAbout(_ term: String, in intent: WatchIntent, lexicon: CompiledLexicon = .current) -> WatchIntent {
        var result = intent
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }
        let tokens = IntentTokenizer.tokenize(trimmed)
        var understood = false
        var index = 0
        while index < tokens.count {
            guard let match = lexicon.match(tokens, at: index, usable: { _ in true }) else {
                index += 1
                continue
            }
            index = match.end
            for effect in match.effects {
                switch effect {
                case .genre(let id):
                    result.genres.include.remove(id)
                    result.genres.exclude.insert(id)
                    if let mood = lexicon.lexicon.genre(id)?.mood { result.moods[mood] = nil }
                    result.confidence[.genres] = 1
                    understood = true
                case .mood(let mood):
                    result.moods[mood] = nil
                    if let negation = lexicon.lexicon.mood(mood)?.negation {
                        result.genres.exclude.formUnion(negation.exclude)
                        result.genres.include.subtract(negation.exclude)
                    }
                    result.confidence[.genres] = 1
                    understood = true
                case .kind(let kind, _):
                    var kinds = result.kinds ?? Set(TitleKind.allCases)
                    kinds.remove(kind)
                    result.kinds = kinds.isEmpty ? nil : kinds
                    result.confidence[.kinds] = 1
                    understood = true
                case .countryGroup(let id):
                    if let group = lexicon.lexicon.countryGroups.first(where: { $0.id == id }) {
                        result.countries.include.subtract(group.members)
                        result.countries.exclude.formUnion(group.members)
                        result.confidence[.countries] = 1
                        understood = true
                    }
                default:
                    break
                }
            }
        }
        if !understood {
            let lower = IntentText.normalize(trimmed)
            let hasPreposition = lower.hasPrefix("про ") || lower.hasPrefix("о ") || lower.hasPrefix("об ")
            let phrase = hasPreposition ? trimmed : "про \(trimmed)"
            if !result.avoid.contains(phrase) { result.avoid.append(phrase) }
            result.confidence[.avoid] = 1
        }
        return result
    }
}

/// «Понял так» chips for an intent, and removing one (the chip's × button).
public enum IntentChips {
    /// Chips for «как X» and people the parser found but the catalogue hasn't resolved yet; removing them leaves the
    /// intent as is (the app drops the query).
    public static let similarQueryPrefix = "similarq:"
    public static let personQueryPrefix = "personq:"

    public static func chips(for intent: WatchIntent) -> [IntentChip] {
        chips(for: intent, titleNames: [:], currentYear: IntentCalendar.year(of: Date().timeIntervalSince1970))
    }

    /// Chips in reading order: mood, time, company, kind, genres, countries, years, rating, «как X», people, then
    /// exclusions. `titleNames` turns `similarTo` ids into «как «Мост»».
    public static func chips(for intent: WatchIntent, titleNames: [String: String], currentYear: Int) -> [IntentChip] {
        let lexicon = Lexicon.current
        var chips: [IntentChip] = []
        for mood in Mood.allCases where (intent.moods[mood] ?? 0) > 0 {
            chips.append(IntentChip(id: "mood:\(mood.rawValue)", field: .moods, label: lexicon.mood(mood)?.label ?? mood.rawValue))
        }
        if let time = intent.time {
            chips.append(IntentChip(id: "time", field: .time, label: IntentLabels.timeChip(time)))
        }
        if let company = intent.company {
            let label = lexicon.company.first { $0.company == company }?.label ?? company.rawValue
            chips.append(IntentChip(id: "company", field: .company, label: label))
        }
        if let kinds = intent.kinds, !kinds.isEmpty, kinds.count < TitleKind.allCases.count {
            chips.append(IntentChip(id: "kinds", field: .kinds, label: IntentLabels.kinds(kinds)))
        }
        for id in intent.genres.include.sorted() {
            chips.append(IntentChip(id: "genre+:\(id)", field: .genres, label: lexicon.genre(id)?.label ?? id))
        }
        for group in countryGroups(intent.countries.include, lexicon: lexicon) {
            chips.append(IntentChip(id: "country+:\(group.id)", field: .countries, label: group.label))
        }
        let sovietYears = intent.years == 1900...1991 && intent.countries.include.contains("СССР")
        if let years = intent.years, !sovietYears {
            chips.append(IntentChip(id: "years", field: .years, label: IntentLabels.years(years, currentYear: currentYear)))
        }
        if let floor = intent.minRating {
            chips.append(IntentChip(id: "rating", field: .minRating, label: IntentLabels.rating(floor)))
        }
        for id in intent.similarTo {
            let label = titleNames[id].map { "как «\($0)»" } ?? "похожее на выбранное"
            chips.append(IntentChip(id: "similar:\(id)", field: .similarTo, label: label))
        }
        for person in intent.people {
            chips.append(IntentChip(id: "person:\(person.id)", field: .people, label: person.name))
        }
        for id in intent.genres.exclude.sorted() {
            chips.append(IntentChip(id: "genre-:\(id)", field: .genres, label: lexicon.genre(id)?.without ?? "без \(id)"))
        }
        for group in countryGroups(intent.countries.exclude, lexicon: lexicon) {
            chips.append(IntentChip(id: "country-:\(group.id)", field: .countries, label: "не \(group.label)"))
        }
        for term in intent.avoid {
            chips.append(IntentChip(id: "avoid:\(term)", field: .avoid, label: IntentLabels.avoid(term)))
        }
        if let familiarity = intent.familiarity {
            if familiarity <= 0.2 {
                chips.append(IntentChip(id: "familiarity", field: .familiarity, label: "из своего"))
            } else if familiarity >= 0.8 {
                chips.append(IntentChip(id: "familiarity", field: .familiarity, label: "открытия"))
            }
        }
        return chips
    }

    public static func removing(_ chip: IntentChip, from intent: WatchIntent) -> WatchIntent {
        var result = intent
        let id = chip.id
        func value(after prefix: String) -> String? { id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : nil }

        if id == "kinds" {
            result.kinds = nil
        } else if let raw = value(after: "mood:"), let mood = Mood(rawValue: raw) {
            result.moods[mood] = nil
        } else if id == "time" {
            result.time = nil
        } else if id == "company" {
            result.company = nil
        } else if let genre = value(after: "genre+:") {
            result.genres.include.remove(genre)
        } else if let genre = value(after: "genre-:") {
            result.genres.exclude.remove(genre)
        } else if let group = value(after: "country+:") {
            result.countries.include.subtract(members(of: group))
            if group == "ussr", result.years == 1900...1991 { result.years = nil }
        } else if let group = value(after: "country-:") {
            result.countries.exclude.subtract(members(of: group))
        } else if id == "years" {
            result.years = nil
        } else if id == "rating" {
            result.minRating = nil
        } else if id == "familiarity" {
            result.familiarity = nil
        } else if let titleId = value(after: "similar:") {
            result.similarTo.removeAll { $0 == titleId }
        } else if let personId = value(after: "person:") {
            result.people.removeAll { $0.id == personId }
        } else if let term = value(after: "avoid:") {
            result.avoid.removeAll { $0 == term }
        }
        dropEmptyConfidence(&result)
        return result
    }

    // MARK: - Countries as the user said them

    private struct CountryChip {
        var id: String
        var label: String
    }

    /// Groups countries back into what the user said: all five Scandinavian countries are «скандинавское», one is
    /// «шведское», an unknown country is its own name.
    private static func countryGroups(_ names: Set<String>, lexicon: Lexicon) -> [CountryChip] {
        var remaining = names
        var chips: [CountryChip] = []
        let groups = lexicon.countryGroups.enumerated()
            .sorted { ($0.element.members.count, -$0.offset) > ($1.element.members.count, -$1.offset) }
            .map(\.element)
        for group in groups where group.members.count > 1 && Set(group.members).isSubset(of: remaining) {
            chips.append(CountryChip(id: group.id, label: group.label))
            remaining.subtract(group.members)
        }
        for name in remaining.sorted() {
            if let single = groups.first(where: { $0.members == [name] }) {
                chips.append(CountryChip(id: single.id, label: single.label))
            } else {
                chips.append(CountryChip(id: name, label: name))
            }
        }
        return chips
    }

    private static func members(of group: String) -> [String] {
        Lexicon.current.countryGroups.first { $0.id == group }?.members ?? [group]
    }

    private static func dropEmptyConfidence(_ intent: inout WatchIntent) {
        let empty: [WatchIntent.Field: Bool] = [
            .kinds: intent.kinds == nil, .moods: intent.moods.isEmpty, .company: intent.company == nil,
            .time: intent.time == nil, .genres: intent.genres.isEmpty, .countries: intent.countries.isEmpty,
            .years: intent.years == nil, .minRating: intent.minRating == nil, .familiarity: intent.familiarity == nil,
            .similarTo: intent.similarTo.isEmpty, .people: intent.people.isEmpty, .avoid: intent.avoid.isEmpty,
        ]
        for (field, isEmpty) in empty where isEmpty { intent.confidence[field] = nil }
    }
}
