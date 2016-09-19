// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class MockCacheTests: XCTestCase {
    var mockCache: MockCache!
    var mockSessionManager: MockDataLoader!
    var loader: Loader!
    
    override func setUp() {
        super.setUp()

        mockCache = MockCache()
        mockSessionManager = MockDataLoader()
        loader = Loader(loader: mockSessionManager, decoder: DataDecoder(), cache: mockCache)
    }
    
    override func tearDown() {
        super.tearDown()
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
        
        XCTAssertEqual(mockCache.images.count, 1)
        XCTAssertNotNil(mockCache[request])
        
        mockSessionManager.queue.isSuspended = true
        
        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
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

class CacheTests: XCTestCase {
    var cache: Nuke.Cache!
    var mockSessionManager: MockDataLoader!
    var loader: Loader!
    
    override func setUp() {
        super.setUp()
        
        cache = Cache()
        mockSessionManager = MockDataLoader()
        loader = Loader(loader: mockSessionManager, decoder: DataDecoder(), cache: cache)
    }
    
    func testThatImagesAreStoredInCache() {
        let request = Request(url: defaultURL)
        
        XCTAssertNil(cache[request])

        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
        
        XCTAssertNotNil(cache[request])
        
        mockSessionManager.queue.isSuspended = true
        
        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
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
    #endif
    
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
    func testThatImageAreRemovedOnMemoryWarnings() {
        let request = Request(url: defaultURL)
        cache[request] = Image()
        XCTAssertNotNil(cache[request])
        
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        
        XCTAssertNil(cache[request])
    }
    #endif
}
