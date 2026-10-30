import Foundation

enum VideoLibError: Error {
    case mirrorBanned(URL)
    case loginRequired(URL)
    case skipLinks([URL])
    case parseJson(String, String)
    case null(String, Int, Int)
    case swiftsoup(String, String)
    case unknown
    case site([String])
    /// The site's address hasn't been entered yet (the built-in default points nowhere).
    case siteNotConfigured
}

extension VideoLibError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .mirrorBanned(mirror):
            String(localized: "key.errors.mirror-\(mirror.host() ?? "")")
        case let .loginRequired(mirror):
            String(localized: "key.errors.login-\(mirror.host() ?? "")")
        case let .skipLinks(links):
            String(localized: "key.errors.links-\(links.map(\.absoluteString).joined(separator: ", "))")
        case let .parseJson(param, function):
            String(localized: "key.errors.parsing-\(param)-\(function)")
        case let .null(functionName, lineNumber, columnNumber):
            String(localized: "key.errors.null-\(functionName)-\(lineNumber)-\(columnNumber)")
        case let .swiftsoup(type, message):
            String(localized: "key.errors.swiftsoup-\(type)-\(message)")
        case .unknown:
            String(localized: "key.errors.unknown")
        case let .site(messages):
            messages.joined(separator: "\n")
        case .siteNotConfigured:
            String(localized: "key.errors.site_not_configured")
        }
    }
}

extension VideoLibError: CustomNSError {
    var errorUserInfo: [String: Any] {
        if let errorDescription {
            [NSLocalizedDescriptionKey: errorDescription]
        } else {
            [:]
        }
    }
}
