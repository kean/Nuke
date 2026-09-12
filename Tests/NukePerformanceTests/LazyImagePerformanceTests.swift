// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke
import NukeUI

/// SwiftUI compares the request of every visible `LazyImage` on each body
/// evaluation, so the comparison runs on the main thread once per cell per update.
@Suite(.serialized)
@MainActor
struct LazyImagePerformanceTests {
    @Test
    func requestComparisonWithSameRequest() throws {
        let request = ImageRequest(url: URL(string: "http://test.com/1"), processors: [ImageProcessors.Resize(width: 320)])

        try measureRequestComparison(LazyImage(request: request), LazyImage(request: request))
    }

    @Test
    func requestComparisonWithRebuiltRequest() throws {
        let url = URL(string: "http://test.com/1")

        try measureRequestComparison(
            LazyImage(request: ImageRequest(url: url, processors: [ImageProcessors.Resize(width: 320)])),
            LazyImage(request: ImageRequest(url: url, processors: [ImageProcessors.Resize(width: 320)]))
        )
    }

    /// The comparison is private to `NukeUI`, so the test reaches it the way
    /// `onChange(of:)` does: through the `Equatable` conformance of the value
    /// the view stores.
    private func measureRequestComparison<Content>(_ lhs: LazyImage<Content>, _ rhs: LazyImage<Content>, name: String = #function) throws {
        let lhs = try #require(Mirror(reflecting: lhs).descendant("context") as? any Equatable)
        let rhs = try #require(Mirror(reflecting: rhs).descendant("context"))
        measureComparison(lhs, rhs, name: name)
    }

    private func measureComparison<T: Equatable>(_ lhs: T, _ rhs: Any, name: String) {
        let rhs = rhs as! T
        measure(name) {
            var count = 0
            for _ in 0..<1_000_000 where lhs == rhs {
                count += 1
            }
            return count
        }
    }
}
