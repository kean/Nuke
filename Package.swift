// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Nuke",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "Nuke", targets: ["Nuke"])
    ],
    targets: [
        .target(name: "Nuke", path: "Sources")
    ]
)
