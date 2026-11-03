import Foundation

/// The engine's entry point. `prepare` does the heavy work once (title weights, taste profile, the site's graph,
/// candidate scores); the prepared engine then answers Home, «Выбери за меня», «Почему это?» and «Вам подойдёт?»
/// without recomputing. Everything is deterministic for a given input and seed.
public enum Recommender {
    /// Raised whenever the engine's logic or default weights change: pages built by an older engine are rebuilt
    /// rather than shown from the cache.
    public static let version = 4

    public static func prepare(_ input: EngineInput) -> PreparedEngine {
        PreparedEngine(input: input)
    }

    /// Home's page and the ranked pool in one go.
    public static func run(_ input: EngineInput) -> EngineOutput {
        prepare(input).output
    }
}
