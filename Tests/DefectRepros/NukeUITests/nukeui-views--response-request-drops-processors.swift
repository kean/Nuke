// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

// BUG: `ImageResponse/request` of a processed image loaded from the network is
// the request *without* its processors, so it's not "the request for which the
// response was created", and it differs from the one reported for the same
// image when it comes from the memory cache.
//
// Sources/Nuke/Tasks/TaskLoadImage.swift, `fetchImage()` / `process(...)`:
// the task for `[p1, ..., pN]` subscribes to the task for `[p1, ..., pN-1]`,
// and down to `TaskFetchOriginalImage` for the request with no processors. The
// processing step only replaces the container (`var response = response;
// response.container = try processor.process(...)`), so the response keeps the
// request of the innermost dependency – the one with no processors at all.
// The memory cache path (`TaskLoadImage.swift:15`) and the disk cache path
// build the response with the full request, as does NukeUI for its own memory
// cache lookups.
//
// Expected: `response.request.processors` lists the processors that produced
// `response.image` on every path.
//
// Actual: it's empty for network loads, and `[p1]` for the very same image when
// it's then served from the memory cache. `LazyImageView.onSuccess`,
// `loadImage(with:options:into:)` completions, and `ImageTask.response` all
// surface it; using `response.request` as a cache key stores the processed
// image under the key of the original one.

@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageResponseRequestProcessorsRepro {
    let pipeline = ImagePipeline {
        $0.dataLoader = MockDataLoader()
        $0.imageCache = MockImageCache()
    }

    @Test func pipelineResponseKeepsRequestProcessors() async throws {
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        let response = try await pipeline.imageTask(with: request).response

        #expect(response.image.nk_test_processorIDs == ["p1"])
        #expect(response.request.processors.map(\.identifier) == ["p1"]) // FAILS: []
    }

    @Test func lazyImageViewReportsSameRequestForNetworkAndMemoryCache() async throws {
        let view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
        view.processors = [MockImageProcessor(id: "p1")]
        var responses: [ImageResponse] = []
        view.onSuccess = { responses.append($0) }

        // Loaded from the network
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        // Then loaded again, from the memory cache
        view.onCompletion = nil
        view.url = Test.url

        try #require(responses.count == 2)
        #expect(responses[1].cacheType == .memory)
        #expect(responses[1].request.processors.map(\.identifier) == ["p1"])
        #expect(responses[0].request.processors.map(\.identifier) == ["p1"]) // FAILS: []
    }
}

#endif
