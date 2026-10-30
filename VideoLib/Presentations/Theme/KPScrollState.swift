import SwiftUI

/// Whether a list is being scrolled. Content moving under a still pointer would otherwise light up every card it
/// passes (a ring, a shadow, a spring each); cards ignore the pointer coming in while this is on. One object for the
/// window, so its identity never changes and reading it in a closure invalidates nothing.
@MainActor @Observable
final class KPScrollState {
    var isScrolling = false
}

extension EnvironmentValues {
    @Entry var kpScrollState: KPScrollState? = nil
}

extension View {
    /// Tells the window's scroll state when this scroll view starts and stops moving.
    func kpReportsScrolling() -> some View {
        modifier(KPReportsScrolling())
    }
}

private struct KPReportsScrolling: ViewModifier {
    @Environment(\.kpScrollState) private var scrollState

    func body(content: Content) -> some View {
        content.onScrollPhaseChange { _, phase in
            scrollState?.isScrolling = phase.isScrolling
        }
    }
}
