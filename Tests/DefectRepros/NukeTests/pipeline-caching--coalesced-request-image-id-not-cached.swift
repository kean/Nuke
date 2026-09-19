// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: concurrent requests for the same URL but with different
// `ImageRequest.imageID`s are coalesced into one `TaskLoadImage`, which stores
// the result only under the *first* request's cache keys. The other request's
// image never reaches the memory or the disk cache, so it misses both and
// downloads the image again next time.
//
// Expected: `imageID` is documented as "the image identifier used for caching
// and task coalescing". After both requests finish, each can be served from
// the caches under its own ID (either the requests aren't coalesced, or the
// coalesced task stores the image for every ID).
//
// Actual: `pipeline.cache[b] == nil` and the disk only has key "a".
// `TaskLoadImageKey` (Sources/Nuke/Internal/ImageRequestKeys.swift:56) is built
// from `TaskFetchOriginalImageKey`, which uses `originalImageID` (the URL), plus
// the options and processors – the custom image ID isn't part of it since
// 3776cae7 "Optimize TaskLoadImageKey" dropped the `MemoryCacheKey` from the
// key. `TaskLoadImage.storeImageInCaches` then writes under `self.request`
// (the first subscriber's request). The same happens for anything a delegate
// derives from the request that isn't in the task key, e.g. a `cacheKey(for:)`
// or `imageCache(for:)` that reads `userInfo`.
@Suite(.timeLimit(.minutes(5)))
struct BugCoalescedImageIDCachingTests {
    @Test func everyCoalescedImageIDIsCached() async throws {
        // GIVEN
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
            $0.dataCache = dataCache
        }
        let a = ImageRequest(url: Test.url).with { $0.imageID = "a" }
        let b = ImageRequest(url: Test.url).with { $0.imageID = "b" }

        // WHEN both are loaded at the same time
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: a), pipeline.imageTask(with: b))
        }
        _ = try await task1.response
        _ = try await task2.response

        // THEN
        #expect(pipeline.cache[a] != nil)
        #expect(pipeline.cache[b] != nil) // actual: nil
        #expect(pipeline.cache.containsData(for: b)) // actual: false, only "a" is stored

        // THEN loading `b` again doesn't hit the network
        _ = try await pipeline.image(for: b)
        #expect(dataLoader.createdTaskCount == 1) // actual: 2
    }
}
