// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "Nuke",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v11),
        .tvOS(.v11),
        .watchOS(.v4)
    ],
    products: [
        .library(name: "Nuke", targets: ["Nuke"])
    ],
    targets: [
        .target(name: "Nuke", path: "Sources")
    ]
)
