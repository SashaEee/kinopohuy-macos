import Foundation
import Testing
@testable import RecommenderCore

@Suite("Site graph and PageRank (§4.5 S1)")
struct GraphTests {
    func bare(_ id: String, watchAlso: [String] = [], directors: [PersonRef] = [], boards: [BoardRef] = []) -> TitleFeatures {
        TitleFeatures(id: id, path: "/\(id)", level: .page, kind: nil, name: "Т\(id)", directors: directors, boards: boards, watchAlso: watchAlso, fetchedAt: 0)
    }

    func graph(_ titles: [TitleFeatures]) -> TitleGraph {
        let ordered = EngineCore.mergedTitles(titles)
        var index: [String: Int] = [:]
        for (i, title) in ordered.enumerated() { index[title.id] = i }
        return TitleGraph(titles: ordered, titleIndex: index, weights: .default)
    }

    @Test func handCheckedPowerIteration() {
        // A → B («Смотрите также», 1.0) and B → A (the reverse edge, 0.5); C has no edges.
        let graph = graph([bare("1", watchAlso: ["2"]), bare("2"), bare("3")])
        #expect(graph.edges(from: 0).map(\.target) == [1])
        #expect(graph.edges(from: 1).map(\.target) == [0])
        #expect(graph.edges(from: 2).isEmpty)
        // Two steps from A with α = 0.3: r₁ = [0.3, 0.7, 0], r₂ = [0.3 + 0.49, 0.21, 0].
        let two = PersonalizedPageRank.run(graph: graph, seeds: [(0, 1)], alpha: 0.3, iterations: 2)
        #expect(abs(two[0] - 0.79) < 1e-15)
        #expect(abs(two[1] - 0.21) < 1e-15)
        #expect(two[2] == 0)
        // The fixed point: r_A = 0.3 + 0.7·r_B, r_B = 0.7·r_A → r_A = 0.3 / 0.51.
        let converged = PersonalizedPageRank.run(graph: graph, seeds: [(0, 1)], alpha: 0.3, iterations: 500)
        #expect(abs(converged[0] - 0.3 / 0.51) < 1e-9)
        #expect(abs(converged[1] - 0.21 / 0.51) < 1e-9)
        #expect(abs(converged.reduce(0, +) - 1) < 1e-12)
    }

    @Test func danglingMassReturnsToSeeds() {
        let graph = graph([bare("1", watchAlso: ["2"]), bare("2"), bare("3")])
        let rank = PersonalizedPageRank.run(graph: graph, seeds: [(2, 1)], alpha: 0.3, iterations: 20)
        #expect(rank == [0, 0, 1])
        #expect(PersonalizedPageRank.run(graph: graph, seeds: [], alpha: 0.3, iterations: 20) == [0, 0, 0])
    }

    @Test func boardsAndNormalisation() throws {
        let director = Fixture.person("d", "Режиссёр")
        let graph = graph([bare("1", directors: [director]), bare("2", directors: [director])])
        let board = try #require(graph.boardIndex["director:d"])
        #expect(graph.boardMembers[board] == [0, 1])
        #expect(graph.boardSize[board] == 2)
        // The title's only edge goes to the board; the board splits evenly between its members.
        #expect(graph.edges(from: 0).map(\.target) == [graph.titleCount + board])
        #expect(graph.edges(from: graph.titleCount + board).map(\.probability) == [0.5, 0.5])
        for node in 0..<graph.nodeCount {
            let row = graph.edges(from: node)
            if !row.isEmpty { #expect(abs(row.map(\.probability).reduce(0, +) - 1) < 1e-12) }
        }
    }

    @Test func listEdgeWeights() {
        let weights = Weights.default
        #expect(abs(TitleGraph.edgeWeight(kind: .list, rank: 1, size: 10, weights: weights) - 0.8 * 1.45) < 1e-12)
        #expect(abs(TitleGraph.edgeWeight(kind: .list, rank: 10, size: 10, weights: weights) - 0.8) < 1e-12)
        #expect(TitleGraph.edgeWeight(kind: .list, rank: nil, size: 10, weights: weights) == 0.8)
        #expect(TitleGraph.edgeWeight(kind: .franchise, rank: 2, size: 3, weights: weights) == 1)
        #expect(TitleGraph.edgeWeight(kind: .actor, rank: nil, size: 3, weights: weights) == 0.25)
    }

    @Test func pageRankIsBitForBitDeterministic() {
        let titles = SyntheticCatalog.titles(count: 2000)
        let first = graph(titles)
        let second = graph(titles.reversed())
        let seeds = [(node: 3, weight: 1.0), (node: 77, weight: 0.5), (node: 501, weight: 0.8)]
        let a = PersonalizedPageRank.run(graph: first, seeds: seeds, alpha: 0.3, iterations: 20)
        let b = PersonalizedPageRank.run(graph: second, seeds: seeds, alpha: 0.3, iterations: 20)
        #expect(a == b)
        #expect(abs(a.reduce(0, +) - 1) < 1e-9)
    }

    @Test func evidenceWithinTwoHops() throws {
        let list = BoardRef(id: "l", kind: .list, name: "Лучшие детективы", rank: 2, size: 20)
        let titles = [
            Fixture.film("1", "Мост", watchAlso: ["2"]), Fixture.film("2", "Убийство"),
            Fixture.film("3", "Охота", boards: [list]), Fixture.film("4", "Чужак", boards: [list]),
            Fixture.film("5", "Далеко"),
        ]
        let graph = graph(titles)
        let ordered = EngineCore.mergedTitles(titles)
        let anchors = [Anchor(title: 0, id: "1", weight: 1), Anchor(title: 2, id: "3", weight: 0.8)]
        let direct = GraphEvidence.links(to: 1, anchors: anchors, graph: graph)
        #expect(direct.count == 1)
        #expect(direct[0].board == nil)
        #expect(GraphEvidence.path(direct[0], candidate: 1, titles: ordered, graph: graph) == ["«Мост»", "«Смотрите также»", "«Убийство»"])
        let shared = try #require(GraphEvidence.links(to: 3, anchors: anchors, graph: graph).first)
        #expect(shared.anchor.id == "3")
        #expect(GraphEvidence.path(shared, candidate: 3, titles: ordered, graph: graph) == ["«Охота»", "«Лучшие детективы»", "«Чужак»"])
        #expect(GraphEvidence.links(to: 4, anchors: anchors, graph: graph).isEmpty)
        // The two-step walk reaches the shared board's members.
        #expect(graph.twoStepProximity(from: 2)[3] ?? 0 > 0)
        #expect(graph.twoStepProximity(from: 2)[4] == nil)
    }

    @Test func mergedTitlesPreferPagesAndKeepCardBoards() {
        let card = TitleFeatures(id: "1", path: "/1", level: .card, kind: .film, name: "Карточка", boards: [BoardRef(id: "l", kind: .list, name: "Список", rank: 4)], fetchedAt: 10)
        let page = Fixture.film("1", "Страница")
        let merged = EngineCore.mergedTitles([card, page, Fixture.film("10"), Fixture.film("9")])
        #expect(merged.map(\.id) == ["1", "9", "10"])
        #expect(merged[0].name == "Страница")
        #expect(merged[0].boards.map(\.key) == ["list:l"])
    }
}
