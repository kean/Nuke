// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

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
        // Given
        cache[Test.request] = Test.container

        // Then
        XCTAssertNotNil(cache[Test.request])
    }

    func testDisableMemoryCacheRead() {
        // Given
        cache[Test.request] = Test.container
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheReads])

        // Then
        XCTAssertNil(cache[request])
    }

    func testDisableMemoryCacheWrite() {
        // Given
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheWrites])
        cache[request] = Test.container

        // Then
        XCTAssertNil(cache[Test.request])
    }

    func testSubscriptRemove() {
        // Given
        cache[Test.request] = Test.container

        // When
        cache[Test.request] = nil

        // Then
        XCTAssertNil(cache[Test.request])
    }

    func testSubscriptStoringPreviewWhenDisabled() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = false
        }

        // When
        cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // Then
        XCTAssertNil(cache[Test.request])
    }

    func testSubscriptStoringPreviewWhenEnabled() throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = true
        }

        // When
        cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // Then
        let response = try XCTUnwrap(cache[Test.request])
        XCTAssertTrue(response.isPreview)
    }

    func testSubscriptWhenNoImageCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.imageCache = nil
        }
        cache[Test.request] = Test.container

        // Then
        XCTAssertNil(cache[Test.request])
    }

    func testSubscriptWithRealImageCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.imageCache = ImageCache()
        }
        cache[Test.request] = Test.container

        // Then
        XCTAssertNotNil(cache[Test.request])
    }

    // MARK: Cached Image

    func testGetCachedImageDefaultFromMemoryCache() {
        // Given
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // When
        let image = cache.cachedImage(for: request)

        // Then
        XCTAssertNotNil(image)
    }

    func testGetCachedImageDefaultFromDiskCache() {
        // Given
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // When
        let image = cache.cachedImage(for: request)

        // Then
        XCTAssertNotNil(image)
    }

    func testGetCachedImageDefaultFromDiskCacheWhenOptionEnabled() {
        // Given
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // When
        let image = cache.cachedImage(for: request, caches: [.disk])

        // Then returns nil because queries only memory cache by default
        XCTAssertNotNil(image)
    }

    func testGetCachedImageDefaultNotStored() {
        // Given
        let request = Test.request

        // When
        let image = cache.cachedImage(for: request)

        // Then
        XCTAssertNil(image)
    }

    func testGetCachedImageDefaultFromMemoryCacheWhenCachePolicyPreventsLookup() {
        // Given
        var request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // When
        request.options = [.reloadIgnoringCachedData]
        let image = cache.cachedImage(for: request)

        // Then
        XCTAssertNil(image)
    }

    func testGetCachedImageDefaultFromDiskCacheWhenCachePolicyPreventsLookup() {
        // Given
        var request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // When
        request.options = [.reloadIgnoringCachedData]
        let image = cache.cachedImage(for: request, caches: [.disk])

        // Then
        XCTAssertNil(image)
    }

    func testGetCachedImageOnlyFromMemoryStoredInMemory() {
        // Given
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // When
        let image = cache.cachedImage(for: request, caches: [.memory])

        // Then
        XCTAssertNotNil(image)
    }

    func testGetCachedImageOnlyFromMemoryStoredOnDisk() {
        // Given
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // When
        let image = cache.cachedImage(for: request, caches: [.memory])

        // Then
        XCTAssertNil(image)
    }

    func testDisableDiskCacheReads() {
        // Given
        cache.storeCachedData(Test.data, for: Test.request)
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheReads])

        // Then
        XCTAssertNil(cache.cachedData(for: request))
    }

    func testDisableDiskCacheWrites() {
        // Given
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])
        cache.storeCachedData(Test.data, for: request)

        // Then
        XCTAssertNil(cache.cachedData(for: Test.request))
    }

    // MARK: Store Cached Image

    func testStoreCachedImageMemoryCache() {
        // When
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // Then
        XCTAssertNotNil(cache.cachedImage(for: request))
        XCTAssertNotNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNotNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNotNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCachedImageInDiskCache() {
        // When
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // Then
        XCTAssertNotNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNotNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNotNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCachedImageInBothLayers() {
        // When
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // Then
        XCTAssertNotNil(cache.cachedImage(for: request))
        XCTAssertNotNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNotNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNotNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    // MARK: Cached Data

    func testStoreCachedData() {
        // When
        let request = Test.request
        cache.storeCachedData(Test.data, for: request)

        // Then
        XCTAssertNotNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNotNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNotNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCacheImageWhenMemoryCacheWriteDisabled() {
        // When
        var request = Test.request
        request.options.insert(.disableMemoryCacheWrites)
        cache.storeCachedImage(Test.container, for: request, caches: [.memory])

        // Then
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testStoreCacheDataWhenNoDataCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // When
        cache.storeCachedData(Test.data, for: Test.request)

        // Then just make sure it doesn't do anything weird
        XCTAssertNil(cache.cachedData(for: Test.request))
    }

    func testGetCachedDataWhenNoDataCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // Then just make sure it doesn't do anything weird
        XCTAssertNil(cache.cachedData(for: Test.request))
        cache.removeCachedData(for: Test.request)
    }

    // MARK: Contains

    func testContainsWhenStoredInMemoryCache() {
        // Given
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])

        // When/Them
        XCTAssertTrue(cache.containsCachedImage(for: Test.request))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.all]))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        XCTAssertFalse(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    func testContainsWhenStoredInDiskCache() {
        // Given
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // When/Them
        XCTAssertTrue(cache.containsCachedImage(for: Test.request))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.all]))
        XCTAssertFalse(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    func testsContainsStoredInBoth() {
        // Given
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.all])

        // When/Them
        XCTAssertTrue(cache.containsCachedImage(for: Test.request))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.all]))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        XCTAssertTrue(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    func testContainsData() {
        // Given
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // When/Them
        XCTAssertTrue(cache.containsData(for: Test.request))
    }

    func testContainsDataWithNoDataCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // When/Them
        XCTAssertFalse(cache.containsData(for: Test.request))
    }

    // MARK: Remove

    func testRemoveFromMemoryCache() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // When
        cache.removeCachedImage(for: request)

        // Then
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])
    }

    func testRemoveFromDiskCache() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // When
        cache.removeCachedImage(for: request, caches: [.disk])

        // Then
        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testRemoveFromAllCaches() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // When
        cache.removeCachedImage(for: request, caches: [.memory, .disk])

        // Then
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    // MARK: Remove All

    func testRemoveAll() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // When
        cache.removeAll()

        // Then
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    func testRemoveAllWithAllStatic() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.all])

        // When
        cache.removeAll()

        // Then
        XCTAssertNil(cache.cachedImage(for: request))
        XCTAssertNil(memoryCache[cache.makeImageCacheKey(for: request)])

        XCTAssertNil(cache.cachedImage(for: request, caches: [.disk]))
        XCTAssertNil(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)))
    }

    // MARK: - Image Orientation

#if canImport(UIKit)
    func testThatImageOrientationIsPreserved() throws {
        // Given opaque jpeg with orientation
        let image = Test.image(named: "right-orientation", extension: "jpeg")
        XCTAssertTrue(image.cgImage!.isOpaque)
        XCTAssertEqual(image.imageOrientation, .right)
        
        // When
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: image), for: Test.request, caches: [.disk])
        let cached = pipeline.cache.cachedImage(for: Test.request, caches: [.disk])!.image
        
        // Then orientation is preserved
        XCTAssertTrue(cached.cgImage!.isOpaque)
        XCTAssertEqual(cached.imageOrientation, .right)
    }
    
    func testThatImageOrientationIsPreservedForProcessedImages() throws {
        // Given opaque jpeg with orientation
        let image = Test.image(named: "right-orientation", extension: "jpeg")
        XCTAssertTrue(image.cgImage!.isOpaque)
        XCTAssertEqual(image.imageOrientation, .right)
        
        let resized = try XCTUnwrap(ImageProcessors.Resize(width: 100).process(image))
        
        // When
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: resized), for: Test.request, caches: [.disk])
        let cached = pipeline.cache.cachedImage(for: Test.request, caches: [.disk])!.image
        
        // Then orientation is preserved
        XCTAssertTrue(cached.cgImage!.isOpaque)
        XCTAssertEqual(cached.imageOrientation, .right)
    }
#endif
}
