// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Nuke",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Nuke", targets: ["Nuke"]),
        .library(name: "NukeUI", targets: ["NukeUI"]),
        .library(name: "NukeVideo", targets: ["NukeVideo"]),
        .library(name: "NukeExtensions", targets: ["NukeExtensions"])
    ],
    targets: [
        .target(name: "Nuke"),
        .target(name: "NukeUI", dependencies: ["Nuke"]),
        .target(name: "NukeVideo", dependencies: ["Nuke"]),
        .target(name: "NukeExtensions", dependencies: ["Nuke"]),
        // The other modules are tested from Nuke.xcodeproj; NukeVideo has no
        // test target there, so this one keeps its API covered.
        .testTarget(name: "NukeVideoTests", dependencies: ["NukeVideo"])
    ]
)
