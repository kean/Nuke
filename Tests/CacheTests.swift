// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class CacheTests: XCTestCase {
    var cache: Nuke.Cache!

    override func setUp() {
        super.setUp()

        cache = Cache()
    }

    // MARK: Count

    func testThatTotalCountChanges() {
        let key1 = "key1"
        let key2 = "key2"
        XCTAssertEqual(cache.totalCount, 0)
        cache[key1] = defaultImage
        XCTAssertEqual(cache.totalCount, 1)
        cache[key2] = defaultImage
        XCTAssertEqual(cache.totalCount, 2)
        cache[key2] = nil
        XCTAssertEqual(cache.totalCount, 1)
        cache[key1] = nil
        XCTAssertEqual(cache.totalCount, 0)
    }

    func testThatItemsAreRemoveImmediatelyWhenCountLimitIsReached() {
        cache.countLimit = 1

        cache["key1"] = defaultImage
        XCTAssertNotNil(cache["key1"])

        cache["key2"] = defaultImage
        XCTAssertNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])
    }

    func testTrimToCount() {
        cache["key1"] = defaultImage
        cache["key2"] = defaultImage

        XCTAssertNotNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])

        cache.trim(toCount: 1)

        XCTAssertNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])
    }

    func testThatImagesAreRemovedOnCountLimitChange() {
        cache.countLimit = 2

        cache["key1"] = defaultImage
        cache["key2"] = defaultImage

        XCTAssertNotNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])

        cache.countLimit = 1

        XCTAssertNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])
    }

    #if !os(macOS)

    // MARK: Cost

    func testDefaultImageCost() {
        XCTAssertEqual(cache.cost(defaultImage), 1228800)
    }

    func testThatTotalCostChanges() {
        let imageCost = cache.cost(defaultImage)

        let key1 = "key1"
        let key2 = "key2"
        XCTAssertEqual(cache.totalCost, 0)
        cache[key1] = defaultImage
        XCTAssertEqual(cache.totalCost, imageCost)
        cache[key2] = defaultImage
        XCTAssertEqual(cache.totalCost, 2 * imageCost)
        cache[key2] = nil
        XCTAssertEqual(cache.totalCost, imageCost)
        cache[key1] = nil
        XCTAssertEqual(cache.totalCost, 0)
    }

    func testThatItemsAreRemoveImmediatelyWhenCostLimitIsReached() {
        let cost = cache.cost(defaultImage)
        cache.costLimit = Int(Double(cost) * 1.5)

        cache["key1"] = defaultImage
        XCTAssertNotNil(cache["key1"])

        // LRU item is released
        cache["key2"] = defaultImage
        XCTAssertNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])
    }

    func testTrimToCost() {
        cache.costLimit = Int.max

        cache["key1"] = defaultImage
        cache["key2"] = defaultImage

        XCTAssertNotNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])

        let cost = cache.cost(defaultImage)
        cache.trim(toCost: Int(Double(cost) * 1.5))

        XCTAssertNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])
    }

    func testThatImagesAreRemovedOnCostLimitChange() {
        let cost = cache.cost(defaultImage)
        cache.costLimit = Int(Double(cost) * 2.5)

        cache["key1"] = defaultImage
        cache["key2"] = defaultImage

        XCTAssertNotNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])

        cache.costLimit = cost

        XCTAssertNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])
    }

    #endif

    // MARK: LRU

    func testThatLeastRecentItemsAreRemoved() {
        let cost = cache.cost(defaultImage)
        cache.costLimit = Int(Double(cost) * 2.5)

        // case 1
        cache["key1"] = defaultImage
        cache["key2"] = defaultImage
        cache["key3"] = defaultImage
        XCTAssertNil(cache["key1"])
        XCTAssertNotNil(cache["key2"])
        XCTAssertNotNil(cache["key3"])
    }

    func testThatItemsAreTouched() {
        let cost = cache.cost(defaultImage)
        cache.costLimit = Int(Double(cost) * 2.5)

        // case 2
        cache["key1"] = defaultImage
        cache["key2"] = defaultImage

        // touched image
        let _ = cache["key1"]

        cache["key3"] = defaultImage

        XCTAssertNotNil(cache["key1"])
        XCTAssertNil(cache["key2"])
        XCTAssertNotNil(cache["key3"])
    }

    // MARK: Misc

    func testRemoveAll() {
        cache["key1"] = defaultImage
        cache["key2"] = defaultImage
        XCTAssertEqual(cache.totalCount, 2)
        cache.removeAll()
        XCTAssertEqual(cache.totalCount, 0)
        XCTAssertEqual(cache.totalCost, 0)
    }

    #if os(iOS) || os(tvOS)
    func testThatImagesAreRemovedOnMemoryWarnings() {
        let request = Request(url: defaultURL)
        cache[request] = Image()
        XCTAssertNotNil(cache[request])

        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)

        XCTAssertNil(cache[request])
    }

    func testThatSomeImagesAreRemovedOnDidEnterBackground() {
        cache.costLimit = Int.max
        cache.countLimit = 10 // 1 out of 10 images should remain

        for i in 0..<10 {
            cache[i] = defaultImage
        }

        XCTAssertEqual(cache.totalCount, 10)

        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)

        XCTAssertEqual(cache.totalCount, 1)
    }

    func testThatSomeImagesAreRemovedBasedOnCostOnDidEnterBackground() {

        let cost = cache.cost(defaultImage)
        cache.costLimit = cost * 10
        cache.countLimit = Int.max

        for i in 0..<10 {
            cache[i] = defaultImage
        }

        XCTAssertEqual(cache.totalCount, 10)

        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)

        XCTAssertEqual(cache.totalCount, 1)
    }
    #endif

    // MARK: Thread Safety

    func testThreadSafety() {
        let cache = Cache()

        func rnd_cost() -> Int {
            return (2 + rnd(20)) * 1024 * 1024
        }

        var ops = [(Void) -> Void]()

        for _ in 0..<10 { // those ops happen more frequently
            ops += [
                { cache[rnd(10)] = defaultImage },
                { cache[rnd(10)] = nil },
                { let _ = cache[rnd(10)] }
            ]
        }

        ops += [
            { cache.costLimit = rnd_cost() },
            { cache.countLimit = rnd(10) },
            { cache.trim(toCost: rnd_cost()) },
            { cache.removeAll() }
        ]

        #if os(iOS) || os(tvOS)
            ops.append {
                NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
            }
            ops.append {
                NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
            }
        #endif

        for _ in 0..<5000 {
            expect { fulfill in
                DispatchQueue.global().async {
                    ops.randomItem()()
                    fulfill()
                }
            }
        }

        wait()
    }
}


class CacheIntegrationTests: XCTestCase {
    var mockCache: MockCache!
    var mockSessionManager: MockDataLoader!
    var loader: Loader!
    
    override func setUp() {
        super.setUp()

        mockCache = MockCache()
        mockSessionManager = MockDataLoader()
        loader = Loader(loader: mockSessionManager, decoder: DataDecoder(), cache: mockCache)
    }

    func testThatCacheWorks() {
        let request = Request(url: defaultURL)

        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])

        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()

        // Suspend queue to make sure that the next request can
        // come only from cache.
        mockSessionManager.queue.isSuspended = true

        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()

        XCTAssertEqual(mockCache.images.count, 1)
        XCTAssertNotNil(mockCache[request])
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
        
        mockCache[request] = Image()
        
        XCTAssertEqual(mockCache.images.count, 1)
        let image = mockCache[request]
        XCTAssertNotNil(image)
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
        
        mockCache[request] = Image()
        
        XCTAssertEqual(mockCache.images.count, 1)
        let image = mockCache[request]
        XCTAssertNotNil(image)
        
        mockCache[request] = nil
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
    }
    
    func testThatCacheStorageCanBeDisabled() {
        var request = Request(url: defaultURL)
        XCTAssertTrue(request.memoryCacheOptions.writeAllowed)
        request.memoryCacheOptions.writeAllowed = false // Test default value
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
        
        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
    }
}
