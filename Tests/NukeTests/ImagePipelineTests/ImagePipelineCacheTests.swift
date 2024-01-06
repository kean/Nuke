// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

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
        // GIVEN
        cache[Test.request] = Test.container

        // THEN
        XCTAssertNotNil(cache[Test.request])
    }

    func testDisableMemoryCacheRead() {
        // GIVEN
        cache[Test.request] = Test.container
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheReads])

        // THEN
        XCTAssertNil(cache[request])
    }

    func testDisableMemoryCacheWrite() {
        // GIVEN
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheWrites])
        cache[request] = Test.container

        // THEN
        XCTAssertNil(cache[Test.request])
    }

    func testSubscriptRemove() {
        // GIVEN
        cache[Test.request] = Test.container

        // WHEN
        cache[Test.request] = nil

        // THEN
        XCTAssertNil(cache[Test.request])
    }

    func testSubscriptStoringPreviewWhenDisabled() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = false
        }

        // WHEN
        cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // THEN
        XCTAssertNil(cache[Test.request])
    }

    func testSubscriptStoringPreviewWhenEnabled() throws {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = true
        }

        // WHEN
        cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // THEN
        let response = try XCTUnwrap(cache[Test.request])
        XCTAssertTrue(response.isPreview)
    }

    func testSubscriptWhenNoImageCache() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.imageCache = nil
        }
        cache[Test.request] = Test.container

        // THEN
        XCTAssertNil(cache[Test.request])
    }

    func testSubscriptWithRealImageCache() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.imageCache = ImageCache()
        }
        cache[Test.request] = Test.container

        // THEN
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
        request.options = [.reloadIgnoringCachedData]
        let image = cache.cachedImage(for: request)

        // THEN
        XCTAssertNil(image)
    }

    func testGetCachedImageDefaultFromDiskCacheWhenCachePolicyPreventsLookup() {
        // GIVEN
        var request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        request.options = [.reloadIgnoringCachedData]
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

    func testDisableDiskCacheReads() {
        // GIVEN
        cache.storeCachedData(Test.data, for: Test.request)
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheReads])

        // THEN
        XCTAssertNil(cache.cachedData(for: request))
    }

    func testDisableDiskCacheWrites() {
        // GIVEN
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])
        cache.storeCachedData(Test.data, for: request)

        // THEN
        XCTAssertNil(cache.cachedData(for: Test.request))
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

    // MARK: Cached Data

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
        request.options.insert(.disableMemoryCacheWrites)
        cache.storeCachedImage(Test.container, for: request, caches: [.memory])

        // THEN
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCacheDataWhenNoDataCache() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // WHEN
        cache.storeCachedData(Test.data, for: Test.request)

        // THEN just make sure it doesn't do anything weird
        XCTAssertNil(cache.cachedData(for: Test.request))
    }

    func testGetCachedDataWhenNoDataCache() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // THEN just make sure it doesn't do anything weird
        XCTAssertNil(cache.cachedData(for: Test.request))
        cache.removeCachedData(for: Test.request)
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

    func testContainsDataWithNoDataCache() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // WHEN/THEN
        XCTAssertFalse(cache.containsData(for: Test.request))
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
        // GIVEN
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
        // GIVEN
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

    // MARK: - Image Orientation

#if canImport(UIKit)
    func testThatImageOrientationIsPreserved() throws {
        // GIVEN opaque jpeg with orientation
        let image = Test.image(named: "left-orientation", extension: "jpeg")
        XCTAssertTrue(image.cgImage!.isOpaque)
        XCTAssertEqual(image.imageOrientation, .right)
        
        // WHEN
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: image), for: Test.request, caches: [.disk])
        let cached = pipeline.cache.cachedImage(for: Test.request, caches: [.disk])!.image
        
        // THEN orientation is preserved
        XCTAssertTrue(cached.cgImage!.isOpaque)
        XCTAssertEqual(cached.imageOrientation, .right)
    }
    
    func testThatImageOrientationIsPreservedForProcessedImages() throws {
        // GIVEN opaque jpeg with orientation
        let image = Test.image(named: "left-orientation", extension: "jpeg")
        XCTAssertTrue(image.cgImage!.isOpaque)
        XCTAssertEqual(image.imageOrientation, .right)
        
        let resized = try XCTUnwrap(ImageProcessors.Resize(width: 100).process(image))
        
        // WHEN
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: resized), for: Test.request, caches: [.disk])
        let cached = pipeline.cache.cachedImage(for: Test.request, caches: [.disk])!.image
        
        // THEN orientation is preserved
        XCTAssertTrue(cached.cgImage!.isOpaque)
        XCTAssertEqual(cached.imageOrientation, .right)
    }
#endif
}
