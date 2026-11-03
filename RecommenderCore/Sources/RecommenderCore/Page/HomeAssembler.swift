import Foundation

/// Builds Home's personal part (§4.8): «Сегодня вечером» by context, then personal rows chosen greedily like
/// Netflix's homepage — the best row first, its titles struck from the others, rows that fall under their minimum
/// dropped — so no title appears twice. Every card gets one verifiable reason, and one anchor backs at most two
/// reasons on the page.
struct HomeAssembler {
    let core: EngineCore
    /// Eligible candidates after franchise collapse, best first.
    let ranked: [ScoredTitle]
    let rankings: [SourceKind: SourceRanking]
    let farHits: [SourceHit]
    let similarity: TitleSimilarity
    let isColdStart: Bool

    private let scoreOf: [Int: ScoredTitle]

    init(
        core: EngineCore, ranked: [ScoredTitle], rankings: [SourceKind: SourceRanking], farHits: [SourceHit],
        similarity: TitleSimilarity, isColdStart: Bool,
    ) {
        self.core = core
        self.ranked = ranked
        self.rankings = rankings
        self.farHits = farHits
        self.similarity = similarity
        self.isColdStart = isColdStart
        var scoreOf: [Int: ScoredTitle] = [:]
        scoreOf.reserveCapacity(ranked.count)
        for item in ranked { scoreOf[item.title] = item }
        self.scoreOf = scoreOf
    }

    // MARK: Plans

    enum Fill: Sendable {
        /// The candidates in order (optionally diversified).
        case ordered
        /// «Подборки для вас»: the best unused title of each collection, round-robin.
        case collections([(board: Int, members: [Int])])
    }

    struct RowPlan: Sendable {
        let id: String
        let kind: RecRow.Kind
        let title: String
        var anchorId: String?
        var person: PersonRef?
        let candidates: [Int]
        /// Relevance for MMR (by title); the final score when absent.
        var relevance: [Int: Double] = [:]
        var diversify = false
        var window = 60
        var minItems: Int
        var options = ReasonOptions()
        var fill: Fill = .ordered
        /// «Для вас» only: discoveries woven into the exploration slots.
        var discoveries: [Int] = []
        let order: Int
    }

    struct Materialized: Sendable {
        var items: [Int]
        var boards: [Int: BoardRef] = [:]
        var window: Set<Int>
    }

    func assemble() -> PageLayout {
        var used = Set<Int>()
        let hero = makeHero(used: &used)
        var plans = rowPlans()
        var cache: [String: Materialized] = [:]
        var newlyUsed = used
        var chosen: [(plan: RowPlan, result: Materialized)] = []
        var kindCount: [RecRow.Kind: Int] = [:]
        let weights = core.weights

        while chosen.count < weights.maxPersonalRows, !plans.isEmpty {
            var best: (index: Int, result: Materialized, score: Double)?
            var keep: [RowPlan] = []
            for plan in plans {
                let group = Self.capGroup(plan.kind)
                if (kindCount[group] ?? 0) >= weights.maxRowsPerKind { continue }
                let result: Materialized
                if let cached = cache[plan.id], cached.window.isDisjoint(with: newlyUsed) {
                    result = cached
                } else {
                    result = materialize(plan, used: used)
                    cache[plan.id] = result
                }
                guard result.items.count >= plan.minItems else { continue }
                keep.append(plan)
                let score = rowScore(plan, items: result.items, repeats: kindCount[group] ?? 0)
                if let current = best, current.score >= score { continue }
                best = (keep.count - 1, result, score)
            }
            plans = keep
            guard let best else { break }
            let plan = plans.remove(at: best.index)
            chosen.append((plan, best.result))
            newlyUsed = Set(best.result.items)
            used.formUnion(best.result.items)
            kindCount[Self.capGroup(plan.kind), default: 0] += 1
        }

        // Reasons in page order: an anchor backs at most two of them.
        var anchorUses: [String: Int] = [:]
        func recommendation(_ title: Int, options base: ReasonOptions, board: BoardRef? = nil) -> Recommendation? {
            guard let scored = scoreOf[title] else { return nil }
            var options = base
            options.excludedAnchors.formUnion(anchorUses.filter { $0.value >= weights.perAnchorCap }.keys)
            options.forcedBoard = board ?? base.forcedBoard
            let reason = ReasonBuilder.reason(for: scored, core: core, options: options)
            if [.becauseWatched, .similarToMany, .loved].contains(reason.kind) {
                for anchor in reason.evidence.anchorIds { anchorUses[anchor, default: 0] += 1 }
            }
            return Recommendation(
                titleId: core.titles[title].id, score: scored.score, contributions: scored.contributions,
                reason: reason, tags: ReasonBuilder.tags(for: title, core: core),
            )
        }

        var tonight: TonightHero?
        if let hero, let main = recommendation(hero.main, options: ReasonOptions()) {
            tonight = TonightHero(
                main: main, alternatives: hero.alternatives.compactMap { recommendation($0, options: ReasonOptions()) },
                contextLabel: hero.label,
            )
        }
        let rows = chosen.map { plan, result in
            RecRow(
                id: plan.id, kind: plan.kind, title: plan.title,
                items: result.items.compactMap { recommendation($0, options: plan.options, board: result.boards[$0]) },
                anchorId: plan.anchorId, person: plan.person,
            )
        }
        return PageLayout(hero: tonight, rows: rows)
    }

    /// Anchor rows share one cap: at most two «Потому что вы…» rows whatever the wording.
    static func capGroup(_ kind: RecRow.Kind) -> RecRow.Kind {
        kind == .becauseLoved ? .becauseWatched : kind
    }

    /// Mean of the top five scores × the type prior × the repeat penalty (× a seeded daily rotation for anchor rows).
    func rowScore(_ plan: RowPlan, items: [Int], repeats: Int) -> Double {
        let top = items.prefix(5).compactMap { scoreOf[$0]?.score }
        let mean = max(0.01, EngineMath.mean(top))
        var score = mean * core.weights.rowPrior(plan.kind) * pow(core.weights.rowRepeatPenalty, Double(repeats))
        if let anchor = plan.anchorId, plan.kind == .becauseWatched || plan.kind == .becauseLoved {
            let u = StableHash.unit(seed: core.seed, key: "row:\(anchor)")
            score *= 1 + core.weights.rowRotation * (2 * u - 1)
        }
        return score
    }

    func materialize(_ plan: RowPlan, used: Set<Int>) -> Materialized {
        let limit = core.weights.rowMaxItems
        switch plan.fill {
        case let .collections(collections):
            var items: [Int] = []
            var boards: [Int: BoardRef] = [:]
            var taken = used
            // One title per collection; a second round only while the row is under its minimum.
            for pass in 0..<2 where items.count < limit {
                for collection in collections where items.count < limit {
                    if pass == 1, items.count >= plan.minItems { break }
                    guard let pick = collection.members.first(where: { !taken.contains($0) }) else { continue }
                    items.append(pick)
                    taken.insert(pick)
                    boards[pick] = core.graph.board(collection.board)
                }
            }
            // Only the picks themselves can be taken away by another row: a used non-pick changes nothing.
            return Materialized(items: items, boards: boards, window: Set(items))
        case .ordered:
            let available = plan.candidates.filter { !used.contains($0) }
            let window = Array(available.prefix(plan.diversify ? plan.window : limit + plan.discoveries.count))
            var items: [Int]
            if plan.diversify {
                let relevance = window.map { plan.relevance[$0] ?? scoreOf[$0]?.score ?? 0 }
                items = MMRDiversifier.select(
                    candidates: window, relevance: relevance, count: limit, minCount: plan.minItems,
                    lambda: core.weights.mmrLambda, similarity: similarity, primaryGenre: core.table.primaryGenre,
                    caps: rowCaps(for: window),
                )
            } else {
                items = Array(window.prefix(limit))
            }
            // MMR depends on its whole window; a plain order only on what it picked.
            var touched = plan.diversify ? Set(window) : Set(items)
            if !plan.discoveries.isEmpty {
                let discoveries = plan.discoveries.filter { !used.contains($0) }
                touched.formUnion(discoveries.prefix(8))
                items = ExplorationSlot.weave(
                    discoveries, into: items, familiarity: core.settings.familiarity, rowSize: limit,
                )
            }
            return Materialized(items: items, window: touched)
        }
    }

    /// Genre shares from the history; anchor and person keys from each candidate's evidence.
    func rowCaps(for candidates: [Int]) -> RowCaps {
        var keysOf: [Int: [String]] = [:]
        for title in candidates {
            guard let scored = scoreOf[title] else { continue }
            var keys: [String] = []
            if let anchor = scored.contribution(.graph)?.evidence.anchorIds.first { keys.append("a:\(anchor)") }
            if let person = scored.contribution(.people)?.evidence.person { keys.append("p:\(person.id)") }
            if !keys.isEmpty { keysOf[title] = keys }
        }
        return RowCaps(
            genreShare: core.profile.genreShare, genreCapMin: core.weights.genreCapMin,
            genreCapSlack: core.weights.genreCapSlack, perKeyCap: core.weights.perAnchorCap, keysOf: keysOf,
        )
    }

    // MARK: Hero

    struct HeroPick {
        let main: Int
        let alternatives: [Int]
        let label: String
    }

    /// The main pick fits the moment; the two alternatives differ from it (and each other) in kind or genre.
    func makeHero(used: inout Set<Int>) -> HeroPick? {
        guard !isColdStart, core.settings.heroMode == .tonight, !ranked.isEmpty else { return nil }
        let context = HeroContext(context: core.context, weights: core.weights)
        let fitting = ranked.first { context.matches(core.titles[$0.title]) }
        guard let main = fitting ?? ranked.first else { return nil }
        let label = fitting == nil ? "Лучшее для вас сейчас" : context.label

        func differs(_ lhs: Int, _ rhs: Int) -> Bool {
            let lk = FeatureTable.kind(of: core.titles[lhs])
            let rk = FeatureTable.kind(of: core.titles[rhs])
            return lk != rk || core.table.primaryGenre[lhs] != core.table.primaryGenre[rhs]
                || core.table.primaryGenre[lhs] == nil
        }
        var alternatives: [Int] = []
        for preferFit in [true, false] {
            for candidate in ranked where alternatives.count < 2 {
                let title = candidate.title
                guard title != main.title, !alternatives.contains(title), differs(title, main.title),
                      alternatives.allSatisfy({ differs(title, $0) }),
                      !preferFit || context.matches(core.titles[title])
                else { continue }
                alternatives.append(title)
            }
        }
        used.insert(main.title)
        used.formUnion(alternatives)
        return HeroPick(main: main.title, alternatives: alternatives, label: label)
    }

    // MARK: Row candidates

    func rowPlans() -> [RowPlan] {
        let weights = core.weights
        let rankedTitles = ranked.map(\.title)
        let inRanked = Set(rankedTitles)
        var plans: [RowPlan] = []
        var order = 0
        func next() -> Int {
            order += 1
            return order
        }

        // «Для вас»: what the user hasn't lined up already (their own queue is «Можно начать»).
        let discoveryTitles = discoveryCandidates(inRanked: inRanked)
        let notQueued = rankedTitles.filter { (core.signal($0)?.intent ?? 0) <= 0 }
        plans.append(RowPlan(
            id: "forYou", kind: .forYou, title: "Для вас", candidates: Array(notQueued.prefix(weights.mmrWindow)),
            diversify: true, window: weights.mmrWindow, minItems: weights.rowMinItems,
            discoveries: discoveryTitles, order: next(),
        ))

        // «Потому что вы досмотрели «X»» for the top anchors.
        let anchors = core.profile.anchors.filter { anchor in
            guard let signal = core.signal(anchor.title) else { return false }
            return anchor.weight >= weights.reasonAnchorMinWeight && !signal.notSeed
        }.prefix(weights.anchorRowCandidates)
        for anchor in anchors {
            let proximity = core.graph.twoStepProximity(from: anchor.title)
            let near = proximity.filter { inRanked.contains($0.key) }
            guard let maxProximity = near.values.max(), maxProximity > 0 else { continue }
            let maxScore = max(1e-9, near.keys.compactMap { scoreOf[$0]?.score }.max() ?? 1)
            var relevance: [Int: Double] = [:]
            for (title, value) in near {
                relevance[title] = 0.6 * value / maxProximity + 0.4 * max(0, scoreOf[title]?.score ?? 0) / maxScore
            }
            let candidates = near.keys.sorted {
                let lhs = relevance[$0] ?? 0
                let rhs = relevance[$1] ?? 0
                return lhs != rhs ? lhs > rhs : $0 < $1
            }
            let (kind, title) = anchorRowTitle(anchor)
            plans.append(RowPlan(
                id: "because:\(anchor.id)", kind: kind, title: title, anchorId: anchor.id, candidates: candidates,
                relevance: relevance, diversify: true, minItems: weights.rowMinItems,
                options: ReasonOptions(excludedAnchors: [anchor.id], excludedKinds: [.becauseWatched, .similarToMany, .loved]),
                order: next(),
            ))
        }

        // «Следующая часть / Вышел новый сезон».
        if let continuation = rankings[.continuation] {
            let items = continuation.hits.map(\.title).filter { inRanked.contains($0) }
            if !items.isEmpty {
                let parts = continuation.hits.filter { inRanked.contains($0.title) && $0.evidence.board?.kind == .franchise }.count
                let title = parts == items.count ? "Следующие части" : (parts == 0 ? "Вышли новые сезоны" : "Следующая часть и новые сезоны")
                plans.append(RowPlan(
                    id: "continuation", kind: .continuation, title: title, candidates: items,
                    minItems: weights.continuationRowMinItems,
                    options: ReasonOptions(preferredKinds: [.nextPart, .newSeason]), order: next(),
                ))
            }
        }

        // «Снова режиссёр Y» / «В ролях: Z».
        for favourite in PeopleSource.favourites(core).prefix(3) {
            let titles = PeopleSource.titles(of: favourite, core: core).filter { inRanked.contains($0) }
                .sorted { (scoreOf[$0]?.score ?? 0, -$0) > (scoreOf[$1]?.score ?? 0, -$1) }
            guard !titles.isEmpty else { continue }
            let title = favourite.role == .director ? "Снова режиссёр \(favourite.person.name)" : "В ролях: \(favourite.person.name)"
            plans.append(RowPlan(
                id: "person:\(favourite.role.rawValue):\(favourite.person.id)", kind: .person, title: title,
                person: favourite.person, candidates: titles, diversify: true, minItems: weights.rowMinItems,
                options: ReasonOptions(excludedPersons: [favourite.person.id]), order: next(),
            ))
        }

        // «Подборки для вас»: collections by the share of titles that suit the user.
        let collections = rankedCollections(inRanked: inRanked)
        if !collections.isEmpty {
            plans.append(RowPlan(
                id: "collections", kind: .collections, title: "Подборки для вас", candidates: [],
                minItems: weights.rowMinItems, fill: .collections(collections), order: next(),
            ))
        }

        // «Что-то новое» when it's mostly exploration (genres and countries the user hasn't tried); far links of the
        // site's graph in their own genres are «Вы могли пропустить» (calling them new would contradict their reasons).
        if !discoveryTitles.isEmpty {
            let exploration = Set((rankings[.exploration]?.hits ?? []).map(\.title))
            let head = discoveryTitles.prefix(20)
            let novel = head.filter(exploration.contains).count * 2 >= head.count
            plans.append(RowPlan(
                id: "discover", kind: .discover, title: novel ? "Что-то новое" : "Вы могли пропустить",
                candidates: discoveryTitles, diversify: true, minItems: weights.rowMinItems,
                options: ReasonOptions(preferredKinds: novel ? [.discovery] : []), order: next(),
            ))
        }

        // «Можно начать».
        if let intent = rankings[.intent] {
            let items = intent.hits.map(\.title).filter { inRanked.contains($0) }
            if !items.isEmpty {
                plans.append(RowPlan(
                    id: "canStart", kind: .canStart, title: "Можно начать", candidates: items,
                    minItems: weights.rowMinItems, options: ReasonOptions(preferredKinds: [.bookmark, .canStart]),
                    order: next(),
                ))
            }
        }
        return plans
    }

    /// Exploration and far-graph candidates, best score first.
    func discoveryCandidates(inRanked: Set<Int>) -> [Int] {
        var titles = Set<Int>()
        for hit in rankings[.exploration]?.hits ?? [] where inRanked.contains(hit.title) { titles.insert(hit.title) }
        // A far link of the site's graph is only a find when it's in the user's taste and well rated (Bayesian 7+):
        // otherwise it's just far.
        for hit in farHits where inRanked.contains(hit.title) && core.profile.tasteMatch[hit.title]
            && (core.qualityRating[hit.title] ?? 0) >= 7 {
            titles.insert(hit.title)
        }
        return titles.sorted {
            let lhs = scoreOf[$0]?.score ?? 0
            let rhs = scoreOf[$1]?.score ?? 0
            return lhs != rhs ? lhs > rhs : $0 < $1
        }
    }

    /// Collections by Σ max(0, score) of their candidate titles / √size, minus the share the user already watched.
    func rankedCollections(inRanked: Set<Int>) -> [(board: Int, members: [Int])] {
        var result: [(board: Int, members: [Int], score: Double)] = []
        for board in 0..<core.graph.boards.count where core.graph.board(board).kind == .collection {
            let members = core.graph.boardMembers[board]
            let candidates = members.filter { inRanked.contains($0) }
                .sorted { (scoreOf[$0]?.score ?? 0, -$0) > (scoreOf[$1]?.score ?? 0, -$1) }
            guard !candidates.isEmpty else { continue }
            let total = candidates.reduce(0) { $0 + max(0, scoreOf[$1]?.score ?? 0) }
            let size = Double(max(1, core.graph.boardSize[board]))
            let watched = Double(members.filter { core.signal($0)?.state == .seen }.count) / Double(max(1, members.count))
            let score = total / size.squareRoot() - watched
            if score > 0 { result.append((board, candidates, score)) }
        }
        result.sort { $0.score != $1.score ? $0.score > $1.score : $0.board < $1.board }
        return result.map { ($0.board, $0.members) }
    }

    /// «Потому что вы досмотрели «X»», «…обожаете…», «…смотрите…», «…оценили…».
    func anchorRowTitle(_ anchor: Anchor) -> (RecRow.Kind, String) {
        let name = RussianText.quoted(core.titles[anchor.title].name, limit: 40)
        guard let signal = core.signal(anchor.title) else { return (.becauseWatched, "Похоже на \(name)") }
        if signal.isLoved { return (.becauseLoved, "Потому что вы обожаете \(name)") }
        if signal.finished { return (.becauseWatched, "Потому что вы досмотрели \(name)") }
        if signal.explicitLevel != nil { return (.becauseWatched, "Потому что вы оценили \(name)") }
        if signal.state == .started { return (.becauseWatched, "Потому что вы смотрите \(name)") }
        return (.becauseWatched, "Похоже на \(name)")
    }
}
