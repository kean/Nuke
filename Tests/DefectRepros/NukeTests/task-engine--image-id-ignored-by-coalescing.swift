// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// Suspected bug: requests that differ only in `ImageRequest.imageID` are
// coalesced, so every request but the first one finishes without its image
// ever being stored under its own cache key, and gets a response that carries
// the first request.
//
// `imageID` is documented as "The image identifier used for caching and task
// coalescing" (Sources/Nuke/ImageRequest.swift:88). The memory cache honors it
// (`MemoryCacheKey` reads `request.imageID`), but none of the task pool keys do:
// `TaskFetchOriginalDataKey` reads `request.originalImageID` – the URL – and
// `TaskLoadImageKey`/`TaskFetchOriginalImageKey` add nothing that includes the
// custom ID (Sources/Nuke/Internal/ImageRequestKeys.swift:56-141). Two
// in-flight requests for the same URL with different `imageID`s therefore
// share one `TaskLoadImage`, whose canonical request is the first one: it
// stores the image in the memory cache under the first request's key only
// (`TaskLoadImage.storeImageInCaches`) and builds the response with the first
// request.
//
// Expected: after both tasks succeed, `pipeline.cache[second]` has the image,
// and the second task's `response.request.imageID` is "b".
// Actual: `pipeline.cache[second]` is `nil` – the next load of the second
// request downloads the image again – and `response.request.imageID` is "a".
@Suite(.timeLimit(.minutes(2)))
struct TaskEngineReproImageIDCoalescingTests {
    @Test func coalescedRequestsWithDifferentImageIDsAreEachCached() async throws {
        // Given
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
        let first = ImageRequest(url: Test.url).with { $0.imageID = "a" }
        let second = ImageRequest(url: Test.url).with { $0.imageID = "b" }

        // When both are in flight at the same time
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: first), pipeline.imageTask(with: second))
        }
        _ = try await task1.response
        let response = try await task2.response

        // Then each request's image is stored under its own key
        #expect(pipeline.cache[first] != nil)
        #expect(pipeline.cache[second] != nil) // Fails: nil
        #expect(response.request.imageID == "b") // Fails: "a"
    }
}
