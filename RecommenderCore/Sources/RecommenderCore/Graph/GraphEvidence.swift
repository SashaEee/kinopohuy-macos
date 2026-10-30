import Foundation

/// How a candidate connects to an anchor within two steps: a direct «Смотрите также» edge or a shared board.
struct GraphLink: Sendable, Hashable {
    let anchor: Anchor
    /// nil for a direct «Смотрите также» edge, otherwise the shared board's index.
    let board: Int?
    /// How specific the link is: direct 1.0, a board's edge weight divided by log₂(2 + its size).
    let strength: Double
}

/// The proof behind a graph recommendation (§4.5, «Объяснение»): which anchors reach the candidate in ≤2 hops and
/// along which path, so «Похоже на «Мост»» is always something the user can check on the site.
enum GraphEvidence {
    /// The best link to each anchor that reaches the title, strongest first.
    static func links(to title: Int, anchors: [Anchor], graph: TitleGraph) -> [GraphLink] {
        var links: [GraphLink] = []
        let boardsOfTitle = graph.titleBoards[title]
        for anchor in anchors where anchor.title != title {
            if SortedInts.contains(graph.watchAlso[anchor.title], title) {
                links.append(GraphLink(anchor: anchor, board: nil, strength: 1))
                continue
            }
            let shared = SortedInts.intersection(graph.titleBoards[anchor.title], boardsOfTitle)
            guard !shared.isEmpty else { continue }
            var best: (board: Int, strength: Double)?
            for board in shared {
                let strength = boardStrength(board, graph: graph)
                if let current = best, current.strength >= strength { continue }
                best = (board, strength)
            }
            if let best { links.append(GraphLink(anchor: anchor, board: best.board, strength: best.strength)) }
        }
        return links.sorted {
            let lhs = $0.strength * $0.anchor.weight
            let rhs = $1.strength * $1.anchor.weight
            return lhs != rhs ? lhs > rhs : $0.anchor.title < $1.anchor.title
        }
    }

    static func boardStrength(_ board: Int, graph: TitleGraph) -> Double {
        let ref = graph.board(board)
        let kindWeight: Double = switch ref.kind {
        case .franchise: 1.0
        case .list: 0.8
        case .collection: 0.6
        case .director: 0.5
        case .actor: 0.25
        }
        return kindWeight / log2(2 + Double(graph.boardSize[board]))
    }

    /// «Мост» → «Смотрите также» → «Убийство», or through the shared board.
    static func path(_ link: GraphLink, candidate: Int, titles: [TitleFeatures], graph: TitleGraph) -> [String] {
        let from = RussianText.quoted(titles[link.anchor.title].name)
        let to = RussianText.quoted(titles[candidate].name)
        guard let board = link.board else { return [from, "«Смотрите также»", to] }
        return [from, label(of: graph.board(board)), to]
    }

    /// How a board reads in a path.
    static func label(of board: BoardRef) -> String {
        switch board.kind {
        case .list, .collection: RussianText.quoted(board.name)
        case .franchise: "та же франшиза"
        case .director: "режиссёр \(board.name)"
        case .actor: "в ролях: \(board.name)"
        }
    }
}
