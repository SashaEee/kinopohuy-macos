import Foundation

/// Every public link of the project in one place: the repository, the Telegram channel, donations and the update feed.
/// The values are placeholders until they are decided; the UI shows a link only once it is set (`isSet`).
enum AppLinks {
    static let repository = URL(string: "https://github.com/SashaEee/kinopohuy-macos")!
    static let releases = URL(string: "https://github.com/SashaEee/kinopohuy-macos/releases")!
    static let issues = URL(string: "https://github.com/SashaEee/kinopohuy-macos/issues")!
    static let telegram = URL(string: "https://t.me/CHANNEL")!

    static let boosty = URL(string: "https://boosty.to/sanchella_zzz")!
    static let cloudtips = URL(string: "https://pay.cloudtips.ru/p/553b7918")!
    static let yoomoney = URL(string: "https://yoomoney.ru/to/WALLET")!

    /// The crypto wallet (shown as text to copy and as a QR code, not opened): Telegram Wallet's dollar address,
    /// which takes USDT on the TON network only.
    static let cryptoUSDT = "UQC3PZ6C2Bhte2-pvdbT9a5c54tSNynDcz080vKHJ3UB8i2f"

    /// A Bybit account's UID (shown as text to copy): a transfer inside Bybit by UID is free and instant, for those who
    /// already have a verified Bybit account.
    static let bybitUID = "150542700"

    /// The same Bybit account's deposit address for bitcoin, on the Bitcoin network only.
    static let cryptoBTC = "1BC5Z3jwh1AUKpk9ECz1FqFqfjd5yh82Kz"

    /// Sparkle's update feed; Info.plist's SUFeedURL carries the same value.
    static let appcast = URL(string: "https://sashaeee.github.io/kinopohuy-macos/appcast.xml")!

    /// The upper-case words that mark a value as not decided yet.
    private static let placeholderMarkers = ["OWNER", "REPO", "CHANNEL", "USERNAME", "PAGE_ID", "WALLET", "BYBIT_UID"]

    /// Whether a link has been filled in (placeholders stay hidden in the UI).
    static func isSet(_ url: URL) -> Bool {
        isSet(url.absoluteString)
    }

    /// Whether a value (a link or a wallet address) has been filled in.
    static func isSet(_ value: String) -> Bool {
        !value.isEmpty && !placeholderMarkers.contains { value.contains($0) }
    }
}
