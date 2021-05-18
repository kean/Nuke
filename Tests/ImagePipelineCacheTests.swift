// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineCacheTests: XCTestCase {
    var memoryCache: MockImageCache!
    var diskCache: MockDataCache!
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var cache: ImagePipeline.Cache { pipeline.cache }

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        diskCache = MockDataCache()
        memoryCache = MockImageCache()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = memoryCache
            $0.dataCache = diskCache
        }
    }

    // MARK: Subscripts

    func testSubscript() {
        // WHEN/THEN
        cache[Test.request] = Test.container
        XCTAssertNotNil(cache[Test.request])
    }

    // MARK: Cached Image

    func testGetCachedImageDefaultFromMemoryCache() {
        // GIVEN
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        let image = cache.cachedImage(for: request)

        // THEN
        XCTAssertNotNil(image)
    }

    func testGetCachedImageDefaultFromDiskCache() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request)

        // THEN
        XCTAssertNotNil(image)
    }

    func testGetCachedImageDefaultFromDiskCacheWhenOptionEnabled() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request, caches: [.disk])

        // THEN returns nil because queries only memory cache by default
        XCTAssertNotNil(image)
    }

    func testGetCachedImageDefaultNotStored() {
        // GIVEN
        let request = Test.request

        // WHEN
        let image = cache.cachedImage(for: request)

        // THEN
        XCTAssertNil(image)
    }

    func testGetCachedImageDefaultFromMemoryCacheWhenCachePolicyPreventsLookup() {
        // GIVEN
        var request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        request.cachePolicy = .reloadIgnoringCachedData
        let image = cache.cachedImage(for: request)

        // THEN
        XCTAssertNil(image)
    }

    func testGetCachedImageDefaultFromDiskCacheWhenCachePolicyPreventsLookup() {
        // GIVEN
        var request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        request.cachePolicy = .reloadIgnoringCachedData
        let image = cache.cachedImage(for: request, caches: [.disk])

        // THEN
        XCTAssertNil(image)
    }

    func testGetCachedImageOnlyFromMemoryStoredInMemory() {
        // GIVEN
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        let image = cache.cachedImage(for: request, caches: [.memory])

        // THEN
        XCTAssertNotNil(image)
    }

    func testGetCachedImageOnlyFromMemoryStoredOnDisk() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request, caches: [.memory])

        // THEN
        XCTAssertNil(image)
    }

    // MARK: Store Cached Image

    func testStoreCachedImageMemoryCache() {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // THEN
        XCTAssertNotNil(cache.cachedImage(for: request))
        XCTAssertNotNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNotNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNotNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCachedImageInDiskCache() {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // THEN
        XCTAssertNotNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNotNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNotNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCachedImageInBothLayers() {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // THEN
        XCTAssertNotNil(cache.cachedImage(for: request))
        XCTAssertNotNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNotNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNotNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCachedData() {
        // WHEN
        let request = Test.request
        cache.storeCachedData(Test.data, for: request)

        // THEN
        XCTAssertNotNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNotNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNotNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCacheImageWhenMemoryCacheWriteDisabled() {
        // WHEN
        var request = Test.request
        request.options.insert(.disableMemoryCacheWrite)
        cache.storeCachedImage(Test.container, for: request, caches: [.memory])

        // THEN
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    // MARK: Contains

    func testContainsWhenStoredInMemoryCache() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])

        // WHEN/THEN
        XCTAssertTrue(cache.containsCachedImage(for: Test.request))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.all]))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        XCTAssertFalse(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    func testContainsWhenStoredInDiskCache() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // WHEN/THEN
        XCTAssertTrue(cache.containsCachedImage(for: Test.request))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.all]))
        XCTAssertFalse(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    func testsContainsStoredInBoth() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.all])

        // WHEN/THEN
        XCTAssertTrue(cache.containsCachedImage(for: Test.request))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.all]))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    func testContainsData() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // WHEN/THEN
        XCTAssertTrue(cache.containsData(for: Test.request))
    }

    // MARK: Remove

    func testRemoveFromMemoryCache() {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // WHEN
        cache.removeCachedImage(for: request)

        // THEN
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])
    }

    func testRemoveFromDiskCache() {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // WHEN
        cache.removeCachedImage(for: request, caches: [.disk])

        // THEN
        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testRemoveFromAllCaches() {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // WHEN
        cache.removeCachedImage(for: request, caches: [.memory, .disk])

        // THEN
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    // MARK: Remove All

    func testRemoveAll() {
        // GIVEM
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // WHEN
        cache.removeAll()

        // THEN
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testRemoveAllWithAllStatic() {
        // GIVEM
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.all])

        // WHEN
        cache.removeAll()

        // THEN
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }
}
