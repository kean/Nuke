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

    // MARK: Cached Image

    func testGetCachedImageDefaultFromMemoryCache() {
        // GIVEN
        let request = Test.request
        memoryCache[cache.makeMemoryCacheKey(for: request)] = Test.container

        // WHEN
        let image = cache.cachedImage(for: request)

        // THEN
        XCTAssertNotNil(image)
    }

    func testGetCachedImageDefaultFromDiskCache() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDiskCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request)

        // THEN returns nil because queries only memory cache by default
        XCTAssertNil(image)
    }

    func testGetCachedImageDefaultFromDiskCacheWhenOptionEnabled() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDiskCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request, sources: [.disk])

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
        memoryCache[cache.makeMemoryCacheKey(for: request)] = Test.container

        // WHEN
        request.cachePolicy = .reloadIgnoringCachedData
        let image = cache.cachedImage(for: request)

        // THEN
        XCTAssertNil(image)
    }

    func testGetCachedImageDefaultFromDiskCacheWhenCachePolicyPreventsLookup() {
        // GIVEN
        var request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDiskCacheKey(for: request))

        // WHEN
        request.cachePolicy = .reloadIgnoringCachedData
        let image = cache.cachedImage(for: request, sources: [.disk])

        // THEN
        XCTAssertNil(image)
    }

    func testGetCachedImageOnlyFromMemoryStoredInMemory() {
        // GIVEN
        let request = Test.request
        memoryCache[cache.makeMemoryCacheKey(for: request)] = Test.container

        // WHEN
        let image = cache.cachedImage(for: request, sources: [.memory])

        // THEN
        XCTAssertNotNil(image)
    }

    func testGetCachedImageOnlyFromMemoryStoredOnDisk() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDiskCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request, sources: [.memory])

        // THEN
        XCTAssertNil(image)
    }
}
