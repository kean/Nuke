// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

private func _request(index: Int) -> ImageRequest {
    return ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
}
private let request1 = _request(index: 1)
private let request2 = _request(index: 2)
private let request3 = _request(index: 3)

class ImageCacheTests: XCTestCase {
    var cache: ImageCache!

    override func setUp() {
        super.setUp()

        cache = ImageCache()
        cache.entryCostLimit = 2
    }

    // MARK: - Basics

    func testCacheCreation() {
        XCTAssertEqual(cache.totalCount, 0)
        XCTAssertNil(cache[Test.request])
    }

    func testThatImageIsStored() {
        // When
        cache[Test.request] = Test.container

        // Then
        XCTAssertEqual(cache.totalCount, 1)
        XCTAssertNotNil(cache[Test.request])
    }

    // MARK: - Subscript

    func testThatImageIsStoredUsingSubscript() {
        // When
        cache[Test.request] = Test.container

        // Then
        XCTAssertNotNil(cache[Test.request])
    }

    // MARK: - Count

    func testThatTotalCountChanges() {
        XCTAssertEqual(cache.totalCount, 0)

        cache[request1] = Test.container
        XCTAssertEqual(cache.totalCount, 1)

        cache[request2] = Test.container
        XCTAssertEqual(cache.totalCount, 2)

        cache[request2] = nil
        XCTAssertEqual(cache.totalCount, 1)

        cache[request1] = nil
        XCTAssertEqual(cache.totalCount, 0)
    }

    func testThatCountLimitChanges() {
        // When
        cache.countLimit = 1

        // Then
        XCTAssertEqual(cache.countLimit, 1)
    }

    func testThatItemsAreRemoveImmediatelyWhenCountLimitIsReached() {
        // Given
        cache.countLimit = 1

        // When
        cache[request1] = Test.container
        cache[request2] = Test.container

        // Then
        XCTAssertNil(cache[request1])
        XCTAssertNotNil(cache[request2])
    }

    func testTrimToCount() {
        // Given
        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        cache.trim(toCount: 1)

        // Then
        XCTAssertNil(cache[request1])
        XCTAssertNotNil(cache[request2])
    }

    func testThatImagesAreRemovedOnCountLimitChange() {
        // Givne
        cache.countLimit = 2

        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        cache.countLimit = 1

        // Then
        XCTAssertNil(cache[request1])
        XCTAssertNotNil(cache[request2])
    }

    // MARK: Cost

    #if !os(macOS)

    func testDefaultImageCost() {
        XCTAssertEqual(cache.cost(for: ImageContainer(image: Test.image)), 1228800)
    }

    func testThatTotalCostChanges() {
        let imageCost = cache.cost(for: ImageContainer(image: Test.image))
        XCTAssertEqual(cache.totalCost, 0)

        cache[request1] = Test.container
        XCTAssertEqual(cache.totalCost, imageCost)

        cache[request2] = Test.container
        XCTAssertEqual(cache.totalCost, 2 * imageCost)

        cache[request2] = nil
        XCTAssertEqual(cache.totalCost, imageCost)

        cache[request1] = nil
        XCTAssertEqual(cache.totalCost, 0)
    }

    func testThatCostLimitChanged() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))

        // When
        cache.costLimit = Int(Double(cost) * 1.5)

        // Then
        XCTAssertEqual(cache.costLimit, Int(Double(cost) * 1.5))
    }

    func testThatItemsAreRemoveImmediatelyWhenCostLimitIsReached() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = Int(Double(cost) * 1.5)

        // When/Then
        cache[request1] = Test.container

        // LRU item is released
        cache[request2] = Test.container
        XCTAssertNil(cache[request1])
        XCTAssertNotNil(cache[request2])
    }

    func testEntryCostLimitEntryStored() {
        // Given
        let container = ImageContainer(image: Test.image)
        let cost = cache.cost(for: container)
        cache.costLimit = Int(Double(cost) * 15)
        cache.entryCostLimit = 0.1

        // When
        cache[Test.request] = container

        // Then
        XCTAssertNotNil(cache[Test.request])
        XCTAssertEqual(cache.totalCount, 1)
    }

    func testEntryCostLimitEntryNotStored() {
        // Given
        let container = ImageContainer(image: Test.image)
        let cost = cache.cost(for: container)
        cache.costLimit = Int(Double(cost) * 3)
        cache.entryCostLimit = 0.1

        // When
        cache[Test.request] = container

        // Then
        XCTAssertNil(cache[Test.request])
        XCTAssertEqual(cache.totalCount, 0)
    }

    func testTrimToCost() {
        // Given
        cache.costLimit = Int.max

        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.trim(toCost: Int(Double(cost) * 1.5))

        // Then
        XCTAssertNil(cache[request1])
        XCTAssertNotNil(cache[request2])
    }

    func testThatImagesAreRemovedOnCostLimitChange() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = Int(Double(cost) * 2.5)

        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        cache.costLimit = cost

        // Then
        XCTAssertNil(cache[request1])
        XCTAssertNotNil(cache[request2])
    }

    func testGIFCost() {
        // Given
        let data = Test.data(name: "cat", extension: "gif")
        let image = PlatformImage(data: data)!
        image._animatedImageData = data

        // Then
        XCTAssertFalse(ImagePipeline.Configuration._isAnimatedImageDataEnabled)
        XCTAssertEqual(cache.cost(for: ImageContainer(image: image)), 558000)

        ImagePipeline.Configuration._isAnimatedImageDataEnabled = true
        XCTAssertEqual(cache.cost(for: ImageContainer(image: image)), 558000 + 427672)
        ImagePipeline.Configuration._isAnimatedImageDataEnabled = false
    }

    func testImageContainerWithoutAssociatedDataCost() {
        // Given
        let data = Test.data(name: "cat", extension: "gif")
        let image = PlatformImage(data: data)!
        let container = ImageContainer(image: image, data: nil)

        // Then
        XCTAssertEqual(cache.cost(for: container), 558000)
    }

    func testImageContainerWithAssociatedDataCost() {
        // Given
        let data = Test.data(name: "cat", extension: "gif")
        let image = PlatformImage(data: data)!
        let container = ImageContainer(image: image, data: data)

        // Then
        XCTAssertEqual(cache.cost(for: container), 558000 + 427672)
    }

    #endif

    // MARK: LRU

    func testThatLeastRecentItemsAreRemoved() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = Int(Double(cost) * 2.5)

        cache[request1] = Test.container
        cache[request2] = Test.container
        cache[request3] = Test.container

        // Then
        XCTAssertNil(cache[request1])
        XCTAssertNotNil(cache[request2])
        XCTAssertNotNil(cache[request3])
    }

    func testThatItemsAreTouched() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = Int(Double(cost) * 2.5)

        cache[request1] = Test.container
        cache[request2] = Test.container
        _ = cache[request1] // Touched image

        // When
        cache[request3] = Test.container

        // Then
        XCTAssertNotNil(cache[request1])
        XCTAssertNil(cache[request2])
        XCTAssertNotNil(cache[request3])
    }

    // MARK: Misc

    func testRemoveAll() {
        // Given
        cache[request1] = Test.container
        cache[request2] = Test.container

        // When
        cache.removeAll()

        // Then
        XCTAssertEqual(cache.totalCount, 0)
        XCTAssertEqual(cache.totalCost, 0)
    }

    #if os(iOS) || os(tvOS)
    func testThatSomeImagesAreRemovedOnDidEnterBackground() {
        // Given
        cache.costLimit = Int.max
        cache.countLimit = 10 // 1 out of 10 images should remain

        for i in 0..<10 {
            cache[_request(index: i)] = Test.container
        }
        XCTAssertEqual(cache.totalCount, 10)

        // When
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Then
        XCTAssertEqual(cache.totalCount, 1)
    }

    func testThatSomeImagesAreRemovedBasedOnCostOnDidEnterBackground() {
        // Given
        let cost = cache.cost(for: ImageContainer(image: Test.image))
        cache.costLimit = cost * 10
        cache.countLimit = Int.max

        for index in 0..<10 {
            let request = ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
            cache[request] = Test.container
        }
        XCTAssertEqual(cache.totalCount, 10)

        // When
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Then
        XCTAssertEqual(cache.totalCount, 1)
    }
    #endif
}

class InternalCacheTTLTests: XCTestCase {
    let cache = Cache<Int, Int>(costLimit: 1000, countLimit: 1000)

    // MARK: TTL

    func testTTL() {
        // Given
        cache.set(1, forKey: 1, cost: 1, ttl: 0.05)  // 50 ms
        XCTAssertNotNil(cache.value(forKey: 1))

        // When
        usleep(55 * 1000)

        // Then
        XCTAssertNil(cache.value(forKey: 1))
    }

    func testDefaultTTLIsUsed() {
        // Given
        cache.ttl = 0.05// 50 ms
        cache.set(1, forKey: 1, cost: 1)
        XCTAssertNotNil(cache.value(forKey: 1))

        // When
        usleep(55 * 1000)

        // Then
        XCTAssertNil(cache.value(forKey: 1))
    }

    func testDefaultToNonExpiringEntries() {
        // Given
        cache.set(1, forKey: 1, cost: 1)
        XCTAssertNotNil(cache.value(forKey: 1))

        // When
        usleep(55 * 1000)

        // Then
        XCTAssertNotNil(cache.value(forKey: 1))
    }
}
