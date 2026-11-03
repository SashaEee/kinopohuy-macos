import Accelerate
import Foundation
import GRDB
import NaturalLanguage
import RecommenderCore

/// «Похоже по сюжету»: each read page's description becomes a vector (macOS's own contextual embedding for Cyrillic,
/// on this Mac, nothing sent anywhere), and titles are close when their descriptions mean similar things. The vectors
/// are kept in `title_vector`; a few dozen new ones per rebuild, so a rebuild stays quick while the index catches up.
/// Raw averaged vectors all point roughly the same way (every comparison comes out 0.8–0.98), and their strongest
/// directions say more about a text's length and style than its story; so they're centred on the pool's mean and
/// stripped of their top three principal components («all but the top»): then a heist is near a heist.
actor PlotIndex {
    private let database: any DatabaseWriter
    private var model: NLContextualEmbedding?
    private var modelFailed = false
    private var vectors: [String: [Float]] = [:]
    private var loaded = false
    private var cache: (key: Int, neighbours: [String: [ViewerNeighbour]])?

    /// New vectors per rebuild, neighbours kept per title, and the centred cosine a neighbour needs.
    static let perBuild = 400
    static let keep = 15
    static let minScore: Float = 0.3
    /// Principal components removed (style and length, not story).
    static let removedComponents = 3
    /// Descriptions shorter than this say too little to compare.
    static let minLength = 60

    init(database: any DatabaseWriter) {
        self.database = database
    }

    /// The pool's plot neighbours (title id → closest titles, best first, 0…1), for the titles with a description.
    func neighbours(for titles: [TitleFeatures]) async -> [String: [ViewerNeighbour]] {
        await loadVectors()
        await embedMissing(titles)

        let ids = titles.map(\.id).filter { vectors[$0] != nil }.sorted()
        guard ids.count >= 2 else { return [:] }
        var hasher = Hasher()
        hasher.combine(ids)
        let key = hasher.finalize()
        if let cache, cache.key == key { return cache.neighbours }

        let result = Self.nearest(ids: ids, vectors: ids.compactMap { vectors[$0] })
        cache = (key, result)
        return result
    }

    // MARK: Vectors

    private func loadVectors() async {
        guard !loaded else { return }
        loaded = true
        let rows: [(String, Data)] = (try? await database.read { db in
            try Row.fetchAll(db, sql: "SELECT titleId, vector FROM title_vector").map { ($0["titleId"], $0["vector"]) }
        }) ?? []
        for (id, data) in rows {
            vectors[id] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
    }

    private func embedMissing(_ titles: [TitleFeatures]) async {
        let missing = titles.filter { vectors[$0.id] == nil && ($0.synopsis?.count ?? 0) >= Self.minLength }.prefix(Self.perBuild)
        guard !missing.isEmpty, let model = await readyModel() else { return }
        var fresh: [(String, [Float])] = []
        for title in missing {
            guard let text = title.synopsis, let vector = Self.embed(text, model: model) else { continue }
            vectors[title.id] = vector
            fresh.append((title.id, vector))
        }
        guard !fresh.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        _ = try? await database.write { [fresh] db in
            for (id, vector) in fresh {
                let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                try db.execute(
                    sql: "INSERT OR REPLACE INTO title_vector (titleId, vector, updatedAt) VALUES (?, ?, ?)",
                    arguments: [id, data, now],
                )
            }
        }
    }

    /// The model, its assets fetched by macOS once (a small download the system manages); nil when it can't be had.
    private func readyModel() async -> NLContextualEmbedding? {
        if let model { return model }
        guard !modelFailed, let candidate = NLContextualEmbedding(script: .cyrillic) else {
            modelFailed = true
            return nil
        }
        if !candidate.hasAvailableAssets {
            let result: NLContextualEmbedding.AssetsResult = await withCheckedContinuation { continuation in
                candidate.requestAssets { result, _ in continuation.resume(returning: result) }
            }
            guard result == .available else {
                // Not now (offline, say): asked again next launch.
                return nil
            }
        }
        do {
            try candidate.load()
            model = candidate
            return candidate
        } catch {
            modelFailed = true
            return nil
        }
    }

    /// The mean of the description's token vectors.
    private static func embed(_ text: String, model: NLContextualEmbedding) -> [Float]? {
        let text = String(text.prefix(1200))
        guard let result = try? model.embeddingResult(for: text, language: .russian) else { return nil }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0.0
        result.enumerateTokenVectors(in: text.startIndex ..< text.endIndex) { vector, _ in
            for i in 0 ..< min(vector.count, sum.count) { sum[i] += vector[i] }
            count += 1
            return true
        }
        guard count > 0 else { return nil }
        return sum.map { Float($0 / count) }
    }

    // MARK: Neighbours

    /// Centred vectors without their top components, normalised; all pairs at once (one matrix product); each title's
    /// best `keep` above the bar.
    private static func nearest(ids: [String], vectors: [[Float]]) -> [String: [ViewerNeighbour]] {
        let n = vectors.count
        let d = vectors[0].count
        var mean = [Float](repeating: 0, count: d)
        for vector in vectors { vDSP_vadd(mean, 1, vector, 1, &mean, 1, vDSP_Length(d)) }
        var scale = 1 / Float(n)
        vDSP_vsmul(mean, 1, &scale, &mean, 1, vDSP_Length(d))

        var matrix = [Float](repeating: 0, count: n * d)
        for (row, vector) in vectors.enumerated() {
            var centred = [Float](repeating: 0, count: d)
            vDSP_vsub(mean, 1, vector, 1, &centred, 1, vDSP_Length(d))
            var norm: Float = 0
            vDSP_svesq(centred, 1, &norm, vDSP_Length(d))
            var inverse = norm > 0 ? 1 / norm.squareRoot() : 0
            vDSP_vsmul(centred, 1, &inverse, &centred, 1, vDSP_Length(d))
            matrix.replaceSubrange(row * d ..< (row + 1) * d, with: centred)
        }
        var transposed = [Float](repeating: 0, count: d * n)
        vDSP_mtrans(matrix, 1, &transposed, 1, vDSP_Length(d), vDSP_Length(n))

        // The top principal components (power iteration on XᵀX with deflation), then each row without them, normalised
        // again.
        var covariance = [Float](repeating: 0, count: d * d)
        vDSP_mmul(transposed, 1, matrix, 1, &covariance, 1, vDSP_Length(d), vDSP_Length(d), vDSP_Length(n))
        var components: [[Float]] = []
        for k in 0 ..< min(removedComponents, n - 1) {
            var v = (0 ..< d).map { Float(($0 * 7919 + k * 104_729) % 997) / 997 - 0.5 }
            for _ in 0 ..< 60 {
                var next = [Float](repeating: 0, count: d)
                vDSP_mmul(covariance, 1, v, 1, &next, 1, vDSP_Length(d), 1, vDSP_Length(d))
                for c in components {
                    var dot: Float = 0
                    vDSP_dotpr(next, 1, c, 1, &dot, vDSP_Length(d))
                    var minus = -dot
                    vDSP_vsma(c, 1, &minus, next, 1, &next, 1, vDSP_Length(d))
                }
                var norm: Float = 0
                vDSP_svesq(next, 1, &norm, vDSP_Length(d))
                guard norm > 0 else { break }
                var inverse = 1 / norm.squareRoot()
                vDSP_vsmul(next, 1, &inverse, &v, 1, vDSP_Length(d))
            }
            components.append(v)
        }
        for row in 0 ..< n {
            var x = Array(matrix[row * d ..< (row + 1) * d])
            for c in components {
                var dot: Float = 0
                vDSP_dotpr(x, 1, c, 1, &dot, vDSP_Length(d))
                var minus = -dot
                vDSP_vsma(c, 1, &minus, x, 1, &x, 1, vDSP_Length(d))
            }
            var norm: Float = 0
            vDSP_svesq(x, 1, &norm, vDSP_Length(d))
            var inverse = norm > 0 ? 1 / norm.squareRoot() : 0
            vDSP_vsmul(x, 1, &inverse, &x, 1, vDSP_Length(d))
            matrix.replaceSubrange(row * d ..< (row + 1) * d, with: x)
        }
        vDSP_mtrans(matrix, 1, &transposed, 1, vDSP_Length(d), vDSP_Length(n))
        var similarity = [Float](repeating: 0, count: n * n)
        vDSP_mmul(matrix, 1, transposed, 1, &similarity, 1, vDSP_Length(n), vDSP_Length(n), vDSP_Length(d))

        var result: [String: [ViewerNeighbour]] = [:]
        for i in 0 ..< n {
            var best: [(Int, Float)] = []
            for j in 0 ..< n where j != i {
                let score = similarity[i * n + j]
                if score >= minScore { best.append((j, score)) }
            }
            guard !best.isEmpty else { continue }
            best.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            result[ids[i]] = best.prefix(keep).map { ViewerNeighbour(titleId: ids[$0.0], score: Double($0.1)) }
        }
        return result
    }
}
