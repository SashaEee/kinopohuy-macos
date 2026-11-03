import AppKit

/// Screenshot mode for README images (Debug builds, `KP_DEMO=1`): posters are slightly enlarged and the account's own
/// details (premium days, the size of the history, voice-overs in the «Продолжить просмотр» captions) stay out of the
/// picture. Always off in Release.
enum KPDemo {
    #if DEBUG
    static let isOn = ProcessInfo.processInfo.environment["KP_DEMO"] != nil
    #else
    static let isOn = false
    #endif

    /// How much a poster grows from its top edge in screenshot mode.
    static let posterScale: CGFloat = isOn ? 1.1 : 1

    /// Voice-over names to leave out of lists in screenshot mode (`KP_DEMO_HIDE=a,b`).
    private static let hiddenWords: [String] = {
        guard isOn else { return [] }
        return (ProcessInfo.processInfo.environment["KP_DEMO_HIDE"] ?? "").split(separator: ",").map(String.init)
    }()

    static func hides(_ name: String) -> Bool {
        hiddenWords.contains { name.localizedCaseInsensitiveContains($0) }
    }

    #if DEBUG
    /// `KP_SCROLL=<points>`: a few seconds after launch (`KP_SCROLL_AFTER`, 8 by default) the window's page scrolls
    /// down this far, for shots of what's below the fold.
    @MainActor
    static func scrollIfAsked() {
        let environment = ProcessInfo.processInfo.environment
        guard isOn, let offset = environment["KP_SCROLL"].flatMap(Double.init) else { return }
        let delay = environment["KP_SCROLL_AFTER"].flatMap(Double.init) ?? 8
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard let content = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 800 })?.contentView else { return }
            // The page's own scroll view is the tallest one (rows scroll sideways in short ones).
            guard let scrollView = scrollViews(in: content).max(by: { $0.frame.height < $1.frame.height }) else { return }
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    @MainActor
    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
    #endif
}
