// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG (off-by-one): an image whose cost is exactly the maximum
// `entryCostLimit` allows is not stored.
//
// Docs: `ImageCache.entryCostLimit` – "The maximum cost of an entry in
// proportion to the costLimit". The admission check in `Cache.set`
// (Sources/Nuke/Caching/Cache.swift:135) is `guard cost < _conf.entryMaxCost`,
// which makes the documented maximum itself inadmissible.
//
// Expected: with `entryCostLimit = 1` an image that costs exactly `costLimit`
// – which the cache has room for, `totalCost <= costLimit` – is stored; with
// the default `0.1` and a 1000-byte limit, a 100-byte image is stored.
// Actual: both are dropped; only images costing strictly less are stored.
@Suite(.timeLimit(.minutes(5)))
struct MemoryCacheEntryCostBoundaryRepro {
    @Test func imageCostingTheWholeLimitIsStoredWhenEntryCostLimitIsOne() {
        // Given
        let cache = ImageCache(costLimit: 100, countLimit: .max)
        cache.entryCostLimit = 1
        let key = ImageCacheKey(key: "a")

        // When storing an image that costs exactly the limit (1 + 99 bytes)
        cache[key] = ImageContainer(image: PlatformImage(), data: Data(count: 99))

        // Then
        #expect(cache[key] != nil) // fails
        #expect(cache.totalCost == 100) // fails: 0
    }

    @Test func imageCostingTheEntryMaximumIsStored() {
        // Given a maximum entry cost of 0.1 × 1000 = 100
        let cache = ImageCache(costLimit: 1000, countLimit: .max)
        let key = ImageCacheKey(key: "a")

        // When
        cache[key] = ImageContainer(image: PlatformImage(), data: Data(count: 99)) // cost 100

        // Then
        #expect(cache[key] != nil) // fails
    }
}
