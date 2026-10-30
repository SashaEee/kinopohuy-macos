import Alamofire
import Defaults
import Foundation

/// The site's own template name. Its comment and rating endpoints check it and answer "Hacking attempt!" to any other
/// (a fixed name doesn't work everywhere). Read once per site address from the home page's asset paths: /templates/<name>/….
actor SiteSkin {
    static let shared = SiteSkin()

    private var cached: (mirror: URL, skin: String)?

    func value(using session: Session) async -> String? {
        let mirror = Defaults[.mirror]
        if let cached, cached.mirror == mirror { return cached.skin }
        guard SiteAddress.isConfigured(mirror) else { return nil }

        guard let html = try? await session.request(mirror).validate(statusCode: 200 ..< 400).serializingString().value,
              let range = html.range(of: "/templates/[A-Za-z0-9_-]+/", options: .regularExpression)
        else { return nil }

        let skin = html[range].dropFirst("/templates/".count).dropLast()
        guard !skin.isEmpty else { return nil }
        cached = (mirror, String(skin))
        return String(skin)
    }
}
