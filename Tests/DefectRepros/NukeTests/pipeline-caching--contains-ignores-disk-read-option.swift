// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: `ImagePipeline.Cache.containsCachedImage(for:caches:)` and
// `containsData(for:)` ignore `.disableDiskCacheReads`, while every other read
// in `ImagePipeline.Cache` honors the request options – including the memory
// half of `containsCachedImage`, which honors `.disableMemoryCacheReads`.
//
// Expected: "All `ImagePipeline.Cache` respect request cache control options"
// (Documentation/Nuke.docc/Performance/Caching/accessing-caches.md). For a
// request with `.disableDiskCacheReads`, the disk layer is invisible:
// `cachedData(for:)` and `cachedImage(for:caches: [.disk])` return `nil`, so
// `containsCachedImage(for:caches: [.disk])` and `containsData(for:)` should
// return `false`.
//
// Actual: both return `true`. `containsCachedImage` (Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:114)
// and `containsData` (:193) query the `DataCaching` directly without the
// `.disableDiskCacheReads` guard that `cachedData(for:)` has, so the answers
// contradict each other: "contains" says yes, "cachedImage" returns nil.
@Suite(.timeLimit(.minutes(5)))
struct BugContainsIgnoresDiskReadOptionTests {
    @Test func containsHonorsDisableDiskCacheReads() {
        // GIVEN data in the disk cache
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
            $0.dataCache = MockDataCache()
        }
        pipeline.cache.storeCachedData(Test.data, for: Test.request)
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheReads])

        // THEN the reads agree that there is nothing to read
        #expect(pipeline.cache.cachedData(for: request) == nil)
        #expect(pipeline.cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(!pipeline.cache.containsCachedImage(for: request, caches: [.disk])) // actual: true
        #expect(!pipeline.cache.containsData(for: request)) // actual: true
    }
}
