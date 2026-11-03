import Foundation

/// What a reason may not use at this spot of the page.
struct ReasonOptions: Sendable {
    /// Anchors already cited twice on the page, or the anchor a row is about (its title says it already).
    var excludedAnchors: Set<String> = []
    var excludedKinds: Set<ReasonKind> = []
    /// The person a «Снова режиссёр Y» row is about.
    var excludedPersons: Set<String> = []
    /// «Подборки для вас»: the collection the title was picked for.
    var forcedBoard: BoardRef?
    /// Kinds to use whenever one holds, in order («Что-то новое» in the discovery row, the folder in «Можно начать»).
    var preferredKinds: [ReasonKind] = []
}

/// A reason that holds for the title, with the share of the score it stands for.
struct ReasonCandidate: Sendable {
    let reason: Reason
    let value: Double
}

/// One verifiable reason per card (§2.5, §4.10): the contribution with the largest share of the score picks the
/// template; when shares are within 10 % the template priority decides. Every claim is checked against the data —
/// «досмотрели» only for titles finished and weighing ≥ 0.5, real counts, real places in lists.
enum ReasonBuilder {
    /// The §2.5 order: lower wins when contributions are close.
    static func priority(_ kind: ReasonKind) -> Int {
        switch kind {
        case .nextEpisode: 1
        case .nextPart: 2
        case .newSeason: 3
        case .becauseWatched, .similarToMany: 4
        case .loved: 5
        case .person: 6
        case .rankedList: 7
        case .collection: 8
        case .bookmark, .canStart: 9
        case .featureCombo: 10
        case .critics: 11
        case .discovery: 12
        case .trending: 13
        }
    }

    static func reason(for scored: ScoredTitle, core: EngineCore, options: ReasonOptions = ReasonOptions()) -> Reason {
        if let board = options.forcedBoard, let forced = boardReason(board) { return forced }
        let candidates = candidates(for: scored, core: core, options: options)
        for preferred in options.preferredKinds {
            if let match = candidates.first(where: { $0.reason.kind == preferred }) { return match.reason }
        }
        if let chosen = choose(candidates, tieShare: core.weights.reasonTieShare) { return chosen }
        return fallback(for: scored.title, core: core, options: options)
    }

    /// The highest share wins; within `tieShare` of it the template priority decides.
    static func choose(_ candidates: [ReasonCandidate], tieShare: Double) -> Reason? {
        guard let top = candidates.map(\.value).max() else { return nil }
        let close = candidates.filter { $0.value >= top * (1 - tieShare) - 1e-12 }
        return close.min { lhs, rhs in
            let lp = priority(lhs.reason.kind)
            let rp = priority(rhs.reason.kind)
            return lp != rp ? lp < rp : lhs.value > rhs.value
        }?.reason
    }

    /// Every reason that holds for the title, each valued by the score share it explains.
    static func candidates(for scored: ScoredTitle, core: EngineCore, options: ReasonOptions) -> [ReasonCandidate] {
        var result: [ReasonCandidate] = []
        func add(_ reason: Reason?, _ value: Double) {
            guard let reason, !options.excludedKinds.contains(reason.kind) else { return }
            result.append(ReasonCandidate(reason: reason, value: value))
        }
        let weights = core.weights
        var tasteValue = weights.scoreAffinity * max(0, scored.affinity)
        for contribution in scored.contributions {
            let evidence = contribution.evidence
            switch contribution.source {
            case .graph, .viewers, .plot:
                add(anchorReason(evidence.anchorIds, evidence: evidence, core: core, options: options), contribution.value)
            case .continuation:
                add(continuationReason(scored.title, evidence: evidence, core: core), contribution.value)
            case .intent:
                add(intentReason(scored.title, evidence: evidence, core: core), contribution.value)
            case .affinity:
                tasteValue += contribution.value
            case .people:
                add(personReason(evidence, core: core, options: options), contribution.value)
            case .qualityFresh:
                if let board = evidence.board, board.rank != nil {
                    add(boardReason(board), contribution.value)
                } else if evidence.count != nil, evidence.features.isEmpty {
                    add(popularReason(scored.title, core: core), contribution.value)
                } else {
                    add(newReleaseReason(scored.title, core: core), contribution.value)
                }
            case .exploration:
                add(discoveryReason(scored.title, evidence: evidence, core: core), contribution.value)
            }
        }
        add(featureReason(scored.title, core: core), tasteValue)
        add(criticsReason(core.titles[scored.title]), weights.scoreQuality * scored.quality)
        return result
    }

    // MARK: Templates

    /// «Потому что вы досмотрели «X»» / «Похоже на «X» и «Y»» / «Вы отметили «X» как любимое».
    static func anchorReason(_ anchorIds: [String], evidence: Evidence, core: EngineCore, options: ReasonOptions) -> Reason? {
        let minWeight = core.weights.reasonAnchorMinWeight
        let usable: [(title: TitleFeatures, signal: TitleSignal)] = anchorIds.compactMap { id in
            guard !options.excludedAnchors.contains(id), let index = core.titleIndex[id], let signal = core.signals[id],
                  signal.weight >= minWeight
            else { return nil }
            return (core.titles[index], signal)
        }
        guard let first = usable.first else { return nil }
        let proof = Evidence(
            anchorIds: usable.map(\.signal.titleId), path: evidence.path, board: evidence.board, count: usable.count,
        )
        if usable.count >= 2 {
            let second = usable[1]
            let both = "Похоже на \(RussianText.quoted(first.title.name)) и \(RussianText.quoted(second.title.name))"
            let short = RussianText.fit([both, RussianText.fitQuoted("Похоже на ", first.title.name)])
            let long = usable.prefix(2).allSatisfy(\.signal.finished) ? "\(both) — вы их досмотрели" : both
            return Reason(kind: .similarToMany, short: short, long: long, evidence: proof)
        }
        let name = first.title.name
        let short = RussianText.fitQuoted("Похоже на ", name)
        if first.signal.isLoved {
            return Reason(
                kind: .loved, short: short, long: "Похоже на \(RussianText.quoted(name)) — вы отметили это как любимое",
                evidence: proof,
            )
        }
        let long: String = if first.signal.finished {
            "Потому что вы досмотрели \(RussianText.quoted(name))"
        } else if first.signal.explicitLevel != nil {
            "Потому что вы оценили \(RussianText.quoted(name))"
        } else if first.signal.state == .started {
            "Потому что вы смотрите \(RussianText.quoted(name))"
        } else {
            "Похоже на \(RussianText.quoted(name))"
        }
        return Reason(kind: .becauseWatched, short: short, long: long, evidence: proof)
    }

    /// «Следующая часть после фильма «Дюна»» / «Вышел 3-й сезон — вы досмотрели 2-й».
    static func continuationReason(_ title: Int, evidence: Evidence, core: EngineCore) -> Reason? {
        if let board = evidence.board, board.kind == .franchise {
            guard let previousId = evidence.anchorIds.first, let previous = core.titleIndex[previousId] else { return nil }
            let prev = core.titles[previous]
            let noun = RussianText.kindGenitive(FeatureTable.kind(of: prev))
            let short = RussianText.fit([
                RussianText.fitQuoted("Продолжение \(noun) ", prev.name),
                "Следующая часть франшизы",
            ])
            return Reason(
                kind: .nextPart, short: short,
                long: "Следующая часть после \(noun) \(RussianText.quoted(prev.name))", evidence: evidence,
            )
        }
        let series = core.titles[title]
        let signal = core.signal(title)
        guard let seasons = series.seasons, seasons > 0 else {
            return Reason(kind: .newSeason, short: "Вышли новые серии", long: "Вышли новые серии — вы смотрели этот сериал", evidence: evidence)
        }
        let short = "Вышел \(RussianText.ordinal(seasons)) сезон"
        guard let userSeason = evidence.count, userSeason > 0, userSeason < seasons else {
            return Reason(kind: .newSeason, short: short, long: short, evidence: evidence)
        }
        let verb = signal?.state == .seen ? "досмотрели" : "смотрели"
        return Reason(
            kind: .newSeason, short: short, long: "\(short) — вы \(verb) \(RussianText.ordinal(userSeason))", evidence: evidence,
        )
    }

    /// «Из закладок «На выходные»» / «Ждёт в «Досмотреть»» / «Вы отслеживаете этот сериал».
    static func intentReason(_ title: Int, evidence: Evidence, core: EngineCore) -> Reason? {
        switch evidence.origin {
        case .bookmark:
            guard let folder = evidence.folder else { return nil }
            return Reason(
                kind: .bookmark, short: RussianText.fitQuoted("Из закладок ", folder),
                long: "Из закладок \(RussianText.quoted(folder))", evidence: evidence,
            )
        case .accountList:
            return Reason(
                kind: .canStart, short: "Ждёт в «Досмотреть»",
                long: "В вашем списке «Досмотреть» — ещё не начато", evidence: evidence,
            )
        case .followed:
            let noun = RussianText.kindAccusative(FeatureTable.kind(of: core.titles[title]))
            return Reason(kind: .canStart, short: "Вы отслеживаете", long: "Вы отслеживаете этот \(noun)", evidence: evidence)
        case .interest:
            return Reason(kind: .canStart, short: "Вы хотели посмотреть", long: "Вы отметили «Хочу посмотреть»", evidence: evidence)
        case nil:
            return nil
        }
    }

    /// «Режиссёр Дени Вильнёв — вы смотрели 3 фильма» / «В ролях: Мэттью Макконахи — вы смотрели 4 работы».
    static func personReason(_ evidence: Evidence, core: EngineCore, options: ReasonOptions) -> Reason? {
        guard let person = evidence.person, let board = evidence.board, !options.excludedPersons.contains(person.id) else {
            return nil
        }
        let titles = positiveTitles(with: person.id, role: board.kind, core: core)
        guard titles.count >= core.weights.peopleMinTitles else { return nil }
        let allFilms = titles.allSatisfy { !core.titles[$0].isSeries }
        let counted = allFilms
            ? RussianText.count(titles.count, "фильм", "фильма", "фильмов")
            : RussianText.count(titles.count, "работу", "работы", "работ")
        let proof = Evidence(board: board, person: person, count: titles.count)
        let surname = RussianText.surname(person.name)
        if board.kind == .director {
            return Reason(
                kind: .person,
                short: RussianText.fit(["Режиссёр \(person.name)", "Режиссёр \(surname)", "Снова этот режиссёр"]),
                long: "Режиссёр \(person.name) — вы смотрели \(counted)", evidence: proof,
            )
        }
        return Reason(
            kind: .person,
            short: RussianText.fit(["В ролях: \(person.name)", "В ролях: \(surname)", "Снова знакомые лица"]),
            long: "В ролях: \(person.name) — вы смотрели \(counted)", evidence: proof,
        )
    }

    /// The user's positive titles with this person in this role (a real count for «3 фильма»).
    static func positiveTitles(with personId: String, role: BoardKind, core: EngineCore) -> [Int] {
        var result: [Int] = []
        for signal in core.orderedSignals where signal.weight > 0 {
            guard let index = core.titleIndex[signal.titleId] else { continue }
            let title = core.titles[index]
            let people = role == .director ? title.directors : Array(title.actors.prefix(5))
            if people.contains(where: { $0.id == personId }) { result.append(index) }
        }
        return result
    }

    /// «9 место в «Лучшие криминальные сериалы 2023»» / «Из подборки «Северный нуар»».
    static func boardReason(_ board: BoardRef) -> Reason? {
        let evidence = Evidence(board: board)
        switch board.kind {
        case .list:
            guard let rank = board.rank else {
                return Reason(
                    kind: .collection, short: RussianText.fitQuoted("Из списка ", board.name),
                    long: "Из списка \(RussianText.quoted(board.name))", evidence: evidence,
                )
            }
            // «Лучшие детективы 2002 года» → «№ 1 · детективы 2002»: the year must survive the cut, or a place in one
            // year's list reads as the best of all time.
            return Reason(
                kind: .rankedList, short: RussianText.fit("№ \(rank) · " + RussianText.listShortName(board.name)),
                long: "\(rank) место в \(RussianText.quoted(board.name))", evidence: evidence,
            )
        case .collection:
            return Reason(
                kind: .collection, short: RussianText.fitQuoted("Из подборки ", board.name),
                long: "Из подборки \(RussianText.quoted(board.name))", evidence: evidence,
            )
        case .franchise, .director, .actor:
            return nil
        }
    }

    /// «Ваше сочетание: детектив · Скандинавия».
    static func featureReason(_ title: Int, core: EngineCore) -> Reason? {
        let features = AffinitySource.topFeatures(of: title, core: core, limit: 2)
            .filter { core.table.keys[$0].group != .collection }
        guard let first = features.first else { return nil }
        let names = features.map { featureLabel($0, core: core) }
        let evidence = Evidence(
            count: AffinitySource.sharedPositiveCount(features, core: core), features: features.map { core.table.keys[$0] },
        )
        if names.count >= 2 {
            let pair = names.prefix(2).joined(separator: " · ")
            return Reason(
                kind: .featureCombo,
                short: RussianText.fit(["Ваше: \(pair)", "В вашем вкусе: \(names[0])", "В вашем вкусе"]),
                long: "Ваше сочетание: \(pair)", evidence: evidence,
            )
        }
        let name = featureLabel(first, core: core)
        return Reason(
            kind: .featureCombo, short: RussianText.fit(["В вашем вкусе: \(name)", "В вашем вкусе"]),
            long: "В вашем вкусе: \(name)", evidence: evidence,
        )
    }

    /// «Критики хвалят: RT 94 % · Metacritic 81» (only with strong critic scores).
    static func criticsReason(_ title: TitleFeatures) -> Reason? {
        let rt = title.rtCritic.flatMap { $0 >= 75 ? $0 : nil }
        let mc = title.metacritic.flatMap { $0 >= 70 ? $0 : nil }
        guard rt != nil || mc != nil else { return nil }
        let longParts = [rt.map { "RT \($0)\u{00A0}%" }, mc.map { "Metacritic \($0)" }].compactMap(\.self)
        let shortParts = [rt.map { "RT \($0)\u{00A0}%" }, mc.map { "MC \($0)" }].compactMap(\.self)
        return Reason(
            kind: .critics,
            short: RussianText.fit(["Критики: " + shortParts.joined(separator: " · "), "Критики: " + (shortParts.first ?? "")]),
            long: "Критики хвалят: " + longParts.joined(separator: " · "), evidence: Evidence(),
        )
    }

    /// «Что-то новое: корейское кино, КП 8,0».
    static func discoveryReason(_ title: Int, evidence: Evidence, core: EngineCore) -> Reason? {
        let item = core.titles[title]
        let novel = evidence.features.isEmpty
            ? ExplorationSource.novelFeatures(of: title, core: core).map { core.table.keys[$0] }
            : evidence.features
        let kind = FeatureTable.kind(of: item)
        let what: String? = if let country = novel.first(where: { $0.group == .country }),
                               let name = displayName(country, core: core)
        {
            RussianText.countryPhrase(name, kind: kind)
        } else if let genre = novel.first(where: { $0.group == .genre }), let name = displayName(genre, core: core) {
            RussianText.genreTag(name)
        } else {
            nil
        }
        guard let what else { return nil }
        let rating = ratingLabel(item)
        let long = rating.map { "Что-то новое: \(what), \($0)" } ?? "Что-то новое: \(what)"
        return Reason(
            kind: .discovery, short: RussianText.fit(["Что-то новое: \(what)", "Новое: \(what)", "Что-то новое для вас"]),
            long: long, evidence: Evidence(features: novel),
        )
    }

    /// «Новинка в вашем жанре» (only when the main genre is liked).
    static func newReleaseReason(_ title: Int, core: EngineCore) -> Reason? {
        guard let genre = core.table.primaryGenre[title], core.profile.affinity[genre] > 0.1 else { return nil }
        let item = core.titles[title]
        let tag = RussianText.genreTag(core.table.names[genre])
        let long = item.year.map { "Новинка \($0) года: \(tag) — ваш жанр" } ?? "Новинка: \(tag) — ваш жанр"
        return Reason(
            kind: .trending, short: "Новинка в вашем жанре", long: long,
            evidence: Evidence(features: [core.table.keys[genre]]),
        )
    }

    /// For a taste still empty: «Популярно: КП 8,0 · IMDb 7,9».
    static func popularReason(_ title: Int, core: EngineCore) -> Reason? {
        let item = core.titles[title]
        guard let votes = QualityFreshSource.popularity(item), votes >= 1000 else { return nil }
        let ratings = [item.kpRating.map { "КП \(RussianText.rating($0))" }, item.imdbRating.map { "IMDb \(RussianText.rating($0))" }]
            .compactMap(\.self)
        let long = ratings.isEmpty ? "Популярно на сайте" : "Популярно: " + ratings.joined(separator: " · ")
        return Reason(
            kind: .trending, short: RussianText.fit([long, "Популярно на сайте"]), long: long,
            evidence: Evidence(count: votes),
        )
    }

    /// «Следующая серия: 2 сезон, 5 серия» for a series in progress («Своё»).
    static func nextEpisodeReason(_ resume: EpisodeRef, titleId: String) -> Reason {
        let place = "\(resume.season) сезон, \(resume.episode) серия"
        let evidence = Evidence(anchorIds: [titleId], count: resume.episode)
        if resume.isNext {
            return Reason(
                kind: .nextEpisode, short: RussianText.fit(["Дальше: \(place)", "Следующая серия"]),
                long: "Следующая серия: \(place)", evidence: evidence,
            )
        }
        return Reason(
            kind: .nextEpisode, short: RussianText.fit(["Продолжить: \(place)", "Продолжить просмотр"]),
            long: "Вы остановились здесь: \(place)", evidence: evidence,
        )
    }

    /// When no template holds: the liked features, something new, the rating, or plainly «по вашему вкусу».
    static func fallback(for title: Int, core: EngineCore, options: ReasonOptions) -> Reason {
        if !options.excludedKinds.contains(.featureCombo), let reason = featureReason(title, core: core) { return reason }
        if let reason = discoveryReason(title, evidence: Evidence(), core: core) { return reason }
        if let rating = ratingLabel(core.titles[title]), let q = core.qualityRating[title], q >= 7 {
            return Reason(kind: .critics, short: "Высокий рейтинг: \(rating)", long: "Высокий рейтинг: \(rating)", evidence: Evidence())
        }
        return Reason(kind: .featureCombo, short: "Может понравиться", long: "Подобрано по вашему вкусу", evidence: Evidence())
    }

    // MARK: Labels

    /// «КП 8,0», else «IMDb 7,9».
    static func ratingLabel(_ title: TitleFeatures) -> String? {
        if let kp = title.kpRating, kp > 0 { return "КП \(RussianText.rating(kp))" }
        if let imdb = title.imdbRating, imdb > 0 { return "IMDb \(RussianText.rating(imdb))" }
        return nil
    }

    static func displayName(_ key: FeatureKey, core: EngineCore) -> String? {
        core.table.id(of: key).map { core.table.names[$0] }
    }

    /// A feature as it reads inside a sentence or a tag: «детектив», «Скандинавия», «2010-е», «реж. Финчер».
    static func featureLabel(_ feature: Int, core: EngineCore) -> String {
        let key = core.table.keys[feature]
        let name = core.table.names[feature]
        switch key.group {
        case .genre: return RussianText.genreTag(name)
        case .country, .decade, .collection, .list: return name
        case .director: return "реж. \(RussianText.surname(name))"
        case .actor: return name
        case .kind: return TitleKind(rawValue: key.value).map { RussianText.kindAccusative($0) } ?? name.lowercased()
        case .duration: return name
        }
    }

    /// Up to three tags: the title's strongest liked features and its format («мини-сериал · 6 серий», «Завершён»,
    /// «1 ч 38 мин»), with the preferred voice-over when the page lists it.
    static func tags(for title: Int, core: EngineCore) -> [String] {
        let item = core.titles[title]
        var tags: [String] = AffinitySource.topFeatures(of: title, core: core, limit: 2)
            .filter { core.table.keys[$0].group != .collection && core.table.keys[$0].group != .kind }
            .map { featureLabel($0, core: core) }
        if tags.isEmpty, let genre = core.table.primaryGenre[title] {
            tags.append(RussianText.genreTag(core.table.names[genre]))
        }
        if let preferred = core.settings.preferredVoiceOver, !preferred.isEmpty,
           let voice = item.voiceOvers.first(where: { TextKey.normalized($0).contains(TextKey.normalized(preferred)) })
        {
            tags = Array(tags.prefix(1)) + ["озвучка \(voice)"]
        }
        if let format = formatTag(item, weights: core.weights) { tags.append(format) }
        return Array(tags.prefix(3))
    }

    /// «мини-сериал · 6 серий», «3 сезона · завершён», «1 ч 38 мин».
    static func formatTag(_ title: TitleFeatures, weights: Weights) -> String? {
        if title.isSeries {
            var parts: [String] = []
            let episodes = title.releasedEpisodes
            if (title.seasons ?? 1) <= 1, let episodes, episodes > 0, episodes <= weights.miniSeriesMaxEpisodes {
                parts.append("мини-сериал")
                parts.append(RussianText.count(episodes, "серия", "серии", "серий"))
            } else if let seasons = title.seasons, seasons > 1 {
                parts.append(RussianText.count(seasons, "сезон", "сезона", "сезонов"))
            } else if let minutes = title.durationMin, minutes > 0 {
                parts.append("серии по \(minutes) мин")
            }
            if title.ended == true { parts.append(parts.isEmpty ? "Завершён" : "завершён") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        guard let minutes = title.durationMin, minutes > 0 else { return nil }
        return RussianText.duration(minutes)
    }
}
