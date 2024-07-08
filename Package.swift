// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nuke",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Nuke", targets: ["Nuke"]),
        .library(name: "NukeUI", targets: ["NukeUI"]),
        .library(name: "NukeVideo", targets: ["NukeVideo"]),
        .library(name: "NukeExtensions", targets: ["NukeExtensions"]),
    ],
    targets: [
        .target(name: "Nuke"),
        .target(name: "NukeUI", dependencies: ["Nuke"]),
        .target(name: "NukeVideo", dependencies: ["Nuke"]),
        .target(name: "NukeExtensions", dependencies: ["Nuke"]),
        .target(name: "NukeTestHelpers", dependencies: ["Nuke"], path: "Tests/NukeTestHelpers", resources: [.process("Fixtures")]),
        .testTarget(name: "NukeTests", dependencies: ["Nuke", "NukeTestHelpers"]),
        .testTarget(name: "NukeThreadSafetyTests", dependencies: ["Nuke", "NukeTestHelpers"]),
        .testTarget(name: "NukeUITests", dependencies: ["NukeUI", "NukeTestHelpers"]),
    ]
)
