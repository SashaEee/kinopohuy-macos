import Foundation

/// The default intent for the moment (weekday evening, Friday night, late night, daytime).
public enum ContextDefaults {
    public static func intent(for context: EngineContext) -> WatchIntent { .empty }
}

/// Applies a critique button to an intent.
public enum CritiqueOps {
    public static func apply(_ critique: Critique, to intent: WatchIntent, current: TitleFeatures?, context: EngineContext) -> WatchIntent { intent }
}

/// «Понял так» chips for an intent, and removing one.
public enum IntentChips {
    public static func chips(for intent: WatchIntent) -> [IntentChip] { [] }
    public static func removing(_ chip: IntentChip, from intent: WatchIntent) -> WatchIntent { intent }
}
