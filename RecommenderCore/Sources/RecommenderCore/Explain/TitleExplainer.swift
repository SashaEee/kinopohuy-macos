import Foundation

/// «Почему это?» and «Вам подойдёт?» (§2.5).
enum TitleExplainer {
    // MARK: «Почему это?»

    /// The reason, the top three contributions as sentences, the graph path, and what «Меньше такого» and
    /// «Не учитывать «X»» would act on.
    static func explanation(for scored: ScoredTitle, reason: Reason, core: EngineCore) -> Explanation {
        let weights = core.weights
        var parts: [(value: Double, line: String)] = []
        var tasteValue = weights.scoreAffinity * max(0, scored.affinity)
        for contribution in scored.contributions {
            if contribution.source == .affinity {
                tasteValue += contribution.value
                continue
            }
            if let line = sentence(for: contribution, title: scored.title, core: core) {
                parts.append((contribution.value, line))
            }
        }
        if tasteValue > 0, let line = tasteSentence(scored.title, core: core) { parts.append((tasteValue, line)) }
        if let line = ratingsSentence(core.titles[scored.title]) {
            parts.append((weights.scoreQuality * scored.quality, line))
        }
        if scored.freshness > 0, let line = freshSentence(scored.title, core: core) {
            parts.append((weights.scoreFresh * scored.freshness, line))
        }
        parts.sort { $0.value > $1.value }
        var lines: [String] = []
        if reason.kind == .nextEpisode { lines.append(reason.long) }
        for part in parts where !lines.contains(part.line) && lines.count < 3 {
            lines.append(part.line)
        }
        if lines.isEmpty { lines.append(reason.long) }

        let path = scored.contribution(.graph)?.evidence.path.nilIfEmpty
            ?? scored.contribution(.continuation)?.evidence.path.nilIfEmpty
            ?? []
        let mainFeature = reason.evidence.features.first
            ?? AffinitySource.topFeatures(of: scored.title, core: core, limit: 1).first.map { core.table.keys[$0] }
            ?? core.table.primaryGenre[scored.title].map { core.table.keys[$0] }
        let mainAnchor = reason.evidence.anchorIds.first { $0 != core.titles[scored.title].id }
            ?? scored.contribution(.graph)?.evidence.anchorIds.first
        return Explanation(
            titleId: core.titles[scored.title].id, reason: reason, lines: lines, path: path, mainFeature: mainFeature,
            mainAnchorId: mainAnchor,
        )
    }

    static func sentence(for contribution: SourceContribution, title: Int, core: EngineCore) -> String? {
        let evidence = contribution.evidence
        switch contribution.source {
        case .graph:
            return graphSentence(evidence, core: core)
        case .continuation:
            return ReasonBuilder.continuationReason(title, evidence: evidence, core: core)?.long
        case .intent:
            return ReasonBuilder.intentReason(title, evidence: evidence, core: core)?.long
        case .people:
            return ReasonBuilder.personReason(evidence, core: core, options: ReasonOptions())?.long
        case .qualityFresh:
            if let board = evidence.board, board.rank != nil { return ReasonBuilder.boardReason(board)?.long }
            if evidence.count != nil, evidence.features.isEmpty { return ReasonBuilder.popularReason(title, core: core)?.long }
            return ReasonBuilder.newReleaseReason(title, core: core)?.long
        case .exploration:
            return ReasonBuilder.discoveryReason(title, evidence: evidence, core: core).map { "\($0.long) — для разнообразия" }
        case .affinity:
            return tasteSentence(title, core: core)
        }
    }

    /// «Похоже на «Мост» и «Убийство» — вы их досмотрели» / «Похоже на «Мост» — вы досмотрели этот сериал».
    static func graphSentence(_ evidence: Evidence, core: EngineCore) -> String? {
        let anchors: [(title: TitleFeatures, signal: TitleSignal)] = evidence.anchorIds.compactMap { id in
            guard let index = core.titleIndex[id], let signal = core.signals[id],
                  signal.weight >= core.weights.reasonAnchorMinWeight
            else { return nil }
            return (core.titles[index], signal)
        }
        guard let first = anchors.first else {
            guard evidence.path.count == 3 else { return nil }
            return "Связано с вашей историей: \(evidence.path.joined(separator: " → "))"
        }
        if anchors.count >= 2 {
            let names = "\(RussianText.quoted(first.title.name)) и \(RussianText.quoted(anchors[1].title.name))"
            let tail = anchors.prefix(2).allSatisfy(\.signal.finished) ? "вы их досмотрели" : "они в вашей истории"
            return "Похоже на \(names) — \(tail)"
        }
        let noun = RussianText.kindAccusative(FeatureTable.kind(of: first.title))
        let tail: String = if first.signal.isLoved {
            "вы отметили это как любимое"
        } else if first.signal.finished {
            "вы досмотрели этот \(noun)"
        } else if first.signal.explicitLevel != nil {
            "вы оценили этот \(noun)"
        } else {
            "вы смотрите этот \(noun)"
        }
        return "Похоже на \(RussianText.quoted(first.title.name)) — \(tail)"
    }

    /// «Детектив · Скандинавия — 7 ваших досмотренных».
    static func tasteSentence(_ title: Int, core: EngineCore) -> String? {
        let features = AffinitySource.topFeatures(of: title, core: core, limit: 2)
            .filter { core.table.keys[$0].group != .collection }
        guard !features.isEmpty else { return nil }
        let label = features.map { ReasonBuilder.featureLabel($0, core: core) }.joined(separator: " · ")
        var finished = 0
        for signal in core.orderedSignals where signal.weight > 0 && signal.finished {
            guard let index = core.titleIndex[signal.titleId] else { continue }
            if features.allSatisfy({ SortedInts.contains(core.table.ofTitle[index], $0) }) { finished += 1 }
        }
        let capitalised = label.prefix(1).uppercased() + label.dropFirst()
        guard finished > 0 else { return "\(capitalised) — совпадает с вашим вкусом" }
        return "\(capitalised) — \(finished) \(RussianText.plural(finished, "ваш досмотренный", "ваших досмотренных", "ваших досмотренных"))"
    }

    /// «IMDb 8,1 · КП 7,9 · RT 94 % · Metacritic 81».
    static func ratingsSentence(_ title: TitleFeatures) -> String? {
        let parts = [
            title.imdbRating.map { "IMDb \(RussianText.rating($0))" },
            title.kpRating.map { "КП \(RussianText.rating($0))" },
            title.rtCritic.map { "RT \($0)\u{00A0}%" },
            title.metacritic.map { "Metacritic \($0)" },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func freshSentence(_ title: Int, core: EngineCore) -> String? {
        if core.newSeasons[title] != nil, let seasons = core.titles[title].seasons {
            return "\(RussianText.ordinal(seasons)) сезон вышел недавно"
        }
        guard let year = core.titles[title].year else { return "Новинка" }
        return "Новинка \(year) года"
    }

    // MARK: «Вам подойдёт?»

    /// fit(t): the score parts every pool title has, no matter whether a source picked it — taste, quality,
    /// freshness, closeness to anchors and to disliked titles.
    static func fitScores(core: EngineCore) -> [Double] {
        let seeds = Set(core.profile.seeds.map(\.title))
        var maxRank: Double = 0
        for title in 0..<core.titles.count where !seeds.contains(title) {
            maxRank = max(maxRank, core.rankForYou[title])
        }
        let weights = core.weights
        return (0..<core.titles.count).map { title in
            let graph = maxRank > 0 ? (core.rankForYou[title] / maxRank).squareRoot() : 0
            return weights.scoreAffinity * core.profile.titleAffinity[title] + weights.scoreQuality * core.quality[title]
                + weights.scoreFresh * core.freshness[title] - weights.scoreNegProximity * core.negProximity[title]
                + 0.5 * graph
        }
    }

    static func verdict(for title: Int, fitScores: [Double], sortedFit: [Double], core: EngineCore) -> FitVerdict {
        let item = core.titles[title]
        if let reason = core.filters.settingsReason(title: item, features: core.table.ofTitle[title], signal: core.signal(title)),
           [.excludedKind, .excludedGenre, .excludedFeature, .age, .notForMe].contains(reason)
        {
            return FitVerdict(level: .unlikely, pros: [], cons: [excludedCon(reason, title: title, core: core)])
        }
        let score = fitScores[title]
        let below = lowerBound(sortedFit, score)
        let percentile = sortedFit.isEmpty ? 0.5 : Double(below) / Double(sortedFit.count)
        let weights = core.weights
        let level: FitVerdict.Level = percentile >= weights.fitLikelyPercentile
            ? .likely : (percentile < weights.fitUnlikelyPercentile ? .unlikely : .maybe)
        return FitVerdict(level: level, pros: Array(pros(for: title, core: core).prefix(2)), cons: Array(cons(for: title, core: core).prefix(1)))
    }

    static func lowerBound(_ sorted: [Double], _ value: Double) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Pluses, strongest first: the user's genre with its place, a liked director, a close anchor, high ratings,
    /// a liked country.
    static func pros(for title: Int, core: EngineCore) -> [String] {
        var result: [String] = []
        let item = core.titles[title]
        if let genre = core.table.primaryGenre[title], core.profile.affinity[genre] > 0.1 {
            let tag = RussianText.genreTag(core.table.names[genre])
            let place = genrePlace(genre, core: core)
            result.append(place <= 5 ? "\(tag) — ваш жанр № \(place)" : "\(tag) — в вашем вкусе")
        }
        for person in item.directors {
            guard let feature = core.table.id(of: FeatureKey(.director, person.id)), core.profile.affinity[feature] > 0.1
            else { continue }
            let count = ReasonBuilder.positiveTitles(with: person.id, role: .director, core: core).filter { $0 != title }.count
            guard count >= 2 else { continue }
            result.append("\(person.name): вы смотрели \(RussianText.count(count, "работу", "работы", "работ"))")
            break
        }
        let anchors = core.profile.anchors.filter { $0.weight >= core.weights.reasonAnchorMinWeight }
        if let link = GraphEvidence.links(to: title, anchors: anchors, graph: core.graph).first {
            result.append("похоже на \(RussianText.quoted(core.titles[link.anchor.title].name))")
        }
        if let rating = core.qualityRating[title], rating >= 7.5, let ratings = ratingsSentence(item) {
            result.append(ratings)
        }
        for country in item.countries {
            guard let feature = core.table.id(of: FeatureKey(.country, country)), core.profile.affinity[feature] > 0.15
            else { continue }
            result.append("\(country) — в вашем вкусе")
            break
        }
        return result
    }

    /// Minuses, strongest first: close to something disliked, a disliked genre, too long, a weak rating, many
    /// seasons for someone who mostly watches films.
    static func cons(for title: Int, core: EngineCore) -> [String] {
        var result: [String] = []
        let item = core.titles[title]
        let disliked = core.profile.negativeAnchors
        if core.negProximity[title] >= 0.5, let link = GraphEvidence.links(to: title, anchors: disliked, graph: core.graph).first {
            result.append("похоже на \(RussianText.quoted(core.titles[link.anchor.title].name)) — вам не понравилось")
        }
        for genre in core.table.genres[title] where core.profile.affinity[genre] < -0.15 {
            result.append("\(RussianText.genreTag(core.table.names[genre])) — не ваш жанр")
            break
        }
        if !item.isSeries, let minutes = item.durationMin, minutes > max(140, typicalFilmMinutes(core: core) + 30) {
            result.append("длинный: \(RussianText.duration(minutes))")
        }
        if let rating = core.qualityRating[title], rating < 6, let label = ReasonBuilder.ratingLabel(item) {
            result.append("невысокий рейтинг: \(label)")
        }
        if item.isSeries, let seasons = item.seasons, seasons >= 3, core.profile.summary.seriesShare < 0.2,
           core.profile.positiveCount >= 5
        {
            result.append("\(RussianText.count(seasons, "сезон", "сезона", "сезонов")), а вы чаще смотрите фильмы")
        }
        return result
    }

    static func excludedCon(_ reason: FilterReason, title: Int, core: EngineCore) -> String {
        let item = core.titles[title]
        switch reason {
        case .excludedKind:
            return "Исключено в настройках: \(FeatureTable.kind(of: item).map { RussianText.kindPlural($0).lowercased() } ?? "этот вид")"
        case .excludedGenre:
            let genre = core.table.genres[title].first { core.filters.excludedGenres.contains($0) }
            return "Исключено в настройках: \(genre.map { RussianText.genreTag(core.table.names[$0]) } ?? "жанр")"
        case .age:
            return "Выше предела возраста: \(item.age.map { "\($0)+" } ?? "")"
        case .notForMe:
            return "Вы отметили «Не моё»"
        default:
            return "Исключено вашими настройками"
        }
    }

    /// The place of a genre among the user's liked genres (1 = favourite).
    static func genrePlace(_ genre: Int, core: EngineCore) -> Int {
        let mine = core.profile.affinity[genre]
        var place = 1
        for feature in 0..<core.table.count where core.table.keys[feature].group == .genre && feature != genre {
            let other = core.profile.affinity[feature]
            if other > mine || (other == mine && core.table.keys[feature] < core.table.keys[genre]) { place += 1 }
        }
        return place
    }

    /// The median length of films the user finished (120 minutes when there are fewer than three).
    static func typicalFilmMinutes(core: EngineCore) -> Int {
        var minutes: [Int] = []
        for signal in core.orderedSignals where signal.finished {
            guard let index = core.titleIndex[signal.titleId], !core.titles[index].isSeries,
                  let length = core.titles[index].durationMin
            else { continue }
            minutes.append(length)
        }
        guard minutes.count >= 3 else { return 120 }
        return minutes.sorted()[minutes.count / 2]
    }
}

extension Array {
    /// nil for an empty array (so `??` can fall through to the next candidate).
    fileprivate var nilIfEmpty: Self? { isEmpty ? nil : self }
}
