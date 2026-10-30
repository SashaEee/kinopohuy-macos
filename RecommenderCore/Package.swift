// swift-tools-version: 6.1

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

// The recommender's pure core: signals → taste → candidates → scores → home rows and «Выбери за меня». No UI, no
// network, no database: JSON in, JSON out, so it is unit-tested with `swift test` and can be ported to the TV server.
let package = Package(
    name: "RecommenderCore",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "RecommenderCore", targets: ["RecommenderCore"]),
        .executable(name: "RecEval", targets: ["RecEval"]),
    ],
    targets: [
        .target(
            name: "RecommenderCore",
            resources: [.process("Resources")],
            swiftSettings: swiftSettings,
        ),
        .executableTarget(
            name: "RecEval",
            dependencies: ["RecommenderCore"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "RecommenderCoreTests",
            dependencies: ["RecommenderCore"],
            resources: [.process("Fixtures")],
            swiftSettings: swiftSettings,
        ),
    ],
)
