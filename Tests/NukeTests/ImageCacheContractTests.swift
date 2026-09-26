// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

// MARK: - Helpers

private func key(_ name: String) -> ImageCacheKey {
    ImageCacheKey(key: name)
}

/// Spins until the reference-date clock – the one the cache stamps and checks
/// expiration dates with – has moved past `instant`. It usually takes about a
/// microsecond and makes a TTL test exact without sleeping for a guessed
/// duration.
private func waitForTheClockToPass(_ instant: TimeInterval) {
    while Date.timeIntervalSinceReferenceDate <= instant {}
}

// MARK: - Defaults

@Suite(.timeLimit(.minutes(5)))
struct ImageCacheDefaultConfigurationTests {
    @Test func defaultLimits() {
        // Given
        let cache = ImageCache()

        // Then the limits are the documented defaults
        #expect(cache.costLimit == ImageCache.defaultCostLimit)
        #expect(cache.countLimit == Int.max)
        #expect(cache.ttl == nil)
        #expect(cache.totalCount == 0)
        #expect(cache.totalCost == 0)
    }

    @Test func initializerLimitsAreApplied() {
        // Given
        let cache = ImageCache(costLimit: 1234, countLimit: 56)

        // Then
        #expect(cache.costLimit == 1234)
        #expect(cache.countLimit == 56)
    }

    @Test func defaultMemoryBudgetIsAFifthOfThePhysicalMemory() {
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        let budget = Double(ImageCache.defaultMemoryBudget)
        #expect(abs(budget - physicalMemory * 0.2) <= 1)
    }

    /// The docs: "three quarters of the one budget decoded images get […]
    /// capped at 768 MB".
    @Test func defaultCostLimitIsThreeQuartersOfTheBudgetCappedAt768MB() {
        let cap = 768 * 1024 * 1024
        let threeQuarters = ImageCache.defaultMemoryBudget / 4 * 3
        let limit = ImageCache.defaultCostLimit

        #expect(limit > 0)
        #expect(limit <= cap)
        #expect(limit == min(threeQuarters, cap))
    }
}

// MARK: - Cost Accounting

@Suite(.timeLimit(.minutes(5)))
struct ImageCacheCostAccountingTests {
    let cache: ImageCache

    init() {
        cache = ImageCache(costLimit: .max, countLimit: .max)
        cache.entryCostLimit = 1
    }

    @Test func removingAMissingKeyChangesNothing() {
        // Given
        cache[key("a")] = container(cost: 10)

        // When
        cache[key("missing")] = nil

        // Then
        #expect(cache.totalCost == 10)
        #expect(cache.totalCount == 1)
    }

    @Test func costOfABitmapIsItsBytesPerRowTimesHeight() throws {
        // Given
        let image = Test.rgbImage(width: 30, height: 20)
        let cgImage = try #require(image.cgImage)

        // When
        let cost = cache.cost(for: ImageContainer(image: image))

        // Then
        #expect(cost == cgImage.bytesPerRow * cgImage.height)
        #expect(cost >= 30 * 20 * 4)
    }

    /// `AnimatedImageSource/data` is the buffer `ImageContainer/data` holds,
    /// so an animation must not be charged for it a second time.
    @Test func dataOfAnAnimatedImageIsChargedOnce() throws {
        // Given
        let gif = Test.animatedGIF(frameCount: 4, size: CGSize(width: 16, height: 16))
        let animation = try #require(AnimatedImageSource(data: gif))
        let image = Test.rgbImage(width: 16, height: 16)

        // When
        let still = cache.cost(for: ImageContainer(image: image))
        let withData = cache.cost(for: ImageContainer(image: image, data: gif))
        let animated = cache.cost(for: ImageContainer(image: image, data: gif, animation: animation))

        // Then
        #expect(withData == still + gif.count)
        #expect(animated == withData)
    }

    @Test func decodedAnimatedGIFIsChargedForItsFirstFrameAndItsData() throws {
        // Given the container the default decoder makes for an animated GIF
        let gif = Test.animatedGIF(frameCount: 3, size: CGSize(width: 12, height: 12))
        let decoded = try ImageDecoders.Default().decode(gif)
        try #require(decoded.animation != nil)
        let firstFrame = try #require(decoded.image.cgImage)

        // Then
        #expect(cache.cost(for: decoded) == firstFrame.bytesPerRow * firstFrame.height + gif.count)
    }

    @Test func previewIsChargedLikeTheFinalImage() {
        // Given
        let image = Test.rgbImage(width: 10, height: 10)

        // Then
        #expect(cache.cost(for: ImageContainer(image: image, isPreview: true)) == cache.cost(for: ImageContainer(image: image)))
    }

    // MARK: Trim

    @Test func trimToCostKeepsAnEntryThatWasReadSinceItWasStored() {
        // Given
        cache[key("a")] = container(cost: 10)
        cache[key("b")] = container(cost: 10)
        cache[key("c")] = container(cost: 10)
        _ = cache[key("a")]

        // When
        cache.trim(toCost: 20)

        // Then
        #expect(cache[key("a")] != nil)
        #expect(cache[key("b")] == nil)
        #expect(cache[key("c")] != nil)
    }

    /// A limit is a maximum – `costLimit` is "the maximum total cost that the
    /// cache can hold" – so a cache that is exactly at it already fits.
    @Test func trimToTheCurrentTotalsRemovesNothing() {
        // Given
        cache[key("a")] = container(cost: 10)
        cache[key("b")] = container(cost: 20)

        // When
        cache.trim(toCost: 30)
        cache.trim(toCount: 2)

        // Then
        #expect(cache.totalCost == 30)
        #expect(cache.totalCount == 2)
    }

    @Test func trimToCostZeroRemovesEverything() {
        // Given
        cache[key("a")] = container(cost: 10)
        cache[key("b")] = container(cost: 20)
        _ = cache[key("a")]

        // When
        cache.trim(toCost: 0)

        // Then
        #expect(cache.totalCost == 0)
        #expect(cache.totalCount == 0)
    }

    // MARK: Limits

    @Test func raisingTheLimitsKeepsEveryEntry() {
        // Given
        cache.costLimit = 100
        cache.countLimit = 5
        for name in ["a", "b", "c"] {
            cache[key(name)] = container(cost: 10)
        }

        // When
        cache.costLimit = 1000
        cache.countLimit = 50

        // Then
        #expect(cache.totalCount == 3)
        #expect(cache.totalCost == 30)
    }

    /// The largest entry the cache takes is recomputed from the cost limit, so
    /// changing the limit moves it in both directions.
    @Test func maximumEntryCostFollowsTheCostLimit() {
        // Given a maximum entry cost of 0.1 × 1000 = 100
        cache.costLimit = 1000
        cache.entryCostLimit = 0.1

        // When
        cache[key("a")] = container(cost: 201)

        // Then
        #expect(cache[key("a")] == nil)

        // When the limit goes up to 10 000, entries up to 1000 fit
        cache.costLimit = 10_000
        cache[key("b")] = container(cost: 201)

        // Then
        #expect(cache[key("b")] != nil)

        // When it goes back down, the maximum shrinks with it
        cache.costLimit = 1000
        cache[key("c")] = container(cost: 201)

        // Then
        #expect(cache[key("c")] == nil)
    }

    @Test func countAndCostLimitsAreEnforcedTogether() {
        // Given
        cache.costLimit = 25
        cache.countLimit = 3

        // When the entries are expensive, the cost limit is what evicts – two
        // of them fit, so the count limit is never reached
        for name in ["a", "b", "c", "d"] {
            cache[key(name)] = container(cost: 10)
            #expect(cache.totalCost <= 25)
            #expect(cache.totalCount <= 3)
        }
        #expect(cache.totalCount == 2)
        #expect(cache.totalCost == 20)

        // When they are cheap, the count limit is what evicts, well before
        // the cost limit is reached
        for index in 0..<10 {
            cache[key("cheap-\(index)")] = container(cost: 1)
            #expect(cache.totalCost <= 25)
            #expect(cache.totalCount <= 3)
        }
        #expect(cache.totalCount == 3)
        #expect(cache.totalCost == 3)
    }

    // MARK: Remove All

    @Test func cacheIsFullyUsableAfterRemoveAll() {
        // Given a cache emptied while it had entries that were read
        cache.countLimit = 2
        cache[key("a")] = container(cost: 10)
        cache[key("b")] = container(cost: 10)
        _ = cache[key("a")]
        cache.removeAll()

        // When
        cache[key("c")] = container(cost: 5)
        cache[key("d")] = container(cost: 6)
        cache[key("e")] = container(cost: 7)

        // Then the old entries are gone and the new ones are evicted in order
        #expect(cache[key("a")] == nil)
        #expect(cache[key("c")] == nil)
        #expect(cache[key("d")] != nil)
        #expect(cache[key("e")] != nil)
        #expect(cache.totalCount == 2)
        #expect(cache.totalCost == 13)
    }
}

// MARK: - Expiration

@Suite(.timeLimit(.minutes(5)))
struct ImageCacheExpirationTests {
    let cache = ImageCache(costLimit: .max, countLimit: .max)

    /// Before Nuke 11, a TTL of `0` meant "never expires"; `nil` means that
    /// now, and `0` is an ordinary, immediate expiration.
    @Test func zeroTTLExpiresTheImage() {
        // Given
        cache.ttl = 0

        // When
        cache[key("a")] = container(cost: 1)
        waitForTheClockToPass(Date.timeIntervalSinceReferenceDate)

        // Then
        #expect(cache[key("a")] == nil)
        #expect(cache.totalCount == 0)
    }

    @Test func infiniteTTLNeverExpires() {
        // Given
        cache.ttl = .infinity

        // When
        cache[key("a")] = container(cost: 1)
        waitForTheClockToPass(Date.timeIntervalSinceReferenceDate)

        // Then
        #expect(cache[key("a")] != nil)
    }

    /// The TTL is stamped on an entry when it is written.
    @Test func changingTheTTLAffectsOnlyImagesStoredAfterwards() {
        // Given an image stored with no TTL
        cache[key("a")] = container(cost: 1)

        // When the TTL is set to one that has already run out
        cache.ttl = -1
        cache[key("b")] = container(cost: 1)

        // Then
        #expect(cache[key("a")] != nil)
        #expect(cache[key("b")] == nil)
    }

    @Test func overwritingAnExpiredImageStoresTheNewOne() {
        // Given an image that has expired
        cache.ttl = -1
        cache[key("a")] = container(cost: 5)

        // When the key is written again without a TTL
        cache.ttl = nil
        cache[key("a")] = container(cost: 7)

        // Then the new image replaces it instead of being added beside it
        #expect(cache[key("a")]?.data?.count == 6)
        #expect(cache.totalCount == 1)
        #expect(cache.totalCost == 7)
    }

    @Test func removingAnExpiredImageReleasesItsCost() {
        // Given an image that expired but was never read
        cache.ttl = -1
        cache[key("a")] = container(cost: 5)

        // When
        cache[key("a")] = nil

        // Then
        #expect(cache.totalCost == 0)
        #expect(cache.totalCount == 0)
    }
}

// MARK: - Internal Cache

@Suite(.timeLimit(.minutes(5)))
struct InternalCacheSweepTests {
    @Test func trimWithANegativeLimitEmptiesTheCache() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 1)
        cache.set("b", forKey: "b", cost: 0)
        _ = cache.value(forKey: "a")

        // When
        cache.trim(toCount: -1)

        // Then
        #expect(cache.totalCount == 0)

        // Given
        cache.set("c", forKey: "c", cost: 0)

        // When
        cache.trim(toCost: -1)

        // Then
        #expect(cache.totalCount == 0)
        #expect(cache.totalCost == 0)
    }

    /// A read protects an entry from one sweep, not from every sweep after it.
    @Test func readProtectsAnEntryFromASingleSweep() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 1)
        cache.set("b", forKey: "b", cost: 1)
        _ = cache.value(forKey: "a")

        // When
        cache.trim(toCount: 1)

        // Then
        #expect(cache.removeValue(forKey: "b") == nil)
        #expect(cache.totalCount == 1)

        // When "a" is not read again before the next sweep
        cache.set("c", forKey: "c", cost: 1)
        cache.trim(toCount: 1)

        // Then
        #expect(cache.value(forKey: "a") == nil)
        #expect(cache.value(forKey: "c") == "c")
    }

    /// Each entry gets at most one second chance, so the sweep ends even when
    /// every entry was read.
    @Test func trimEndsWhenEveryEntryWasRead() {
        // Given
        let cache = makeCache()
        for index in 0..<100 {
            cache.set("\(index)", forKey: "\(index)", cost: 1)
        }
        for index in 0..<100 {
            _ = cache.value(forKey: "\(index)")
        }

        // When
        cache.trim(toCount: 10)

        // Then
        #expect(cache.totalCount == 10)
        #expect(cache.totalCost == 10)
    }

    @Test func evictionOrderSurvivesRemovalsFromEveryPosition() {
        // Given
        let cache = makeCache()
        for name in ["a", "b", "c", "d", "e"] {
            cache.set(name, forKey: name, cost: 1)
        }

        // When the first, a middle, and the last entry are removed
        cache.removeValue(forKey: "a")
        cache.removeValue(forKey: "c")
        cache.removeValue(forKey: "e")
        cache.set("f", forKey: "f", cost: 1)

        // Then the remaining ones are still evicted oldest first
        cache.trim(toCount: 2)
        #expect(cache.removeValue(forKey: "b") == nil)
        cache.trim(toCount: 1)
        #expect(cache.removeValue(forKey: "d") == nil)
        #expect(cache.value(forKey: "f") == "f")
        #expect(cache.totalCount == 1)
    }

    @Test func expiredEntryIsRemovedFromTheMiddleOfTheList() {
        // Given
        let cache = makeCache()
        cache.set("a", forKey: "a", cost: 1)
        cache.set("b", forKey: "b", cost: 2, ttl: -1)
        cache.set("c", forKey: "c", cost: 4)

        // When
        #expect(cache.value(forKey: "b") == nil)

        // Then
        #expect(cache.totalCount == 2)
        #expect(cache.totalCost == 5)
        cache.trim(toCount: 1)
        #expect(cache.value(forKey: "c") == "c")
    }

    #if arch(arm64) || arch(x86_64)
    /// Before the maximum entry cost was precomputed, a cost limit above
    /// `Int32.max` switched the entry limit off.
    @Test func entryCostLimitAppliesToCostLimitsAboveInt32Max() {
        // Given a maximum entry cost of 0.1 × 3 GB = 300 MB
        let cache = Cache<String, String>(costLimit: 3_000_000_000, countLimit: 100)

        // When
        cache.set("small", forKey: "small", cost: 200_000_000)
        cache.set("large", forKey: "large", cost: 400_000_000)

        // Then
        #expect(cache.value(forKey: "small") == "small")
        #expect(cache.value(forKey: "large") == nil)
    }
    #endif

    @Test func unboundedCacheTakesAnyEntry() {
        // Given a cost limit whose product with the entry limit overflows `Int`
        let cache = makeCache(costLimit: .max, countLimit: .max)

        // When
        cache.set("huge", forKey: "huge", cost: Int.max / 2)

        // Then
        #expect(cache.value(forKey: "huge") == "huge")
        #expect(cache.totalCost == Int.max / 2)
    }

    /// Drives the cache through a long, seeded sequence of writes, reads,
    /// removals, trims, and limit changes, checking the limits after every
    /// step and, at the end, that every entry holds the last value written
    /// for its key and the totals are exactly what those entries cost.
    @Test func totalsMatchTheEntriesAfterARandomSequenceOfOperations() throws {
        // Given
        let cache = makeCache(costLimit: 60, countLimit: 12)
        var lastWritten = [String: (value: String, cost: Int)]()
        var generator = SplitMix64(seed: 2026)

        // When
        for step in 0..<5_000 {
            let key = "\(Int.random(in: 0..<24, using: &generator))"
            switch Int.random(in: 0..<20, using: &generator) {
            case 0..<8:
                let value = "\(key)-\(step)"
                let cost = Int.random(in: 0...9, using: &generator)
                cache.set(value, forKey: key, cost: cost)
                lastWritten[key] = (value, cost)
            case 8..<14:
                if let value = cache.value(forKey: key), value != lastWritten[key]?.value {
                    Issue.record("Read \(value) for \(key) at step \(step), last written \(String(describing: lastWritten[key]))")
                    return
                }
            case 14..<16:
                cache.removeValue(forKey: key)
                lastWritten[key] = nil
            case 16:
                cache.trim(toCost: Int.random(in: 0...60, using: &generator))
            case 17:
                cache.trim(toCount: Int.random(in: 0...12, using: &generator))
            case 18:
                // Never below 10, so that every cost in 0...9 stays admissible
                cache.conf.costLimit = Int.random(in: 10...60, using: &generator)
            default:
                cache.conf.countLimit = Int.random(in: 1...12, using: &generator)
            }
            guard cache.totalCost <= cache.conf.costLimit, cache.totalCount <= cache.conf.countLimit else {
                Issue.record("Limits exceeded at step \(step): cost \(cache.totalCost)/\(cache.conf.costLimit), count \(cache.totalCount)/\(cache.conf.countLimit)")
                return
            }
        }

        // Then
        let totalCost = cache.totalCost
        let totalCount = cache.totalCount
        var removedCost = 0
        var removedCount = 0
        for key in (0..<24).map({ "\($0)" }) {
            guard let value = cache.removeValue(forKey: key) else { continue }
            let model = try #require(lastWritten[key])
            #expect(value == model.value)
            removedCost += model.cost
            removedCount += 1
        }
        #expect(removedCost == totalCost)
        #expect(removedCount == totalCount)
        #expect(cache.totalCost == 0)
        #expect(cache.totalCount == 0)
    }
}

// MARK: - Concurrency

@Suite(.timeLimit(.minutes(5)))
struct ImageCacheConcurrentAccountingTests {
    /// The lock must keep the map, the list and the running totals in step
    /// under contention: afterwards, the totals must be exactly what the
    /// surviving entries cost, and every entry must hold its own value.
    @Test func concurrentMutationsKeepTheTotalsConsistent() {
        // Given
        let cache = Cache<Int, Int>(costLimit: 100, countLimit: 20)
        cache.conf.entryCostLimit = 1
        let mismatches = OSAllocatedUnfairLock(initialState: 0)
        let keyCount = 40

        // When
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            var generator = SplitMix64(seed: UInt64(worker + 1))
            for _ in 0..<4_000 {
                let key = Int.random(in: 0..<keyCount, using: &generator)
                switch Int.random(in: 0..<10, using: &generator) {
                case 0..<4:
                    cache.set(key, forKey: key, cost: key % 5 + 1)
                case 4..<8:
                    if let value = cache.value(forKey: key), value != key {
                        mismatches.withLock { $0 += 1 }
                    }
                case 8:
                    cache.removeValue(forKey: key)
                default:
                    cache.trim(toCount: Int.random(in: 5...20, using: &generator))
                }
            }
        }

        // Then
        #expect(mismatches.withLock { $0 } == 0)
        #expect(cache.totalCost <= 100)
        #expect(cache.totalCount <= 20)

        let totalCost = cache.totalCost
        let totalCount = cache.totalCount
        var removedCost = 0
        var removedCount = 0
        for key in 0..<keyCount {
            guard let value = cache.removeValue(forKey: key) else { continue }
            #expect(value == key)
            removedCost += key % 5 + 1
            removedCount += 1
        }
        #expect(removedCost == totalCost)
        #expect(removedCount == totalCount)
        #expect(cache.totalCost == 0)
        #expect(cache.totalCount == 0)
    }

    @Test func concurrentReadsOfTheSameImageAllHit() {
        // Given
        let cache = ImageCache(costLimit: .max, countLimit: .max)
        cache[key("shared")] = container(cost: 10)
        let misses = OSAllocatedUnfairLock(initialState: 0)

        // When
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<2_000 {
                if cache[key("shared")] == nil {
                    misses.withLock { $0 += 1 }
                }
            }
        }

        // Then
        #expect(misses.withLock { $0 } == 0)
        #expect(cache.totalCount == 1)
        #expect(cache.totalCost == 10)
    }
}
