// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Nuke",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v5)
    ],
    products: [
        .library(name: "Nuke", targets: ["Nuke"])
    ],
    targets: [
        .target(name: "Nuke", path: "Sources")
    ]
)
