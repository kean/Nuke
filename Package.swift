// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "Nuke",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .tvOS(.v10),
        .watchOS(.v3)
    ],
    products: [
        .library(name: "Nuke", targets: ["Nuke"]),
    ],
    targets: [
        .target(name: "Nuke", path: "Sources")
    ]
)
