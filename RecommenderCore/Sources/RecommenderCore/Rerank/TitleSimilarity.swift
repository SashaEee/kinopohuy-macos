import Foundation

/// How alike two titles are for diversity (§4.7 step 4): 0.5·Jaccard(genres) + 0.3·shared boards + 0.2·a shared
/// person; parts of one franchise are identical.
struct TitleSimilarity: Sendable {
    let genres: [[Int]]
    /// Lists, collections (ascending board indices).
    let boards: [[Int]]
    /// Directors and top-3 actors (ascending board indices).
    let people: [[Int]]
    let franchise: [String?]

    init(core: EngineCore) {
        genres = core.table.genres
        var boards = [[Int]](repeating: [], count: core.titles.count)
        var people = [[Int]](repeating: [], count: core.titles.count)
        for title in 0..<core.titles.count {
            for board in core.graph.titleBoards[title] {
                switch core.graph.board(board).kind {
                case .list, .collection: boards[title].append(board)
                case .director, .actor: people[title].append(board)
                case .franchise: break
                }
            }
        }
        self.boards = boards
        self.people = people
        franchise = core.titles.map(\.franchiseId)
    }

    func similarity(_ lhs: Int, _ rhs: Int) -> Double {
        if lhs == rhs { return 1 }
        if let franchise = franchise[lhs], !franchise.isEmpty, franchise == self.franchise[rhs] { return 1 }
        var value: Double = 0
        let lg = genres[lhs]
        let rg = genres[rhs]
        if !lg.isEmpty || !rg.isEmpty {
            let shared = SortedInts.intersectionCount(lg, rg)
            let union = lg.count + rg.count - shared
            if union > 0 { value += 0.5 * Double(shared) / Double(union) }
        }
        let sharedBoards = SortedInts.intersectionCount(boards[lhs], boards[rhs])
        value += 0.3 * min(1, Double(sharedBoards) / 2)
        if SortedInts.intersectionCount(people[lhs], people[rhs]) > 0 { value += 0.2 }
        return value
    }
}
