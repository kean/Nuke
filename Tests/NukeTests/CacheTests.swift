// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Tests for the internal memory cache that backs ``ImageCache``. Exercising it
/// directly makes the cost accounting and the eviction order testable with
/// explicit costs on every platform.
@Suite(.timeLimit(.minutes(5)))
struct InternalCacheTests {
    private func makeCache(
        costLimit: Int = 1000,
        countLimit: Int = 100,
        entryCostLimit: Double = 1
    ) -> Cache<String, String> {
        let cache = Cache<String, String>(costLimit: costLimit, countLimit: countLimit)
        cache.conf.entryCostLimit = entryCostLimit
        return cache
    }

    // MARK: - Basics

    @Test func storingAndRetrievingValues() {
        // Given
        let cache = makeCache()

        // When
        cache.set("value", forKey: "key", cost: 10)

        // Then
        #expect(cache.value(forKey: "key") == "value")
        #expect(cache.totalCount == 1)
        #expect(cache.totalCost == 10)
    }

    @Test func retrievingAMissingValue() {
        #expect(makeCache().value(forKey: "key") == nil)
    }

    @Test func removingAValueReturnsIt() {
        // Given
        let cache = makeCache()
        cache.set("value", forKey: "key", cost: 10)

        // When
        let removed = cache.removeValue(forKey: "key")

        // Then
        #expect(removed == "value")
        #expect(cache.totalCount == 0)
        #expect(cache.totalCost == 0)
    }

    @Test func removingAMissingValueReturnsNil() {
        #expect(makeCache().removeValue(forKey: "key") == nil)
    }

    @Test func removingAllValues() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 10)
        cache.set("b", forKey: "b", cost: 20)

        // When
        cache.removeAllCachedValues()

        // Then
        #expect(cache.totalCount == 0)
        #expect(cache.totalCost == 0)
        #expect(cache.value(forKey: "a") == nil)
    }

    // MARK: - Overwriting

    @Test func overwritingAnEntryUpdatesTheTotalCost() {
        // Given
        let cache = makeCache()
        cache.set("first", forKey: "key", cost: 100)

        // When
        cache.set("second", forKey: "key", cost: 30)

        // Then the cost of the replaced entry is subtracted
        #expect(cache.value(forKey: "key") == "second")
        #expect(cache.totalCount == 1)
        #expect(cache.totalCost == 30)
    }

    @Test func overwritingAnEntryDoesNotCreateADuplicate() {
        // Given
        let cache = makeCache(countLimit: 2)
        cache.set("a", forKey: "a", cost: 1)

        // When the same key is written repeatedly
        for _ in 0..<10 {
            cache.set("a", forKey: "a", cost: 1)
        }
        cache.set("b", forKey: "b", cost: 1)

        // Then both entries are still there
        #expect(cache.totalCount == 2)
        #expect(cache.value(forKey: "a") == "a")
        #expect(cache.value(forKey: "b") == "b")
    }

    // MARK: - Entry Cost Limit

    @Test func entryExceedingTheEntryCostLimitIsNotStored() {
        // Given a cache that accepts entries up to 10% of its cost limit
        let cache = makeCache(costLimit: 100, entryCostLimit: 0.1)

        // When
        cache.set("small", forKey: "small", cost: 9)
        cache.set("large", forKey: "large", cost: 11)

        // Then
        #expect(cache.value(forKey: "small") == "small")
        #expect(cache.value(forKey: "large") == nil)
        #expect(cache.totalCost == 9)
    }

    @Test func entryCostLimitIsClampedToTheValidRange() {
        // Given an out-of-range limit
        let cache = makeCache(costLimit: 100, entryCostLimit: 5)

        // Then it behaves as if it were `1` – any entry within the cost limit fits
        cache.set("value", forKey: "key", cost: 99)
        #expect(cache.value(forKey: "key") == "value")
    }

    @Test func negativeEntryCostLimitRejectsEverything() {
        // Given
        let cache = makeCache(costLimit: 100, entryCostLimit: -1)

        // When
        cache.set("value", forKey: "key", cost: 0)

        // Then
        #expect(cache.value(forKey: "key") == nil)
    }

    // MARK: - Trimming

    @Test func trimToCost() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 10)
        cache.set("b", forKey: "b", cost: 10)
        cache.set("c", forKey: "c", cost: 10)

        // When
        cache.trim(toCost: 20)

        // Then the least recently used entry is evicted first
        #expect(cache.totalCost == 20)
        #expect(cache.value(forKey: "a") == nil)
        #expect(cache.value(forKey: "c") == "c")
    }

    @Test func trimToCount() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 1)
        cache.set("b", forKey: "b", cost: 1)
        cache.set("c", forKey: "c", cost: 1)

        // When
        cache.trim(toCount: 1)

        // Then
        #expect(cache.totalCount == 1)
        #expect(cache.value(forKey: "c") == "c")
    }

    @Test func trimToZero() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 1)

        // When
        cache.trim(toCount: 0)

        // Then
        #expect(cache.totalCount == 0)
    }

    @Test func loweringTheCostLimitTrimsTheCache() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 10)
        cache.set("b", forKey: "b", cost: 10)

        // When
        cache.conf.costLimit = 10

        // Then
        #expect(cache.totalCost == 10)
        #expect(cache.value(forKey: "b") == "b")
    }

    @Test func loweringTheCountLimitTrimsTheCache() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 1)
        cache.set("b", forKey: "b", cost: 1)

        // When
        cache.conf.countLimit = 1

        // Then
        #expect(cache.totalCount == 1)
        #expect(cache.value(forKey: "b") == "b")
    }

    @Test func entriesAreEvictedImmediatelyWhenTheCostLimitIsReached() {
        // Given
        let cache = makeCache(costLimit: 20)

        // When
        cache.set("a", forKey: "a", cost: 10)
        cache.set("b", forKey: "b", cost: 10)
        cache.set("c", forKey: "c", cost: 10)

        // Then
        #expect(cache.totalCost == 20)
        #expect(cache.value(forKey: "a") == nil)
    }

    // MARK: - Eviction Order (CLOCK)

    @Test func recentlyUsedEntriesGetASecondChance() {
        // Given a full cache
        let cache = makeCache(countLimit: 3)
        cache.set("a", forKey: "a", cost: 1)
        cache.set("b", forKey: "b", cost: 1)
        cache.set("c", forKey: "c", cost: 1)

        // When "a" is read and a new entry forces an eviction
        _ = cache.value(forKey: "a")
        cache.set("d", forKey: "d", cost: 1)

        // Then "a" survives and the next unreferenced entry is evicted instead
        #expect(cache.value(forKey: "a") == "a")
        #expect(cache.value(forKey: "b") == nil)
        #expect(cache.totalCount == 3)
    }

    @Test func overwritingAnEntryCountsAsAUse() {
        // Given a full cache
        let cache = makeCache(countLimit: 3)
        cache.set("a", forKey: "a", cost: 1)
        cache.set("b", forKey: "b", cost: 1)
        cache.set("c", forKey: "c", cost: 1)

        // When "a" is overwritten and a new entry forces an eviction
        cache.set("a2", forKey: "a", cost: 1)
        cache.set("d", forKey: "d", cost: 1)

        // Then
        #expect(cache.value(forKey: "a") == "a2")
        #expect(cache.value(forKey: "b") == nil)
    }

    // MARK: - TTL

    @Test func expiredEntriesAreNotReturned() {
        // Given an entry that expired a second ago
        let cache = makeCache()
        cache.set("value", forKey: "key", cost: 10, ttl: -1)

        // Then
        #expect(cache.value(forKey: "key") == nil)
        // ...and it is evicted on access
        #expect(cache.totalCount == 0)
        #expect(cache.totalCost == 0)
    }

    @Test func entriesWithoutTTLNeverExpire() {
        // Given
        let cache = makeCache()
        cache.set("value", forKey: "key", cost: 10)

        // Then
        #expect(cache.value(forKey: "key") == "value")
    }

    @Test func defaultTTLIsUsedWhenNoneIsGiven() {
        // Given a cache with a default TTL in the past
        let cache = makeCache()
        cache.conf.ttl = -1

        // When
        cache.set("value", forKey: "key", cost: 10)

        // Then
        #expect(cache.value(forKey: "key") == nil)
    }

    @Test func perEntryTTLOverridesTheDefault() {
        // Given
        let cache = makeCache()
        cache.conf.ttl = -1

        // When
        cache.set("value", forKey: "key", cost: 10, ttl: 60)

        // Then
        #expect(cache.value(forKey: "key") == "value")
    }
}
