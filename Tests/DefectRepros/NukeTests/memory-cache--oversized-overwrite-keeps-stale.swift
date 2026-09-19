// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: overwriting a key with an image over the entry cost limit
// leaves the previous image in the cache.
//
// `Cache.set(_:forKey:cost:ttl:)` (Sources/Nuke/Caching/Cache.swift:131)
// returns early when `cost >= entryMaxCost` *before* it looks at the entry the
// key already has, so the old value survives the write and keeps being served:
//
//     cache[key] = small   // stored
//     cache[key] = large   // too large to cache – silently ignored
//     cache[key]           // returns `small`, a value the caller replaced
//
// Expected: after `cache[key] = large` the cache holds either `large` or
// nothing for `key` (the new value can be refused, but the stale one must not
// outlive a write that replaced it – `NSCache.setObject(_:forKey:cost:)` and
// every other write path of `ImageCache` replace or evict).
// Actual: `cache[key]` returns the old, smaller image.
//
// The same happens through `ImagePipeline.Cache`: an image reloaded with
// `.reloadIgnoringCachedData` that grew past the entry limit leaves the old
// image in memory, and every later load of the request gets the outdated image
// from the memory cache.
@Suite(.timeLimit(.minutes(5)))
struct MemoryCacheOversizedOverwriteRepro {
    @Test func overwritingWithAnOversizedImageDoesNotKeepTheOldOne() {
        // Given a cache that takes entries up to 10% of its 1000-byte limit
        let cache = ImageCache(costLimit: 1000, countLimit: 100)
        cache.entryCostLimit = 0.1
        let key = ImageCacheKey(key: "avatar")

        // Costs are `1 + data.count` for an image without a bitmap
        let old = ImageContainer(image: PlatformImage(), data: Data(count: 10))  // 11
        let new = ImageContainer(image: PlatformImage(), data: Data(count: 500)) // 501
        cache[key] = old
        #expect(cache[key]?.data?.count == 10)

        // When the key is overwritten with an image the cache won't take
        cache[key] = new

        // Then the replaced image is no longer served
        #expect(cache[key]?.data?.count != 10) // fails: the old image is returned
        #expect(cache.totalCost != 11)          // fails: the old image is still charged
    }

    @Test func pipelineCacheSubscriptKeepsTheOldImage() {
        // Given
        let imageCache = ImageCache(costLimit: 1000, countLimit: 100)
        let pipeline = ImagePipeline {
            $0.imageCache = imageCache
            $0.dataCache = nil
        }
        let request = ImageRequest(url: URL(string: "https://example.com/avatar.png"))
        pipeline.cache[request] = ImageContainer(image: PlatformImage(), data: Data(count: 10))

        // When
        pipeline.cache[request] = ImageContainer(image: PlatformImage(), data: Data(count: 500))

        // Then
        #expect(pipeline.cache[request]?.data?.count != 10) // fails
    }
}
