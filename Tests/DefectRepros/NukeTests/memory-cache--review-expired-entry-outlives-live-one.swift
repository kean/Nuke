// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: to make room, the cache evicts a live image and keeps an
// expired one that it will never return again.
//
// The eviction sweep in `Cache._trim(while:)` (Sources/Nuke/Caching/Cache.swift:225)
// never looks at `Entry.isExpired`. An entry that was read while it was still
// fresh has its CLOCK reference bit set; once its TTL runs out, the bit still
// buys it a second chance, so the sweep rotates it to the tail and evicts the
// next unreferenced entry instead – a live image. The expired entry keeps
// counting against `totalCount` and `totalCost` until something reads it (and
// removes it) or a later sweep reaches it again.
//
// Expected: storing "c" into a full cache (count limit 2) that holds an
// expired "a" and a live "b" removes "a" – an image the cache can no longer
// serve (`ttl`: "make sure that the entries get validated at some point") –
// and keeps "b". Under true LRU "a" would go too: its last use predates "b".
// Actual: "b" is evicted; "a" survives the sweep only to be dropped on the
// next lookup, leaving the cache with one image where it had room for two.
@Suite(.timeLimit(.minutes(5)))
struct MemoryCacheExpiredEntryOutlivesLiveOneRepro {
    private func key(_ name: String) -> ImageCacheKey { ImageCacheKey(key: name) }
    private var image: ImageContainer { ImageContainer(image: PlatformImage()) }

    @Test func expiredImageIsEvictedBeforeALiveOne() {
        // Given an image that is displayed while fresh and then expires
        let cache = ImageCache(costLimit: .max, countLimit: 2)
        cache.ttl = 0.5
        cache[key("a")] = image
        let storedAt = Date.timeIntervalSinceReferenceDate
        #expect(cache[key("a")] != nil) // read within its TTL

        // Given a live image stored without a TTL
        cache.ttl = nil
        cache[key("b")] = image

        // Given "a" has expired (spin rather than sleep: exact, no guessed margin)
        while Date.timeIntervalSinceReferenceDate <= storedAt + 0.5 {}

        // When a new image needs room
        cache[key("c")] = image

        // Then the expired image is the one that goes
        #expect(cache[key("b")] != nil) // fails: the live image was evicted
        #expect(cache[key("c")] != nil)
        #expect(cache[key("a")] == nil) // expired, so a lookup misses (and drops it)
        #expect(cache.totalCount == 2) // fails: 1 – "a" took the slot "b" needed
    }
}
