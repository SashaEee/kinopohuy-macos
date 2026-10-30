import Foundation

/// When the app looks for its own updates: only a Release build whose Info.plist carries the real feed (SUFeedURL, the
/// same value as AppLinks.appcast) and the real EdDSA key (SUPublicEDKey). A build made before they're decided never
/// asks a placeholder address, and a Debug build never replaces itself with a public release (same bundle id and
/// container as the installed app).
enum AppUpdates {
    /// SUPublicEDKey until the key is generated (`generate_keys --account kinopohuy`); scripts/release.sh won't ship it.
    static let publicKeyPlaceholder = "SPARKLE_PUBLIC_KEY_PLACEHOLDER"

    /// Info.plist's SUFeedURL.
    static var feedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
    }

    /// Info.plist's SUPublicEDKey: the base64 Ed25519 public key that every update's signature is checked against.
    static var publicKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
    }

    /// The feed is an https address that isn't a placeholder, and the key is a real 32-byte Ed25519 key.
    static var isConfigured: Bool {
        let feedIsSet = AppLinks.isSet(feedURL) && URL(string: feedURL)?.scheme == "https"
        let keyIsSet = publicKey != publicKeyPlaceholder && Data(base64Encoded: publicKey)?.count == 32

        return feedIsSet && keyIsSet
    }

    /// Whether Sparkle starts at launch (scheduled checks, «Проверить наличие обновлений…»).
    static var startsUpdater: Bool {
        #if DEBUG
            return false
        #else
            return isConfigured
        #endif
    }
}
