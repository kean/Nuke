// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Nuke",
    platforms: [
        .iOS(.v14),
        .tvOS(.v14),
        .macOS(.v11),
        .watchOS(.v7),
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
        .target(name: "NukeExtensions", dependencies: ["Nuke"])
    ]
)
