import Foundation

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
}
