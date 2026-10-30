// swift-tools-version: 6.1

import PackageDescription

// The rules behind the app's recommendation screens (the title page's bar, the cards' menus, the rating after
// watching, «Досмотреть»'s segments, the taste stack), tested with `swift test`. The app has no test target, so the
// source here is a link to the app's own file (VideoLib/Presentations/Recommendations/Logic/RecsUILogic.swift): the
// app and the tests compile the very same code.
let package = Package(
    name: "RecsAppLogic",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "../RecommenderCore"),
    ],
    targets: [
        .target(
            name: "RecsAppLogic",
            dependencies: [.product(name: "RecommenderCore", package: "RecommenderCore")],
        ),
        .testTarget(
            name: "RecsAppLogicTests",
            dependencies: ["RecsAppLogic", .product(name: "RecommenderCore", package: "RecommenderCore")],
        ),
    ],
)
