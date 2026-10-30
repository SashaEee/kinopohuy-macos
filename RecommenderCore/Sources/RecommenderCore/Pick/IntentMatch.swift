import Foundation

/// How long a title takes. List cards rarely carry the length, so a missing one is estimated from the kind (a film
/// ~105 minutes, an episode ~45, a cartoon series ~22) — good enough to tell «на 20 минут» from «фильм на вечер», and
/// marked as a guess so a known length wins a tie.
enum TitleTiming {
    static func minutes(of title: TitleFeatures) -> (value: Int, estimated: Bool) {
        if let minutes = title.durationMin, minutes > 0 { return (minutes, false) }
        let kind = TitleMatch.kind(of: title)
        switch (kind, title.isSeries) {
        case (.cartoon, true), (.anime, true): return (24, true)
        case (.cartoon, false): return (85, true)
        case (.anime, false): return (100, true)
        case (.show, _): return (50, true)
        case (_, true): return (45, true)
        case (_, false): return (105, true)
        }
    }

    /// Whether a title fits a time budget: films by their length, series by an episode («до 90 минут» lets a series
    /// with 45-minute episodes through; «серия до 45» does not let a 2-hour film through).
    static func fits(_ title: TitleFeatures, _ budget: TimeBudget) -> Bool {
        let minutes = minutes(of: title).value
        switch budget {
        case .maxMinutes(let limit):
            return minutes <= limit
        case .episode(let range):
            return minutes <= range.upperBound && (range.lowerBound <= 1 || minutes >= range.lowerBound || !title.isSeries)
        case .filmNight:
            return !title.isSeries && (70...190).contains(minutes)
        case .weekendSeries:
            return title.isSeries
        }
    }
}

/// Matching what the user said («ужасы», «Южная Корея», «не про войну») against the site's own words («Ужасы», «Корея
/// Южная», «Военные»): by lowercase stems, word by word, so plural/singular and word order don't matter.
enum TitleMatch {
    /// The title's kind, inferred from «isSeries» when the card didn't say.
    static func kind(of title: TitleFeatures) -> TitleKind {
        title.kind ?? (title.isSeries ? .series : .film)
    }

    /// Whether any word of `names` starts with one of `stems`.
    static func anyWord(of names: [String], hasPrefixIn stems: [String]) -> Bool {
        guard !stems.isEmpty else { return false }
        for name in names {
            for word in IntentText.words(name) where stems.contains(where: { word.hasPrefix($0) }) {
                return true
            }
        }
        return false
    }

    /// The stems a genre facet value is matched by: the lexicon's for known ids and genre words, else the value's own.
    static func genreStems(_ facet: String, lexicon: Lexicon = .current) -> [String] {
        let normalized = IntentText.normalize(facet)
        if let entry = lexicon.genres.first(where: { $0.id == normalized || IntentText.normalize($0.label) == normalized }) {
            return entry.stems
        }
        let words = IntentText.words(facet)
        for entry in lexicon.genres where entry.stems.contains(where: { stem in words.contains { $0.hasPrefix(stem) } }) {
            return entry.stems
        }
        return words.map(IntentText.stem).filter { $0.count >= 3 }
    }

    static func hasGenre(_ title: TitleFeatures, facet: String) -> Bool {
        anyWord(of: title.genres, hasPrefixIn: genreStems(facet))
    }

    /// The stems a country facet value is matched by («Южная Корея» → «коре»).
    static func countryStems(_ facet: String, lexicon: Lexicon = .current) -> [String] {
        let normalized = IntentText.normalize(facet)
        if let entry = lexicon.countries.first(where: { IntentText.normalize($0.name) == normalized }) {
            return entry.stems
        }
        let words = IntentText.words(facet)
        for entry in lexicon.countries where entry.stems.contains(where: { stem in words.contains { $0.hasPrefix(stem) } }) {
            return entry.stems
        }
        return words.map(IntentText.stem).filter { $0.count >= 3 }
    }

    static func hasCountry(_ title: TitleFeatures, facet: String) -> Bool {
        let stems = countryStems(facet)
        if anyWord(of: title.countries, hasPrefixIn: stems) { return true }
        // Multi-word stems («соединенн» matches «Соединённые Штаты»).
        let normalized = title.countries.map(IntentText.normalize)
        return stems.contains { stem in normalized.contains { $0.contains(stem) && stem.count >= 5 } }
    }

    /// A theme to avoid («про войну», «насилия», «Ди Каприо») found in the title's genres, names or people. Short
    /// stems match whole words only, so «без детей» doesn't hide «Детективы».
    static func mentions(_ title: TitleFeatures, avoid term: String) -> Bool {
        var words = IntentText.words(term)
        if let first = words.first, ["про", "о", "об"].contains(first) { words.removeFirst() }
        guard !words.isEmpty else { return false }
        let haystack = (title.genres + [title.name, title.originalName ?? ""] + title.directors.map(\.name)
            + title.actors.prefix(5).map(\.name)).flatMap(IntentText.words)
        if words.count > 1, term.trimmingCharacters(in: .whitespaces).first?.isUppercase == true {
            // A name («Ди Каприо»): all of its words, or written together («ДиКаприо»).
            return words.allSatisfy { haystack.contains($0) } || haystack.contains(words.joined())
        }
        for word in words {
            let stem = IntentText.stem(word)
            if stem.count >= 4 {
                if haystack.contains(where: { $0.hasPrefix(stem) }) { return true }
            } else if haystack.contains(word) {
                return true
            }
        }
        return false
    }

    /// The title's rating on a 1–10 scale, as the picker's quality rules read it (КП, then IMDb, then the site).
    static func quality(_ title: TitleFeatures) -> Double? {
        let known = [title.kpRating, title.imdbRating].compactMap { $0 }.filter { $0 > 0 }
        if !known.isEmpty { return known.reduce(0, +) / Double(known.count) }
        if let site = title.siteRating, site > 0 { return site }
        return nil
    }

    /// Whether a title clears a rating floor («КП от 7»); «рейтинг от 7,5» takes whichever rating is known.
    static func meets(_ title: TitleFeatures, _ floor: RatingFloor) -> Bool {
        switch floor.source {
        case .kp:
            return (title.kpRating ?? 0) >= floor.value
        case .imdb:
            return (title.imdbRating ?? 0) >= floor.value
        case .rt:
            return Double(title.rtCritic ?? 0) >= floor.value
        case .any:
            let ratings = [title.kpRating, title.imdbRating, title.rtCritic.map { Double($0) / 10 }].compactMap { $0 }
            return ratings.contains { $0 >= floor.value }
        }
    }
}
