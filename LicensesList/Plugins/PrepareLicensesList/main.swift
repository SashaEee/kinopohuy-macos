import Foundation
import PackagePlugin

@main
struct PrepareLicensesList: BuildToolPlugin {
    struct SourcePackagesNotFoundError: Error & CustomStringConvertible {
        let description: String = "SourcePackages not found"
    }

    func existsSourcePackages(in url: URL) throws -> Bool {
        guard url.isFileURL,
              url.pathComponents.count > 1,
              let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        else {
            throw SourcePackagesNotFoundError()
        }

        let existsSourcePackagesInDirectory = FileManager.default
            .fileExists(atPath: url.appending(path: "SourcePackages").path(percentEncoded: false))

        return isDirectory && existsSourcePackagesInDirectory
    }

    func sourcePackages(_ pluginWorkDirectory: URL) throws -> URL {
        var tmpURL = pluginWorkDirectory.absoluteURL

        while try !existsSourcePackages(in: tmpURL) {
            tmpURL.deleteLastPathComponent()
        }

        tmpURL.append(path: "SourcePackages")

        return tmpURL
    }

    /// The project's Package.resolved: the first one found going up from this package's folder, in a workspace or a
    /// project next to it (`X.xcworkspace/xcshareddata/swiftpm`, `X.xcodeproj/project.xcworkspace/xcshareddata/swiftpm`)
    /// or a plain package's own. It names the packages the project uses now: a DerivedData folder's workspace-state.json
    /// can still list ones an older version of the project checked out.
    func packageResolved(above packageDirectory: URL) -> URL? {
        let fileManager = FileManager.default
        var directory = packageDirectory.absoluteURL.deletingLastPathComponent()

        while directory.pathComponents.count > 1 {
            let contents = ((try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []).sorted()
            let candidates = contents.filter { $0.hasSuffix(".xcworkspace") }
                .map { directory.appending(path: $0).appending(path: "xcshareddata/swiftpm/Package.resolved") }
                + contents.filter { $0.hasSuffix(".xcodeproj") }
                .map { directory.appending(path: $0).appending(path: "project.xcworkspace/xcshareddata/swiftpm/Package.resolved") }
                + [directory.appending(path: "Package.resolved")]

            if let found = candidates.first(where: { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }) {
                return found
            }

            directory.deleteLastPathComponent()
        }

        return nil
    }

    func makeBuildCommand(executableURL: URL, sourcePackagesURL: URL, packageResolvedURL: URL?, outputURL: URL) -> Command {
        let workspaceStateURL = sourcePackagesURL.appending(path: "workspace-state.json")

        return .buildCommand(
            displayName: "Prepare LicensesList",
            executable: executableURL,
            arguments: [
                outputURL.absoluteURL.path(percentEncoded: false),
                sourcePackagesURL.absoluteURL.path(percentEncoded: false),
            ] + [packageResolvedURL?.absoluteURL.path(percentEncoded: false)].compactMap(\.self),
            // Both inputs: the list is made again whenever the packages change, not only when it's missing.
            inputFiles: [workspaceStateURL, packageResolvedURL]
                .compactMap(\.self)
                .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
            outputFiles: [
                outputURL,
            ],
        )
    }

    func createBuildCommands(context: PluginContext, target _: Target) async throws -> [Command] {
        try [
            makeBuildCommand(
                executableURL: context.tool(named: "SourcePackagesParser").url,
                sourcePackagesURL: sourcePackages(context.pluginWorkDirectoryURL),
                packageResolvedURL: packageResolved(above: context.package.directoryURL),
                outputURL: context.pluginWorkDirectoryURL.appending(path: "LicensesList.swift"),
            ),
        ]
    }
}
