import Alamofire
import Defaults
import Dependencies
import Foundation
import SwiftUI

class Const {
    /// No site address is built in: the user enters it (see SiteAddress). Until then this reserved name, which never
    /// resolves, is the default and nothing is sent anywhere.
    static let mirror = URL(string: "https://example.invalid/")!

    static let rpc = URL(string: "http://127.0.0.1:6800/")!

    /// The local aria2 RPC secret: new on every launch, so no other app on this Mac can drive the downloader.
    static let token = UUID().uuidString

    /// The site's Android app version sent in its headers until the site reports a newer one.
    static let siteAppVersion = "2.2.2"

    static let premiumGradient = LinearGradient(colors: [
        .init(red: 222.0 / 255.0, green: 21.0 / 255.0, blue: 226.0 / 255.0),
        .init(red: 138.0 / 255.0, green: 0.0, blue: 173.0 / 255.0),
    ], startPoint: .leading, endPoint: .trailing)

    static var userAgent: String {
        // Always "VideoLib": the shown name is Cyrillic, and a non-ASCII User-Agent makes the site drop the connection
        // (NSURLErrorNetworkConnectionLost). No device identifier goes into it.
        let appName = "VideoLib"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let appBundle = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let osName = "macOS"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion

        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: Int(size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let deviceModel = String(utf8String: model) ?? "Unknown"

        return "\(appName)/\(appVersion)(\(appBundle)) (\(deviceModel); \(osName) \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion))"
    }

    static var headers: HTTPHeaders {
        HTTPHeaders(
            Defaults[.useHeaders] ? [
                .init(name: "X-VideoLib-Android-App", value: "1"),
                .init(name: "X-VideoLib-Android-App-Version", value: Defaults[.siteAppVersion]),
                .userAgent(userAgent),
            ] : [.userAgent(userAgent)]
        )
    }

    static var dbPath: String {
        get throws {
            let applicationSupportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            return applicationSupportDirectory.appending(path: "VideoLib.db", directoryHint: .notDirectory).absoluteString
        }
    }
}
