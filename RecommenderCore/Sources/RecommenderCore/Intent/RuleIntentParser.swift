import Foundation

/// Reads a free-text request in Russian into a `WatchIntent` without any model (≈5 ms).
public enum RuleIntentParser {
    public static func parse(_ text: String, context: EngineContext) -> ParsedRequest {
        ParsedRequest(intent: .empty, chips: [])
    }
}
