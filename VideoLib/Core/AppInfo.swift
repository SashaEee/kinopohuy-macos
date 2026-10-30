import Foundation

/// The app's name, version and credits as the user sees them: the About window, Settings and the menus.
enum AppInfo {
    /// «КиноПохуй»: the shown Cyrillic name, not the ASCII bundle name.
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? "КиноПохуй"
    }

    /// «2.0.0».
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// The build number Sparkle compares («64»).
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "—"
    }

    /// «Версия 2.0.0 (64)».
    static var versionLine: String {
        "Версия \(version) (\(build))"
    }

    /// «© 2026 КиноПохуй» (Info.plist's copyright line, the same text when it's missing).
    static var copyright: String {
        let plist = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
        return plist.isEmpty ? "© 2026 КиноПохуй" : plist
    }

    /// What the app is, in one line under its name.
    static let summary = "Неофициальный клиент для macOS. Ничего не размещает и не распространяет: показывает страницы сайта, адрес которого указали вы."

    /// The credit to the author of the open-source code this project grew from: the MIT notice stays with every copy.
    static let upstreamCredit = "© 2025 voidboost, MIT"
}
