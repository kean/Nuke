// swift-tools-version:5.3
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
        .binaryTarget(name: "Nuke", url: "https://github.com/kean/Nuke/releases/download/9.1.1/Nuke.xcframework.zip", checksum: "f13ca296cd8b9575049a88e4cc7ce6790e133aa40cb80bf624e7d38e294fa518")
    ]
)
