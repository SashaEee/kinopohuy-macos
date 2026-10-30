import Foundation

func exitWithUsage() -> Never {
    print("USAGE: swift run SourcePackagesParser [output directory path] [SourcePackages directory path] [Package.resolved path (optional)]")

    exit(1)
}

func exitWithSourcePackagesParserError(_ sourcePackagesParserError: SourcePackagesParserError) -> Never {
    switch sourcePackagesParserError {
    case let .couldNotReadFile(fileName):
        print("Error: Could not read \(fileName).")
    case .couldNotExportLicensesList:
        print("Error: Could not export LicensesList.swift.")
    }

    exit(1)
}

func main() {
    guard [3, 4].contains(CommandLine.arguments.count) else {
        exitWithUsage()
    }

    let outputPath = CommandLine.arguments[1]
    let sourcePackagesPath = CommandLine.arguments[2]
    let packageResolvedPath = CommandLine.arguments.count == 4 ? CommandLine.arguments[3] : nil

    do {
        try SourcePackagesParser(outputPath, sourcePackagesPath, packageResolvedPath).run()
    } catch {
        if let sourcePackagesParserError = error as? SourcePackagesParserError {
            exitWithSourcePackagesParserError(sourcePackagesParserError)
        }
    }
}

main()
