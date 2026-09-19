// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG (docs vs behavior): `ImageResponse.request` of a processed
// image loaded from the network is the request *without* its processors.
// (Found independently of nukeui-views--response-request-drops-processors.swift;
// same root cause.)
//
// Docs (Sources/Nuke/ImageResponse.swift:31): "The request for which the
// response was created."
//
// Expected: `response.request.processors` are the processors of the request
// that was loaded, as they are when the same image comes from the memory
// cache (TaskLoadImage.swift:15).
// Actual: the `TaskLoadImage` for `[p1]` subscribes to the one for `[]` and
// `process(_:isCompleted:processor:)` only replaces `response.container`, so
// the response keeps the request of the innermost dependency. A caller that
// keys anything off `response.request` – e.g. `pipeline.cache[response.request]
// = response.container` – writes the *processed* image into the slot of the
// original one.
@Suite(.timeLimit(.minutes(1)))
struct RequestModelBugResponseRequestTests {
    @Test func responseRequestKeepsProcessors() async throws {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["p1"])
        #expect(response.request.processors.map(\.identifier) == ["p1"])
        #expect(pipeline.cache.makeImageCacheKey(for: response.request) == pipeline.cache.makeImageCacheKey(for: request))
    }
}
