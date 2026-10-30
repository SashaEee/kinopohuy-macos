import Foundation

/// The project's Package.resolved: the packages it depends on now. A DerivedData folder's workspace-state.json can
/// still list packages checked out for an older version of the project, so only the ones named here make the list.
struct PackageResolved {
    let identities: Set<String>

    init(contentsOf url: URL) throws {
        guard let data = try? Data(contentsOf: url) else {
            throw SourcePackagesParserError.couldNotReadFile(url.lastPathComponent)
        }

        if let file = try? JSONDecoder().decode(FileV2.self, from: data) {
            identities = Set(file.pins.map { $0.identity.lowercased() })
        } else if let file = try? JSONDecoder().decode(FileV1.self, from: data) {
            identities = Set(file.object.pins.map { Self.identity(location: $0.repositoryURL) })
        } else {
            throw SourcePackagesParserError.couldNotReadFile(url.lastPathComponent)
        }
    }

    func contains(_ identity: String) -> Bool {
        identities.contains(identity.lowercased())
    }

    /// SwiftPM's identity of a package at `location`: its last path component, lower-cased, without `.git`.
    private static func identity(location: String) -> String {
        let name = location.components(separatedBy: "/").filter { !$0.isEmpty }.last ?? location
        let trimmed = name.hasSuffix(".git") ? String(name.dropLast(4)) : name

        return trimmed.lowercased()
    }

    /// Versions 2 and 3 (Xcode 13.3 and later).
    private struct FileV2: Decodable {
        let pins: [Pin]

        struct Pin: Decodable {
            let identity: String
        }
    }

    /// Version 1.
    private struct FileV1: Decodable {
        let object: ObjectRef

        struct ObjectRef: Decodable {
            let pins: [Pin]
        }

        struct Pin: Decodable {
            let repositoryURL: String
        }
    }
}
