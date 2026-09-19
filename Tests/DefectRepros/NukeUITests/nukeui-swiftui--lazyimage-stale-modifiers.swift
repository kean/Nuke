// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

// BUG: `LazyImage` copies `pipeline`, `onStart`, `onCompletion` and
// `transaction` into its `FetchImage` only in `onAppear`
// (Sources/NukeUI/LazyImage.swift:181-190). When the parent re-renders the
// view with a new request *and* new modifier values, `onChange(of: context)`
// (LazyImage.swift:162-164) calls `viewModel.load(...)` with the values
// captured when the view first appeared.
//
// Expected: a request started by a view update uses the modifiers of that
// same update – the new URL is loaded through the new pipeline and reported
// to the new `onCompletion` closure. `pipeline(_:)` is documented as
// "Changes the underlying pipeline used for image loading".
//
// Actual: the new URL is loaded through the old pipeline (its data loader
// is hit twice, the new pipeline's never), and the completion is delivered to
// the stale closure, which still captures the old view's values – e.g. an
// `onCompletion { viewModel.didLoad(item.id, $0) }` in a detail view reports
// the new image under the previous item's id.
@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct LazyImageStaleModifiersBugRepro {
    private let urls = [Test.url, URL(string: "https://example.com/other.jpeg")!]

    @Test func requestStartedByAnUpdateUsesTheUpdatedPipeline() async {
        let loaders = [MockDataLoader(), MockDataLoader()]
        let pipelines = loaders.map { loader in
            ImagePipeline {
                $0.dataLoader = loader
                $0.imageCache = nil
            }
        }

        let completions = Ref(0)
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(0) { index in
            LazyImage(url: urls[index])
                .pipeline(pipelines[index])
                .onCompletion { _ in
                    completions.value += 1
                    if completions.value == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update(1)
        await second.wait()

        // Expected: 1 and 1. Actual: 2 and 0.
        #expect(loaders[0].createdTaskCount == 1)
        #expect(loaders[1].createdTaskCount == 1)
    }

    @Test func requestStartedByAnUpdateReportsToTheUpdatedOnCompletion() async throws {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let received = Ref<[(viewIndex: Int, url: URL?)]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(0) { index in
            LazyImage(url: urls[index])
                .pipeline(pipeline)
                .onCompletion { result in
                    received.value.append((index, result.value?.request.url))
                    if received.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update(1)
        await second.wait()

        let last = try #require(received.value.last)
        #expect(last.url == urls[1])
        // Expected: 1 (the closure of the view that asked for `urls[1]`).
        // Actual: 0 (the closure captured when the view first appeared).
        #expect(last.viewIndex == 1)
    }
}

#endif
