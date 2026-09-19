// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG (docs vs behavior): `ImageCache.trim(toCount:)` and
// `trim(toCost:)` remove the *most* recently used image first when every image
// has been read since the last sweep.
//
// Docs: `trim(toCount:)` – "Removes least recently used items from the cache
// until…"; `ImageCache` – "An LRU memory cache"; cache-layers.md – "LRU cleanup
// policy (least recently used are removed first)".
//
// Since "Switch to CLOCK LRU in Cache" (13.0.5), reads only set a reference bit
// (Sources/Nuke/Caching/Cache.swift:120) and the order of the list is the
// insertion order. The sweep in `_trim(while:)` (Cache.swift:227) clears the
// bits of referenced entries and rotates them, so when all of them are
// referenced it degenerates into FIFO and evicts the entry that was *inserted*
// first, however recently it was read.
//
// Expected: after reading c, b, a (in that order), `trim(toCount: 2)` removes
// `c`, the least recently used image, and keeps `a`, the most recently used.
// Actual: `a` is removed and `c` is kept.
//
// If the approximation is intended, the docs of `trim(toCount:)`,
// `trim(toCost:)`, `ImageCache` and cache-layers.md promise more than the
// cache does.
@Suite(.timeLimit(.minutes(5)))
struct MemoryCacheTrimOrderRepro {
    private func key(_ name: String) -> ImageCacheKey { ImageCacheKey(key: name) }
    private var image: ImageContainer { ImageContainer(image: PlatformImage()) }

    @Test func trimToCountRemovesTheLeastRecentlyUsedImage() {
        // Given
        let cache = ImageCache(costLimit: .max, countLimit: .max)
        cache[key("a")] = image
        cache[key("b")] = image
        cache[key("c")] = image

        // When the images are used in the reverse order – "a" last
        _ = cache[key("c")]
        _ = cache[key("b")]
        _ = cache[key("a")]
        cache.trim(toCount: 2)

        // Then the least recently used one is removed
        #expect(cache[key("a")] != nil) // fails: the most recently used image is gone
        #expect(cache[key("c")] == nil) // fails: the least recently used one is kept
    }

    @Test func trimToCostRemovesTheLeastRecentlyUsedImage() {
        // Given
        let cache = ImageCache(costLimit: .max, countLimit: .max)
        for name in ["a", "b", "c"] {
            cache[key(name)] = ImageContainer(image: PlatformImage(), data: Data(count: 9)) // cost 10
        }

        // When
        _ = cache[key("c")]
        _ = cache[key("b")]
        _ = cache[key("a")]
        cache.trim(toCost: 20)

        // Then
        #expect(cache[key("a")] != nil) // fails
        #expect(cache[key("c")] == nil) // fails
    }
}
