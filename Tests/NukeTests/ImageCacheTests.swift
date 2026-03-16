// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

private func _request(index: Int) -> ImageRequest {
    return ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
}
private let request1 = _request(index: 1)
private let request2 = _request(index: 2)
private let request3 = _request(index: 3)

@Suite(.timeLimit(.minutes(2)))
struct ImageCacheTests {
    let cache: ImageCache

    init() {
        cache = ImageCache()
        cache.entryCostLimit = 2
    }

    // MARK: - Basics

    @Test func cacheCreation() {
        #expect(cache.totalCount == 0)
        #expect(cache[Test.request] == nil)
    }

    @Test func imageIsStored() {
        // When
        cache[Test.request] = Test.container

        // Then
        #expect(cache.totalCount == 1)
        #expect(cache[Test.request] != nil)
    }

    // MARK: - Subscript

    @Test func imageIsStoredUsingSubscript() {
        // When
        cache[Test.request] = Test.container

        // Then
        #expect(cache[Test.request] != nil)
    }

    // MARK: - Count

    @Test func totalCountChanges() {
        #expect(cache.totalCount == 0)

        cache[request1] = Test.container
        #expect(cache.totalCount == 1)

        cache[request2] = Test.container
        #expect(cache.totalCount == 2)

        cache[request2] = nil
        #expect(cache.totalCount == 1)

        cache[request1] = nil
        #expect(cache.totalCount == 0)
    }

    @Test func countLimitChanges() {
        // When
        cache.countLimit = 1

        // Then
        #expect(cache.countLimit == 1)
    }

    @Test func ttlChanges() {
        // When
        cache.ttl = 1

        // Then
        #expect(cache.ttl == 1)
    }

    @Test func itemsAreRemovedImmediatelyWhenCountLimitIsReached() {
        // Given
        cache.countLimit = 1

        // When
        cache[request1] = Test.container
        cache[request2] = Test.container

        // Then
        #expect(cache[request1] == nil)
        #expect(cache[request2] != nil)
    }

    @Test func trimToCount() {
        // Given
        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        cache.trim(toCount: 1)

        // Then
        #expect(cache[request1] == nil)
        #expect(cache[request2] != nil)
    }

    @Test func countLimitOfZeroPreventsCaching() {
        // Given
        cache.countLimit = 0

        // When
        cache[request1] = Test.container

        // Then
        #expect(cache.totalCount == 0)
        #expect(cache[request1] == nil)
    }

    @Test func imagesAreRemovedOnCountLimitChange() {
        // Given
        cache.countLimit = 2

        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        cache.countLimit = 1

        // Then
        #expect(cache[request1] == nil)
        #expect(cache[request2] != nil)
    }

    // MARK: Cost

#if !os(macOS)

    @Test func defaultImageCost() {
        #expect(cache.cost(for: ImageContainer(image: Test.image)) == 1228800)
    }

    @Test func totalCostChanges() {
        let imageCost = cache.cost(for: ImageContainer(image: Test.image))
        #expect(cache.totalCost == 0)

        cache[request1] = Test.container
        #expect(cache.totalCost == imageCost)

        cache[request2] = Test.container
        #expect(cache.totalCost == 2 * imageCost)

        cache[request2] = nil
        #expect(cache.totalCost == imageCost)

        cache[request1] = nil
        #expect(cache.totalCost == 0)
    }

    @Test func replacingExistingEntryKeepsCostConsistent() {
        // Given
        cache.costLimit = Int.max
        cache[request1] = Test.container
        let costAfterFirstStore = cache.totalCost

        // When - store a new container at the same key
        cache[request1] = Test.container

        // Then - cost should not double; the old entry cost is replaced
        #expect(cache.totalCost == costAfterFirstStore)
        #expect(cache.totalCount == 1)
    }

    @Test func costLimitOfZeroPreventsCaching() {
        // Given
        cache.costLimit = 0

        // When
        cache[request1] = Test.container

        // Then
        #expect(cache.totalCost == 0)
        #expect(cache[request1] == nil)
    }

    @Test func costLimitChanged() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))

        // When
        cache.costLimit = Int(Double(cost) * 1.5)

        // Then
        #expect(cache.costLimit == Int(Double(cost) * 1.5))
    }

    @Test func itemsAreRemovedImmediatelyWhenCostLimitIsReached() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = Int(Double(cost) * 1.5)

        // When/Then
        cache[request1] = Test.container

        // LRU item is released
        cache[request2] = Test.container
        #expect(cache[request1] == nil)
        #expect(cache[request2] != nil)
    }

    @Test func entryCostLimitEntryStored() {
        // Given
        let container = ImageContainer(image: Test.image)
        let cost = cache.cost(for: container)
        cache.costLimit = Int(Double(cost) * 15)
        cache.entryCostLimit = 0.1

        // When
        cache[Test.request] = container

        // Then
        #expect(cache[Test.request] != nil)
        #expect(cache.totalCount == 1)
    }

    @Test func entryCostLimitEntryNotStored() {
        // Given
        let container = ImageContainer(image: Test.image)
        let cost = cache.cost(for: container)
        cache.costLimit = Int(Double(cost) * 3)
        cache.entryCostLimit = 0.1

        // When
        cache[Test.request] = container

        // Then
        #expect(cache[Test.request] == nil)
        #expect(cache.totalCount == 0)
    }

    @Test func trimToCost() {
        // Given
        cache.costLimit = Int.max

        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.trim(toCost: Int(Double(cost) * 1.5))

        // Then
        #expect(cache[request1] == nil)
        #expect(cache[request2] != nil)
    }

    @Test func imagesAreRemovedOnCostLimitChange() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = Int(Double(cost) * 2.5)

        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        cache.costLimit = cost

        // Then
        #expect(cache[request1] == nil)
        #expect(cache[request2] != nil)
    }

    @Test func imageContainerWithoutAssociatedDataCost() {
        // Given
        let data = Test.data(name: "cat", extension: "gif")
        let image = PlatformImage(data: data)!
        let container = ImageContainer(image: image, data: nil)

        // Then
        #expect(cache.cost(for: container) == 558000)
    }

    @Test func imageContainerWithAssociatedDataCost() {
        // Given
        let data = Test.data(name: "cat", extension: "gif")
        let image = PlatformImage(data: data)!
        let container = ImageContainer(image: image, data: data)

        // Then
        #expect(cache.cost(for: container) == 558000 + 427672)
    }

#endif

    // MARK: LRU

    @Test func leastRecentItemsAreRemoved() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = Int(Double(cost) * 2.5)

        cache[request1] = Test.container
        cache[request2] = Test.container
        cache[request3] = Test.container

        // Then
        #expect(cache[request1] == nil)
        #expect(cache[request2] != nil)
        #expect(cache[request3] != nil)
    }

    @Test func itemsAreTouched() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = Int(Double(cost) * 2.5)

        cache[request1] = Test.container
        cache[request2] = Test.container
        _ = cache[request1] // Touched image

        // When
        cache[request3] = Test.container

        // Then
        #expect(cache[request1] != nil)
        #expect(cache[request2] == nil)
        #expect(cache[request3] != nil)
    }

    @Test func trimToCountRespectsLRUOrder() {
        // Given - three items inserted in order
        cache.countLimit = Int.max
        cache[request1] = Test.container
        cache[request2] = Test.container
        cache[request3] = Test.container

        // When - access request1 and request3, making request2 the LRU item
        _ = cache[request1]
        _ = cache[request3]

        // Trim down to 2 items
        cache.trim(toCount: 2)

        // Then - the LRU item (request2) is evicted; recently accessed items remain
        #expect(cache[request1] != nil)
        #expect(cache[request2] == nil)
        #expect(cache[request3] != nil)
        #expect(cache.totalCount == 2)
    }

    // MARK: Misc

    @Test func removeAll() {
        // GIVEN
        cache[request1] = Test.container
        cache[request2] = Test.container

        // WHEN
        cache.removeAll()

        // THEN
        #expect(cache.totalCount == 0)
        #expect(cache.totalCost == 0)
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @MainActor
    @Test func someImagesAreRemovedOnDidEnterBackground() async {
        // GIVEN
        cache.costLimit = Int.max
        cache.countLimit = 10 // 1 out of 10 images should remain

        for i in 0..<10 {
            cache[_request(index: i)] = Test.container
        }
        #expect(cache.totalCount == 10)

        // WHEN
        await Task.yield() // Allow the background notification observer to be registered
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // THEN
        #expect(cache.totalCount == 1)
    }

    @MainActor
    @Test func someImagesAreRemovedBasedOnCostOnDidEnterBackground() async {
        // GIVEN
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = cost * 10
        cache.countLimit = Int.max

        for index in 0..<10 {
            let request = ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
            cache[request] = Test.container
        }
        #expect(cache.totalCount == 10)

        // WHEN
        await Task.yield() // Allow the background notification observer to be registered
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // THEN
        #expect(cache.totalCount == 1)
    }

#endif
}

@Suite(.timeLimit(.minutes(2)))
struct InternalCacheTTLTests {
    let cache = Cache<Int, Int>(costLimit: 1000, countLimit: 1000)

    // MARK: TTL

    @Test func ttl() async throws {
        // Given
        cache.set(1, forKey: 1, cost: 1, ttl: 0.05)  // 50 ms
        #expect(cache.value(forKey: 1) != nil)

        // When
        try await Task.sleep(for: .milliseconds(55))

        // Then
        #expect(cache.value(forKey: 1) == nil)
    }

    @Test func defaultTTLIsUsed() async throws {
        // Given
        cache.conf.ttl = 0.05 // 50 ms
        cache.set(1, forKey: 1, cost: 1)
        #expect(cache.value(forKey: 1) != nil)

        // When
        try await Task.sleep(for: .milliseconds(55))

        // Then
        #expect(cache.value(forKey: 1) == nil)
    }

    @Test func defaultToNonExpiringEntries() async throws {
        // Given
        cache.set(1, forKey: 1, cost: 1)
        #expect(cache.value(forKey: 1) != nil)

        // When
        try await Task.sleep(for: .milliseconds(55))

        // Then
        #expect(cache.value(forKey: 1) != nil)
    }
}
