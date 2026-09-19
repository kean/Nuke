// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: when two requests for the same URL but with different
// `imageID` overrides are coalesced, the second one's image is never stored
// under its own ID and its response reports the first one's request.
// (Found independently of pipeline-caching--coalesced-request-image-id-not-
// cached.swift and task-engine--image-id-ignored-by-coalescing.swift; same
// root cause.)
//
// Docs (Sources/Nuke/ImageRequest.swift:88): "The image identifier used for
// caching and task coalescing."
//
// Expected: after both loads, each request finds its image in the memory
// cache under its own `imageID`.
// Actual: every task key is built from `originalImageID` (the URL) –
// Sources/Nuke/Internal/ImageRequestKeys.swift – so the second request joins
// the first one's `TaskLoadImage`, which stores the result only under the
// first request's `imageID` (TaskLoadImage.storeImageInCaches uses its own
// `request`). The second request's cache slot stays empty, and so does its
// disk cache key, so its next load goes to the network again.
@Suite(.timeLimit(.minutes(1)))
struct RequestModelBugCoalescedImageIDTests {
    @Test func eachCoalescedRequestIsCachedUnderItsImageID() async throws {
        // Given
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
        let first = ImageRequest(url: Test.url).with { $0.imageID = "first" }
        let second = ImageRequest(url: Test.url).with { $0.imageID = "second" }

        // When both are loaded at the same time
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: first), pipeline.imageTask(with: second))
        }
        _ = try await task1.response
        let response2 = try await task2.response

        // Then
        #expect(imageCache[first] != nil)
        #expect(imageCache[second] != nil)
        #expect(response2.request.imageID == "second")
    }
}
