import Foundation

/// The site's graph (§4.5 S1) in CSR arrays: title nodes and «board» nodes (a franchise, a ranked list, a
/// collection, a director, one of the top three actors), plus direct «Смотрите также» edges between titles.
/// Titles come first in the fixed title order, boards after them sorted by key, so every walk over the graph visits
/// nodes in the same order on every run.
struct TitleGraph: Sendable {
    let titleCount: Int
    /// Board `i` is node `titleCount + i`.
    let boards: [BoardRef]
    let boardIndex: [String: Int]
    /// Max of the size the site declares and the members the pool has: what out-degree normalisation divides by.
    let boardSize: [Int]
    /// CSR: node `u`'s out-edges are `target[rowStart[u]..<rowStart[u + 1]]`, with row-stochastic probabilities.
    let rowStart: [Int]
    let target: [Int]
    let probability: [Double]
    /// Boards per title (ascending) with the title→board edge weight, and members per board (ascending).
    let titleBoards: [[Int]]
    let titleBoardWeight: [[Double]]
    let boardMembers: [[Int]]
    /// «Смотрите также» neighbours in either direction (ascending).
    let watchAlso: [[Int]]
    /// A title's 1-based position in its franchise, when known.
    let franchisePosition: [Int?]

    var nodeCount: Int { titleCount + boards.count }

    init(titles: [TitleFeatures], titleIndex: [String: Int], weights: Weights) {
        titleCount = titles.count

        // 1. Board memberships: key → (ref, member → rank).
        var refs: [String: BoardRef] = [:]
        var members: [String: [Int: Int?]] = [:]
        var franchisePosition = [Int?](repeating: nil, count: titles.count)
        func add(_ title: Int, _ ref: BoardRef, rank: Int?) {
            let key = ref.key
            if var known = refs[key] {
                if known.name.isEmpty { known.name = ref.name }
                if let size = ref.size { known.size = max(known.size ?? 0, size) }
                refs[key] = known
            } else {
                refs[key] = ref
            }
            if let existing = members[key]?[title], existing != nil { return }
            members[key, default: [:]][title] = rank
        }
        for (index, title) in titles.enumerated() {
            for board in title.boards where !board.id.isEmpty {
                add(index, board, rank: board.rank)
            }
            if let franchiseId = title.franchiseId, !franchiseId.isEmpty {
                let first = title.franchise.min { $0.position < $1.position }
                let ref = BoardRef(
                    id: franchiseId, kind: .franchise, name: first?.name ?? title.name,
                    size: title.franchise.isEmpty ? nil : title.franchise.count,
                )
                let current = title.franchise.first { $0.isCurrent || $0.titleId == title.id }
                if let current { franchisePosition[index] = current.position }
                add(index, ref, rank: current?.position)
                for part in title.franchise {
                    guard let partId = part.titleId, let partIndex = titleIndex[partId] else { continue }
                    if franchisePosition[partIndex] == nil { franchisePosition[partIndex] = part.position }
                    add(partIndex, ref, rank: part.position)
                }
            }
            for person in title.directors where !person.id.isEmpty {
                add(index, BoardRef(id: person.id, kind: .director, name: person.name), rank: nil)
            }
            for person in title.actors.prefix(3) where !person.id.isEmpty {
                add(index, BoardRef(id: person.id, kind: .actor, name: person.name), rank: nil)
            }
        }

        // 2. Boards in key order.
        let keys = refs.keys.sorted()
        var boardIndex: [String: Int] = [:]
        boardIndex.reserveCapacity(keys.count)
        for (i, key) in keys.enumerated() { boardIndex[key] = i }
        let boards = keys.compactMap { refs[$0] }
        var boardMembers = [[Int]](repeating: [], count: keys.count)
        var boardSize = [Int](repeating: 0, count: keys.count)
        var titleBoardPairs = [[(board: Int, weight: Double)]](repeating: [], count: titles.count)
        var boardEdges = [[(title: Int, weight: Double)]](repeating: [], count: keys.count)
        for (b, key) in keys.enumerated() {
            let ranks = members[key] ?? [:]
            let sortedMembers = ranks.keys.sorted()
            boardMembers[b] = sortedMembers
            let size = max(boards[b].size ?? 0, sortedMembers.count)
            boardSize[b] = size
            let spread = log2(2 + Double(size))
            for member in sortedMembers {
                let rank = ranks[member] ?? nil
                let weight = Self.edgeWeight(kind: boards[b].kind, rank: rank, size: size, weights: weights)
                titleBoardPairs[member].append((b, weight))
                // A board's way out is divided by log₂(2 + size): giant collections don't outweigh everything.
                boardEdges[b].append((member, weight / spread))
            }
        }

        // 3. «Смотрите также»: 1.0 forward, 0.5 back; the stronger wins when both pages list each other.
        var direct = [[Int: Double]](repeating: [:], count: titles.count)
        for (index, title) in titles.enumerated() {
            for otherId in title.watchAlso {
                guard let other = titleIndex[otherId], other != index else { continue }
                direct[index][other] = max(direct[index][other] ?? 0, weights.edgeWatchAlso)
                direct[other][index] = max(direct[other][index] ?? 0, weights.edgeWatchAlsoReverse)
            }
        }

        // 4. CSR, rows normalised to probabilities.
        var rowStart = [Int](repeating: 0, count: titles.count + keys.count + 1)
        var target: [Int] = []
        var probability: [Double] = []
        var titleBoards = [[Int]](repeating: [], count: titles.count)
        var titleBoardWeight = [[Double]](repeating: [], count: titles.count)
        var watchAlso = [[Int]](repeating: [], count: titles.count)
        func appendRow(_ edges: [(Int, Double)]) {
            let total = edges.reduce(0) { $0 + $1.1 }
            guard total > 0 else { return }
            for (to, weight) in edges where weight > 0 {
                target.append(to)
                probability.append(weight / total)
            }
        }
        for index in 0..<titles.count {
            rowStart[index] = target.count
            let neighbours = direct[index].sorted { $0.key < $1.key }
            watchAlso[index] = neighbours.map(\.key)
            let pairs = titleBoardPairs[index].sorted { $0.board < $1.board }
            titleBoards[index] = pairs.map(\.board)
            titleBoardWeight[index] = pairs.map(\.weight)
            appendRow(neighbours.map { ($0.key, $0.value) } + pairs.map { (titles.count + $0.board, $0.weight) })
        }
        for b in 0..<keys.count {
            rowStart[titles.count + b] = target.count
            appendRow(boardEdges[b].map { ($0.title, $0.weight) })
        }
        rowStart[titles.count + keys.count] = target.count

        self.boards = boards
        self.boardIndex = boardIndex
        self.boardSize = boardSize
        self.rowStart = rowStart
        self.target = target
        self.probability = probability
        self.titleBoards = titleBoards
        self.titleBoardWeight = titleBoardWeight
        self.boardMembers = boardMembers
        self.watchAlso = watchAlso
        self.franchisePosition = franchisePosition
    }

    /// Title → board edge weights: franchise 1.0, a ranked list 0.8·(1 + 0.5·(1 − place/N)), a collection 0.6,
    /// a director 0.5, an actor 0.25.
    static func edgeWeight(kind: BoardKind, rank: Int?, size: Int, weights: Weights) -> Double {
        switch kind {
        case .franchise: return weights.edgeFranchise
        case .collection: return weights.edgeCollection
        case .director: return weights.edgeDirector
        case .actor: return weights.edgeActor
        case .list:
            guard let rank, size > 0 else { return weights.edgeList }
            let place = EngineMath.clamp(Double(rank) / Double(size), 0, 1)
            return weights.edgeList * (1 + 0.5 * (1 - place))
        }
    }

    func board(_ index: Int) -> BoardRef { boards[index] }

    /// The node's out-neighbours with their probabilities (for tests and evidence).
    func edges(from node: Int) -> [(target: Int, probability: Double)] {
        guard node >= 0, node < nodeCount else { return [] }
        return (rowStart[node]..<rowStart[node + 1]).map { (target[$0], probability[$0]) }
    }

    /// The two-step walk from one title: where a random step or two from it lands (direct links, shared boards).
    /// It's what «Потому что вы досмотрели «X»» ranks by: every result is within the verifiable two hops.
    func twoStepProximity(from title: Int) -> [Int: Double] {
        var first: [(Int, Double)] = []
        for edge in rowStart[title]..<rowStart[title + 1] {
            first.append((target[edge], probability[edge]))
        }
        var result: [Int: Double] = [:]
        for (node, p1) in first {
            if node < titleCount, node != title { result[node, default: 0] += p1 }
            for edge in rowStart[node]..<rowStart[node + 1] {
                let next = target[edge]
                guard next < titleCount, next != title else { continue }
                result[next, default: 0] += p1 * probability[edge]
            }
        }
        return result
    }
}
