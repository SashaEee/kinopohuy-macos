import Foundation

/// A director or actor the user keeps coming back to.
struct FavouritePerson: Sendable, Hashable {
    let person: PersonRef
    let role: BoardKind
    /// Σw over the user's titles with them, and how many of those are positive.
    let weight: Double
    let positiveTitles: Int
}

/// S5: people — directors and actors with Σw ≥ 1.5 over at least two positive titles, and their other titles in the
/// pool (§4.5): «Режиссёр Дени Вильнёв — вы смотрели 3 работы».
enum PeopleSource {
    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .people, hits: hits(core))
    }

    /// The user's people, strongest first (at most `peopleMaxPersons`).
    static func favourites(_ core: EngineCore) -> [FavouritePerson] {
        var totals: [String: (person: PersonRef, role: BoardKind, weight: Double, positive: Int)] = [:]
        for signal in core.orderedSignals where signal.weight != 0 {
            guard let index = core.titleIndex[signal.titleId] else { continue }
            let title = core.titles[index]
            var counted = Set<String>()
            let people = title.directors.map { ($0, BoardKind.director) } + title.actors.prefix(5).map { ($0, BoardKind.actor) }
            for (person, role) in people where !person.id.isEmpty {
                let key = "\(role.rawValue):\(person.id)"
                guard counted.insert(key).inserted else { continue }
                var entry = totals[key] ?? (person, role, 0, 0)
                entry.weight += signal.weight
                if signal.weight > 0 { entry.positive += 1 }
                totals[key] = entry
            }
        }
        let weights = core.weights
        return totals.keys.sorted().compactMap { key -> FavouritePerson? in
            guard let entry = totals[key], entry.weight >= weights.peopleMinWeight, entry.positive >= weights.peopleMinTitles
            else { return nil }
            return FavouritePerson(person: entry.person, role: entry.role, weight: entry.weight, positiveTitles: entry.positive)
        }
        .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : ($0.role.rawValue, $0.person.id) < ($1.role.rawValue, $1.person.id) }
        .prefix(weights.peopleMaxPersons)
        .map(\.self)
    }

    /// Eligible titles of a person in the pool (as director, or among the top-5 actors).
    static func titles(of person: FavouritePerson, core: EngineCore) -> [Int] {
        let feature = core.table.id(of: FeatureKey(person.role == .director ? .director : .actor, person.person.id))
        var result: [Int] = []
        if let feature {
            for title in 0..<core.titles.count where core.isEligible(title) {
                if SortedInts.contains(core.table.ofTitle[title], feature) { result.append(title) }
            }
        }
        // Filmography pages captured as boards add titles whose own page wasn't read yet.
        if let board = core.graph.boardIndex["\(person.role.rawValue):\(person.person.id)"] {
            for title in core.graph.boardMembers[board] where core.isEligible(title) && !result.contains(title) {
                result.append(title)
            }
        }
        return result.sorted()
    }

    static func hits(_ core: EngineCore) -> [SourceHit] {
        var best: [Int: SourceHit] = [:]
        for favourite in favourites(core) {
            let roleFactor = favourite.role == .director ? 1.0 : 0.6
            let board = BoardRef(id: favourite.person.id, kind: favourite.role, name: favourite.person.name)
            for title in titles(of: favourite, core: core) {
                let score = favourite.weight * roleFactor + 0.2 * core.quality[title]
                if let existing = best[title], existing.score >= score { continue }
                best[title] = SourceHit(
                    title: title, score: score,
                    evidence: Evidence(board: board, person: favourite.person, count: favourite.positiveTitles),
                )
            }
        }
        return best.keys.sorted().compactMap { best[$0] }
    }
}
