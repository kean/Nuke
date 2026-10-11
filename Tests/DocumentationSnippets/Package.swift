// swift-tools-version:6.0
import PackageDescription

// The hand-written samples from the DocC articles, verbatim.
//
// This is a separate package rather than a target in the root one so that it can
// be built for iOS – the UIKit and Objective-C samples don't compile on macOS,
// which is the only platform the root package's `swift build` covers. CI builds
// it with `.scripts/ci.sh snippets`; nothing links against it.
let package = Package(
    name: "DocumentationSnippets",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "DocumentationSnippets", targets: ["DocumentationSnippets"])
    ],
    dependencies: [
        .package(name: "Nuke", path: "../..")
    ],
    targets: [
        // The dependency is named explicitly: a path dependency otherwise takes
        // its identity from the directory it sits in, which is "Nuke" in a clone
        // but not in a git worktree or a renamed checkout.
        .target(
            name: "DocumentationSnippets",
            dependencies: [
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke")
            ],
            path: "Snippets"
        )
    ]
)
