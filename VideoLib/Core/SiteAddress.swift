import Defaults
import Foundation

/// The site's address is the user's to enter: the app ships with a placeholder that points nowhere, and no request is
/// sent until a real address is set (Settings → «Сайт», or the first-run screen).
enum SiteAddress {
    /// The built-in default (`Const.mirror`), a reserved name that never resolves.
    static var placeholder: URL {
        Const.mirror
    }

    /// Whether the user has entered the site's address.
    static var isConfigured: Bool {
        isConfigured(Defaults[.mirror])
    }

    /// Whether `url` is a real address rather than the placeholder or something without a host.
    static func isConfigured(_ url: URL) -> Bool {
        guard let host = url.host(), !host.isEmpty else { return false }

        return !isPlaceholder(host: host)
    }

    /// Whether a request to `host` would go to the placeholder (CustomInterceptor stops those).
    static func isPlaceholder(host: String?) -> Bool {
        guard let host else { return false }

        return host.caseInsensitiveCompare(placeholder.host() ?? "") == .orderedSame
    }
}
