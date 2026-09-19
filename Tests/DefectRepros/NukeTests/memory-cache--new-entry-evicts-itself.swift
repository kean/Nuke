// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: an image stored in a full cache whose entries have all been
// read is evicted by its own insertion.
//
// `Cache._add` (Sources/Nuke/Caching/Cache.swift:156) appends the new entry to
// the tail of the list with its CLOCK reference bit clear, and `set` only then
// calls `_trim()`. The CLOCK sweep in `_trim(while:)` (Cache.swift:227) starts
// at the head: every referenced entry gets its bit cleared and is moved to the
// tail – *behind* the new entry – so once all the old entries have been
// rotated past it, the unreferenced new entry is at the head and is the one
// evicted. In the classic CLOCK algorithm the victim is chosen before the new
// page takes its slot, so a page can never evict itself.
//
// Expected (ImageCache docs: "An LRU memory cache", "discards the least
// recently cached images if either cost or count limit is reached"): storing
// `d` evicts one of the older entries, and `cache[d]` returns the image that
// was just stored.
// Actual: `cache[d]` is `nil` right after `cache[d] = image`; `a`, `b` and `c`
// all survive.
//
// In an app this is the steady state of a full cache whose images are all on
// screen (each lookup marks its entry): the next image the pipeline loads is
// dropped the moment it is stored, and the following lookup for it misses.
@Suite(.timeLimit(.minutes(5)))
struct MemoryCacheSelfEvictionRepro {
    private func key(_ name: String) -> ImageCacheKey { ImageCacheKey(key: name) }
    private var image: ImageContainer { ImageContainer(image: PlatformImage()) }

    @Test func imageStoredInAFullCacheIsKept() {
        // Given a full cache in which every image has been read since it was stored
        let cache = ImageCache(costLimit: .max, countLimit: 3)
        cache[key("a")] = image
        cache[key("b")] = image
        cache[key("c")] = image
        _ = cache[key("a")]
        _ = cache[key("b")]
        _ = cache[key("c")]

        // When a new image is stored
        cache[key("d")] = image

        // Then the image just stored is in the cache
        #expect(cache.totalCount == 3)
        #expect(cache[key("d")] != nil) // fails: "d" evicted itself
    }

    @Test func imageStoredInACacheWithACountLimitOfOneReplacesTheReadOne() {
        // Given
        let cache = ImageCache(costLimit: .max, countLimit: 1)
        cache[key("a")] = image
        _ = cache[key("a")]

        // When
        cache[key("b")] = image

        // Then the new image replaces the old one
        #expect(cache[key("b")] != nil) // fails
        #expect(cache[key("a")] == nil) // fails: the old image is kept instead
    }

    @Test func imageStoredOverTheCostLimitIsKept() {
        // Given room for three 11-byte images, all read since they were stored
        let cache = ImageCache(costLimit: 35, countLimit: .max)
        cache.entryCostLimit = 1
        func container() -> ImageContainer {
            ImageContainer(image: PlatformImage(), data: Data(count: 10)) // cost 11
        }
        cache[key("a")] = container()
        cache[key("b")] = container()
        cache[key("c")] = container()
        _ = cache[key("a")]
        _ = cache[key("b")]
        _ = cache[key("c")]

        // When
        cache[key("d")] = container()

        // Then
        #expect(cache[key("d")] != nil) // fails
    }
}
