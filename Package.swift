// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "SwiftState",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "SwiftState",
            targets: ["SwiftState"]),
    ],
    dependencies: [
        .package(url: "https://github.com/belozierov/SwiftCoroutine.git", Package.Dependency.Requirement.exact("2.1.9"))
    ],
    targets: [
        .target(
            name: "SwiftState",
            dependencies: ["SwiftCoroutine"]
        ),
        .testTarget(
            name: "SwiftStateTests",
            dependencies: ["SwiftState"]
        ),
    ]
)
