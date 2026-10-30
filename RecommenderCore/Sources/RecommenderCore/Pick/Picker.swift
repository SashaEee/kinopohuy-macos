import Foundation

/// Everything the picker needs from a prepared engine: the ranked candidates (best first, after the engine's filters),
/// the titles they refer to, the user's own pool («Своё»), title weights and recent impressions.
public struct PickContext: Sendable {
    public var ranked: [Recommendation]
    public var titles: [String: TitleFeatures]
    /// «Своё»: bookmarks without progress, «Можно начать», next parts and next episodes, best first.
    public var ownPool: [Recommendation]
    /// Far graph links and exploration candidates, best first.
    public var discoverPool: [Recommendation]
    public var titleWeights: [String: Double]
    public var impressions: [Impression]
    public var context: EngineContext
    public var settings: RecommenderSettings
    public var weights: Weights

    public init(
        ranked: [Recommendation], titles: [String: TitleFeatures], ownPool: [Recommendation],
        discoverPool: [Recommendation], titleWeights: [String: Double], impressions: [Impression],
        context: EngineContext, settings: RecommenderSettings, weights: Weights
    ) {
        self.ranked = ranked
        self.titles = titles
        self.ownPool = ownPool
        self.discoverPool = discoverPool
        self.titleWeights = titleWeights
        self.impressions = impressions
        self.context = context
        self.settings = settings
        self.weights = weights
    }
}

/// «Выбери за меня»: hard filters from the intent, a shortlist from the chosen pool, a seeded noisy argmax, two MMR
/// alternatives, relaxation when nothing matches, at most one clarifying question (the plan's §4.9).
///
/// - The pool follows the slider: «Своё» picks only from the user's own list, «Микс» adds the 50 best matches of the
///   ranking, «Открытия» takes far links. Titles shown this session never come back; their sequels and «Смотрите
///   также» neighbours count ×0.7 for the rest of the session («Другое» means «not this kind of thing right now»).
/// - The winner is `argmax(score + ε)`, `ε ~ N(0, σ²/(1 + impressions))`, `σ = 0.15·std(scores)`, seeded by the
///   session and the step, so the same step gives the same card and a title shown often wobbles less.
/// - If nothing fits, constraints go one by one — rating, mood, duration ±20 %, kind (then time, years, countries) —
///   and each is reported («убрал «до 90 минут»») so the sheet can offer «Вернуть». Exclusions («без ужасов») and the
///   family rules are never dropped.
public enum Picker {
    public static func pick(_ request: PickRequest, in context: PickContext) -> PickResult {
        pick(request, in: context, moodMap: .current)
    }

    static func pick(_ request: PickRequest, in context: PickContext, moodMap: MoodMap) -> PickResult {
        var session = PickSession(request: request, context: context, moodMap: moodMap)
        return session.run()
    }

    /// The shortlist size (the plan's «топ-50 из пула»).
    static let shortlistSize = 50
    /// «Другое» on a title: its sequels and neighbours sink this much for the rest of the session.
    static let skipFactor = 0.7
    /// σ = this × the shortlist's score spread.
    static let noiseShare = 0.15
    /// A guessed length (card without one) loses ties to a known one.
    static let estimatePenalty = 0.03
}

// MARK: - One pick

private struct PickSession {
    let request: PickRequest
    let context: PickContext
    let moodMap: MoodMap
    let lexicon: Lexicon
    let shown: Set<String>
    let shownTitles: [TitleFeatures]
    private var genreWordsCache: [String: [String]] = [:]

    init(request: PickRequest, context: PickContext, moodMap: MoodMap) {
        self.request = request
        self.context = context
        self.moodMap = moodMap
        self.lexicon = .current
        self.shown = Set(request.shown)
        self.shownTitles = request.shown.compactMap { context.titles[$0] }
    }

    struct Candidate {
        var rec: Recommendation
        var title: TitleFeatures
        var score: Double
        var similarity: Double
        var similarAnchor: String?
        var directLink: Bool
        var person: (ref: PersonRef, director: Bool)?
    }

    mutating func run() -> PickResult {
        let solved = solve()
        let shortlist = solved.candidates
        let theta = noisyScores(shortlist)
        let order = shortlist.indices.sorted { lhs, rhs in
            theta[lhs] != theta[rhs] ? theta[lhs] > theta[rhs] : shortlist[lhs].title.id < shortlist[rhs].title.id
        }
        var main: Recommendation?
        var alternatives: [Recommendation] = []
        if let best = order.first {
            main = explained(shortlist[best], intent: solved.intent)
            alternatives = mmrAlternatives(shortlist, theta: theta, main: best, count: 2)
                .map { explained(shortlist[$0], intent: solved.intent) }
        }
        let question = clarifyingQuestion(shortlist, order: order)
        return PickResult(
            main: main, alternatives: alternatives, showGrid: request.skips >= 3, relaxed: solved.relaxed,
            question: question, suggestRefine: request.skips >= 5, effectiveIntent: solved.intent,
        )
    }

    // MARK: Relaxation

    private enum Step: CaseIterable {
        case rating, mood, duration, kind, time, years, countries
    }

    /// Tries the intent as asked, then drops constraints in the plan's order until something fits; then puts back
    /// every dropped constraint that wasn't the problem (most important first), so «убрал …» names only what had to
    /// go. Widens the pool last.
    private mutating func solve() -> (candidates: [Candidate], intent: WatchIntent, relaxed: [Relaxation]) {
        var pools: [[PickPool]] = [[request.pool]]
        if request.pool != .mix { pools.append([.mix]) }
        pools.append([.own, .mix, .discover])
        var widened = false
        for poolSet in pools {
            var dropped: [Step] = []
            var built = (intent: request.intent, relaxed: [Relaxation]())
            var candidates = shortlist(for: built.intent, pools: poolSet)
            for step in Step.allCases where candidates.isEmpty {
                let trial = relaxing(dropped + [step])
                guard trial.relaxed.count > built.relaxed.count else { continue }
                dropped.append(step)
                built = trial
                candidates = shortlist(for: built.intent, pools: poolSet)
            }
            if !candidates.isEmpty, dropped.count > 1 {
                for step in dropped.dropLast().reversed() {
                    let fewer = dropped.filter { $0 != step }
                    let trial = relaxing(fewer)
                    let restored = shortlist(for: trial.intent, pools: poolSet)
                    if !restored.isEmpty {
                        dropped = fewer
                        built = trial
                        candidates = restored
                    }
                }
            }
            if !candidates.isEmpty {
                var relaxed = built.relaxed
                if widened {
                    relaxed.append(Relaxation(field: .familiarity, label: "добавил подходящее из каталога"))
                }
                return (candidates, built.intent, relaxed)
            }
            widened = true
        }
        return ([], request.intent, [])
    }

    /// The request's intent with these steps applied, in the plan's order, and what each one dropped.
    private func relaxing(_ steps: [Step]) -> (intent: WatchIntent, relaxed: [Relaxation]) {
        var intent = request.intent
        var relaxed: [Relaxation] = []
        for step in Step.allCases where steps.contains(step) {
            guard let next = relax(intent, step) else { continue }
            intent = next.intent
            relaxed += next.relaxed
        }
        return (intent, relaxed)
    }

    private func relax(_ intent: WatchIntent, _ step: Step) -> (intent: WatchIntent, relaxed: [Relaxation])? {
        var result = intent
        switch step {
        case .rating:
            guard let floor = intent.minRating else { return nil }
            result.minRating = nil
            result.confidence[.minRating] = nil
            return (result, [Relaxation(field: .minRating, label: "убрал «\(IntentLabels.rating(floor))»")])
        case .mood:
            var relaxed: [Relaxation] = []
            let moods = Mood.allCases.filter { (intent.moods[$0] ?? 0) > 0 }
            if !moods.isEmpty {
                let labels = moods.map { "«\(lexicon.mood($0)?.label ?? $0.rawValue)»" }
                relaxed.append(Relaxation(field: .moods, label: "убрал \(labels.joined(separator: " и "))"))
                result.moods = [:]
                result.confidence[.moods] = nil
            }
            if !intent.genres.include.isEmpty {
                let labels = intent.genres.include.sorted().map { "«\(lexicon.genre($0)?.label ?? $0)»" }
                relaxed.append(Relaxation(field: .genres, label: "убрал \(labels.joined(separator: " и "))"))
                result.genres.include = []
                if result.genres.isEmpty { result.confidence[.genres] = nil }
            }
            return relaxed.isEmpty ? nil : (result, relaxed)
        case .duration:
            guard let time = intent.time else { return nil }
            let stretched: TimeBudget
            switch time {
            case .maxMinutes(let minutes):
                stretched = .maxMinutes(Int((Double(minutes) * 1.2).rounded()))
            case .episode(let range):
                stretched = .episode(Int((Double(range.lowerBound) * 0.8).rounded())...Int((Double(range.upperBound) * 1.2).rounded()))
            case .filmNight, .weekendSeries:
                return nil
            }
            result.time = stretched
            let limit: Int = switch stretched {
            case .maxMinutes(let minutes): minutes
            case .episode(let range): range.upperBound
            default: 0
            }
            let label = "растянул «\(IntentLabels.timePhrase(time))» до \(limit) \(IntentLabels.minutesGenitive(limit))"
            return (result, [Relaxation(field: .time, label: label)])
        case .kind:
            guard let kinds = intent.kinds else { return nil }
            result.kinds = nil
            result.confidence[.kinds] = nil
            return (result, [Relaxation(field: .kinds, label: "убрал «\(IntentLabels.kinds(kinds))»")])
        case .time:
            guard let time = intent.time else { return nil }
            result.time = nil
            result.confidence[.time] = nil
            return (result, [Relaxation(field: .time, label: "убрал «\(IntentLabels.timePhrase(time))»")])
        case .years:
            guard let years = intent.years else { return nil }
            result.years = nil
            result.confidence[.years] = nil
            let label = IntentLabels.years(years, currentYear: IntentCalendar.year(of: context.context.now))
            return (result, [Relaxation(field: .years, label: "убрал «\(label)»")])
        case .countries:
            guard !intent.countries.include.isEmpty else { return nil }
            let labels = IntentChips.chips(for: WatchIntent(countries: Facets(include: intent.countries.include)))
                .map { "«\($0.label)»" }
            result.countries.include = []
            if result.countries.isEmpty { result.confidence[.countries] = nil }
            return (result, [Relaxation(field: .countries, label: "убрал \(labels.joined(separator: " и "))")])
        }
    }

    // MARK: Pools and filters

    private func poolRecommendations(_ pool: PickPool) -> [Recommendation] {
        switch pool {
        case .own: context.ownPool
        case .mix: context.ranked
        case .discover: context.discoverPool
        }
    }

    /// The shortlist for an intent over pools: hard filters, scores, the top 50. «Микс» is the own pool plus the 50
    /// best of the ranking that pass the filters.
    private mutating func shortlist(for intent: WatchIntent, pools: [PickPool]) -> [Candidate] {
        let filter = IntentFilter(intent: intent, settings: context.settings, moodMap: moodMap, lexicon: lexicon)
        var byId: [String: Candidate] = [:]
        var poolsToScan = pools
        if pools == [.mix] { poolsToScan = [.own, .mix] }
        for pool in poolsToScan {
            var passing: [Candidate] = []
            for rec in poolRecommendations(pool) where byId[rec.titleId] == nil {
                guard let candidate = evaluate(rec, intent: intent, filter: filter) else { continue }
                passing.append(candidate)
            }
            if pool == .mix || pool == .discover {
                passing.sort(by: Self.better)
                passing = Array(passing.prefix(Picker.shortlistSize))
            }
            for candidate in passing where byId[candidate.title.id] == nil { byId[candidate.title.id] = candidate }
        }
        return Array(byId.values.sorted(by: Self.better).prefix(Picker.shortlistSize))
    }

    private static func better(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        lhs.score != rhs.score ? lhs.score > rhs.score : lhs.title.id < rhs.title.id
    }

    private mutating func genreWords(_ title: TitleFeatures) -> [String] {
        if let cached = genreWordsCache[title.id] { return cached }
        let words = title.genres.flatMap(IntentText.words)
        genreWordsCache[title.id] = words
        return words
    }

    /// One title against the intent: nil when a hard filter says no, else its score for this request.
    private mutating func evaluate(_ rec: Recommendation, intent: WatchIntent, filter: IntentFilter) -> Candidate? {
        guard !shown.contains(rec.titleId), !intent.similarTo.contains(rec.titleId),
              let title = context.titles[rec.titleId]
        else { return nil }
        let words = genreWords(title)
        guard filter.passes(title, genreWords: words) else { return nil }

        var score = rec.score
        if !intent.moods.isEmpty {
            let fit = moodMap.moodFit(title, genreWords: words, moods: intent.moods)
            if filter.requiresMood, fit.matched.isEmpty { return nil }
            score += moodMap.moodWeight * fit.score
        }
        if let company = intent.company {
            score += moodMap.companyWeight * moodMap.companyFit(title, genreWords: words, company: company)
        }
        var candidate = Candidate(rec: rec, title: title, score: score, similarity: 0, similarAnchor: nil, directLink: false, person: nil)
        if !intent.similarTo.isEmpty {
            for anchor in intent.similarTo {
                let link = similarity(title, to: anchor)
                if link.value > candidate.similarity {
                    candidate.similarity = link.value
                    candidate.similarAnchor = anchor
                    candidate.directLink = link.direct
                }
            }
            candidate.score += moodMap.similarWeight * candidate.similarity
        }
        if !intent.people.isEmpty {
            for person in intent.people {
                if title.directors.contains(where: { Self.same($0, person) }) {
                    candidate.person = (person, true)
                    break
                }
                if candidate.person == nil, title.actors.prefix(5).contains(where: { Self.same($0, person) }) {
                    candidate.person = (person, false)
                }
            }
            if let person = candidate.person { candidate.score += moodMap.peopleWeight * (person.director ? 1 : 0.7) }
        }
        if intent.time != nil, TitleTiming.minutes(of: title).estimated { candidate.score -= Picker.estimatePenalty }
        if isRelatedToShown(title) {
            candidate.score = candidate.score >= 0 ? candidate.score * Picker.skipFactor : candidate.score / Picker.skipFactor
        }
        return candidate
    }

    private static func same(_ lhs: PersonRef, _ rhs: PersonRef) -> Bool {
        lhs.id == rhs.id || (!rhs.name.isEmpty && IntentText.normalize(lhs.name) == IntentText.normalize(rhs.name))
    }

    /// A sequel or a «Смотрите также» neighbour of something the user already skipped this session.
    private func isRelatedToShown(_ title: TitleFeatures) -> Bool {
        shownTitles.contains { skipped in
            (skipped.franchiseId != nil && skipped.franchiseId == title.franchiseId)
                || skipped.watchAlso.contains(title.id) || title.watchAlso.contains(skipped.id)
        }
    }

    /// «как «Мост»»: how close a title is to the reference — a direct «Смотрите также» link or the same franchise
    /// first, then shared lists and collections, people and genres.
    private func similarity(_ title: TitleFeatures, to anchorId: String) -> (value: Double, direct: Bool) {
        let anchor = context.titles[anchorId]
        var value = 0.0
        let direct = title.watchAlso.contains(anchorId) || anchor?.watchAlso.contains(title.id) == true
        if direct { value = 1 }
        guard let anchor else { return (value, direct) }
        if let franchise = title.franchiseId, franchise == anchor.franchiseId { value = max(value, 0.9) }
        let boards = Set(title.boards.filter { $0.kind == .list || $0.kind == .collection }.map(\.key))
        let anchorBoards = Set(anchor.boards.filter { $0.kind == .list || $0.kind == .collection }.map(\.key))
        value += min(0.6, 0.3 * Double(boards.intersection(anchorBoards).count))
        if !Set(title.directors.map(\.id)).isDisjoint(with: anchor.directors.map(\.id)) { value += 0.3 }
        let sharedActors = Set(title.actors.prefix(5).map(\.id)).intersection(anchor.actors.prefix(5).map(\.id)).count
        value += min(0.3, 0.1 * Double(sharedActors))
        value += 0.3 * Self.jaccard(title.genres, anchor.genres)
        return (min(1, value), direct)
    }

    // MARK: Noise and choice

    /// θ = score + ε, ε ~ N(0, σ²/(1 + impressions)), σ = 0.15·std(scores); seeded by the session and the step.
    private func noisyScores(_ shortlist: [Candidate]) -> [Double] {
        guard !shortlist.isEmpty else { return [] }
        let scores = shortlist.map(\.score)
        let mean = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scores.count)
        let sigma = Picker.noiseShare * variance.squareRoot()
        guard sigma > 0 else { return scores }
        let window = context.weights.fatigueWindowDays * 86_400
        var impressions: [String: Int] = [:]
        for impression in context.impressions where context.context.now - impression.shownAt <= window {
            impressions[impression.titleId, default: 0] += 1
        }
        return shortlist.map { candidate in
            var random = SplitMix64.forTitle(candidate.title.id, seed: request.seed, step: request.shown.count)
            let shows = Double(impressions[candidate.title.id] ?? 0)
            return candidate.score + random.nextGaussian() * sigma / (1 + shows).squareRoot()
        }
    }

    /// Two alternatives by MMR: good on their own and unlike the main pick and each other (genres, lists, people).
    private func mmrAlternatives(_ shortlist: [Candidate], theta: [Double], main: Int, count: Int) -> [Int] {
        guard shortlist.count > 1 else { return [] }
        let lambda = context.weights.mmrLambda
        let low = theta.min() ?? 0
        let high = theta.max() ?? 0
        func relevance(_ index: Int) -> Double { high > low ? (theta[index] - low) / (high - low) : 1 }
        var selected = [main]
        var result: [Int] = []
        while result.count < count {
            var best: (index: Int, value: Double)?
            for index in shortlist.indices where !selected.contains(index) {
                let redundancy = selected.map { Self.likeness(shortlist[index].title, shortlist[$0].title) }.max() ?? 0
                let value = lambda * relevance(index) - (1 - lambda) * redundancy
                if let current = best {
                    let tie = value == current.value
                    if value > current.value || (tie && (theta[index] > theta[current.index]
                        || (theta[index] == theta[current.index] && shortlist[index].title.id < shortlist[current.index].title.id))) {
                        best = (index, value)
                    }
                } else {
                    best = (index, value)
                }
            }
            guard let chosen = best else { break }
            selected.append(chosen.index)
            result.append(chosen.index)
        }
        return result
    }

    /// 0.5·genres (Jaccard) + 0.3·shared lists/collections + 0.2·shared people; the same franchise counts as alike.
    private static func likeness(_ a: TitleFeatures, _ b: TitleFeatures) -> Double {
        if let franchise = a.franchiseId, franchise == b.franchiseId { return 1 }
        let boardsA = Set(a.boards.map(\.key))
        let boardsB = Set(b.boards.map(\.key))
        let sharedBoards = boardsA.isEmpty || boardsB.isEmpty
            ? 0 : Double(boardsA.intersection(boardsB).count) / Double(min(boardsA.count, boardsB.count))
        let peopleA = Set((a.directors + a.actors.prefix(5)).map(\.id))
        let peopleB = Set((b.directors + b.actors.prefix(5)).map(\.id))
        let sharedPeople: Double = peopleA.isDisjoint(with: peopleB) ? 0 : 1
        return 0.5 * jaccard(a.genres, b.genres) + 0.3 * sharedBoards + 0.2 * sharedPeople
    }

    private static func jaccard(_ a: [String], _ b: [String]) -> Double {
        let setA = Set(a.map(IntentText.normalize))
        let setB = Set(b.map(IntentText.normalize))
        let union = setA.union(setB).count
        return union == 0 ? 0 : Double(setA.intersection(setB).count) / Double(union)
    }

    // MARK: The clarifying question

    /// «Фильм или пара серий?» — once a session, when the kind or the time is unsure and the best ten mix films and
    /// series at least 30/70.
    private func clarifyingQuestion(_ shortlist: [Candidate], order: [Int]) -> ClarifyingQuestion? {
        guard !request.askedQuestion else { return nil }
        let intent = request.intent
        let unsure = (intent.confidence[.kinds] ?? 0) < 0.5 || (intent.confidence[.time] ?? 0) < 0.5
        guard unsure else { return nil }
        let top = order.prefix(10).map { shortlist[$0].title }
        let series = top.filter(\.isSeries).count
        let films = top.count - series
        guard top.count >= 4, Double(min(series, films)) / Double(top.count) >= 0.3 else { return nil }
        var film = intent
        film.kinds = [.film]
        film.confidence[.kinds] = 1
        if film.time == .weekendSeries { film.time = nil }
        var episodes = intent
        episodes.kinds = [.series]
        episodes.confidence[.kinds] = 1
        if episodes.time == .filmNight { episodes.time = nil }
        return ClarifyingQuestion(text: "Фильм или пара серий?", options: [
            .init(label: "Фильм", intent: film),
            .init(label: "Пару серий", intent: episodes),
        ])
    }

    // MARK: Reasons

    /// When the request named a title or a person and the pick matches it, say so — that's the reason the user will
    /// check first.
    private func explained(_ candidate: Candidate, intent: WatchIntent) -> Recommendation {
        var rec = candidate.rec
        if let anchorId = candidate.similarAnchor, candidate.similarity >= 0.5, let anchor = context.titles[anchorId] {
            let long = candidate.directLink
                ? "Похоже на «\(anchor.name)»: есть в «Смотрите также»"
                : "Похоже на «\(anchor.name)»"
            rec.reason = Reason(
                kind: .similarToMany, short: "Похоже на «\(anchor.name)»", long: long,
                evidence: Evidence(
                    anchorIds: [anchorId],
                    path: candidate.directLink ? [anchor.name, "Смотрите также", candidate.title.name] : [],
                ),
            )
        } else if let person = candidate.person {
            let short = person.director ? "Режиссёр \(person.ref.name)" : "С участием \(person.ref.name)"
            rec.reason = Reason(kind: .person, short: short, long: short, evidence: Evidence(person: person.ref))
        }
        return rec
    }
}

// MARK: - Hard filters

/// The intent's hard limits, prepared once per pick (stems resolved, rules combined).
private struct IntentFilter {
    let intent: WatchIntent
    let settings: RecommenderSettings
    let rules: MoodMap.Rules
    let requiresMood: Bool
    let includeGenres: [[String]]
    let excludeGenres: [[String]]
    let settingsGenres: [[String]]
    let includeCountries: [String]
    let excludeCountries: [String]

    init(intent: WatchIntent, settings: RecommenderSettings, moodMap: MoodMap, lexicon: Lexicon) {
        self.intent = intent
        self.settings = settings
        self.rules = moodMap.rules(moods: intent.moods, company: intent.company)
        // A mood the user asked for must match; a mood from the clock only nudges.
        self.requiresMood = !intent.moods.isEmpty
            && (intent.confidence[.moods] ?? 1) >= moodMap.moodRequirementConfidence
        self.includeGenres = intent.genres.include.sorted().map { TitleMatch.genreStems($0, lexicon: lexicon) }
        self.excludeGenres = intent.genres.exclude.sorted().map { TitleMatch.genreStems($0, lexicon: lexicon) }
        self.settingsGenres = settings.excludedGenres.sorted().map { TitleMatch.genreStems($0, lexicon: lexicon) }
        self.includeCountries = intent.countries.include.sorted()
        self.excludeCountries = intent.countries.exclude.sorted()
    }

    func passes(_ title: TitleFeatures, genreWords: [String]) -> Bool {
        guard title.available, !title.comingSoon else { return false }
        let kind = TitleMatch.kind(of: title)
        func hasGenre(_ stems: [String]) -> Bool { genreWords.contains { word in stems.contains { word.hasPrefix($0) } } }

        // The user's standing settings.
        if settings.excludedKinds.contains(kind) { return false }
        if settingsGenres.contains(where: hasGenre) { return false }
        if let maxAge = settings.maxAge, let age = title.age, age > maxAge { return false }

        if let kinds = intent.kinds, !kinds.isEmpty, !kinds.contains(kind) { return false }
        if let time = intent.time, !TitleTiming.fits(title, time) { return false }

        // Company and mood rules: family ≤ 12+ and no horror, friends ≤ 130 minutes, cozy ≤ 16+.
        if let maxAge = rules.maxAge, let age = title.age, age > maxAge { return false }
        if !rules.excludeStems.isEmpty, hasGenre(rules.excludeStems) { return false }
        if let maxMinutes = rules.maxDurationMin, !title.isSeries, TitleTiming.minutes(of: title).value > maxMinutes {
            return false
        }

        if !includeGenres.isEmpty, !includeGenres.contains(where: hasGenre) { return false }
        if excludeGenres.contains(where: hasGenre) { return false }
        if !includeCountries.isEmpty, !includeCountries.contains(where: { TitleMatch.hasCountry(title, facet: $0) }) {
            return false
        }
        if excludeCountries.contains(where: { TitleMatch.hasCountry(title, facet: $0) }) { return false }
        if let years = intent.years {
            guard let year = title.year, years.contains(year) else { return false }
        }
        if let floor = intent.minRating, !TitleMatch.meets(title, floor) { return false }
        if intent.avoid.contains(where: { TitleMatch.mentions(title, avoid: $0) }) { return false }
        return true
    }
}
