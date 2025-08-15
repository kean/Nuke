// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

@Suite class ImagePipelineCacheTests {
    var memoryCache: MockImageCache!
    var diskCache: MockDataCache!
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var cache: ImagePipeline.Cache { pipeline.cache }

    init() {
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

    @Test func subscriptSimple() {
        // Given
        cache[Test.request] = Test.container

        // Then
        #expect(cache[Test.request] != nil)
    }

    @Test func disableMemoryCacheRead() {
        // Given
        cache[Test.request] = Test.container
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheReads])

        // Then
        #expect(cache[request] == nil)
    }

    @Test func disableMemoryCacheWrite() {
        // Given
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheWrites])
        cache[request] = Test.container

        // Then
        #expect(cache[Test.request] == nil)
    }

    @Test func subscriptRemove() {
        // Given
        cache[Test.request] = Test.container

        // When
        cache[Test.request] = nil

        // Then
        #expect(cache[Test.request] == nil)
    }

    @Test func subscriptStoringPreviewWhenDisabled() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = false
        }

        // When
        cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // Then
        #expect(cache[Test.request] == nil)
    }

    @Test func subscriptStoringPreviewWhenEnabled() throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = true
        }

        // When
        cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // Then
        let response = try #require(cache[Test.request])
        #expect(response.isPreview)
    }

    @Test func subscriptWhenNoImageCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.imageCache = nil
        }
        cache[Test.request] = Test.container

        // Then
        #expect(cache[Test.request] == nil)
    }

    @Test func subscriptWithRealImageCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.imageCache = ImageCache()
        }
        cache[Test.request] = Test.container

        // Then
        #expect(cache[Test.request] != nil)
    }

    // MARK: Cached Image

    @Test func getCachedImageDefaultFromMemoryCache() {
        // Given
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // When
        let image = cache.cachedImage(for: request)

        // Then
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultFromDiskCache() {
        // Given
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // When
        let image = cache.cachedImage(for: request)

        // Then
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultFromDiskCacheWhenOptionEnabled() {
        // Given
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // When
        let image = cache.cachedImage(for: request, caches: [.disk])

        // Then returns nil because queries only memory cache by default
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultNotStored() {
        // Given
        let request = Test.request

        // When
        let image = cache.cachedImage(for: request)

        // Then
        #expect(image == nil)
    }

    @Test func getCachedImageDefaultFromMemoryCacheWhenCachePolicyPreventsLookup() {
        // Given
        var request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // When
        request.options = [.reloadIgnoringCachedData]
        let image = cache.cachedImage(for: request)

        // Then
        #expect(image == nil)
    }

    @Test func getCachedImageDefaultFromDiskCacheWhenCachePolicyPreventsLookup() {
        // Given
        var request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // When
        request.options = [.reloadIgnoringCachedData]
        let image = cache.cachedImage(for: request, caches: [.disk])

        // Then
        #expect(image == nil)
    }

    @Test func getCachedImageOnlyFromMemoryStoredInMemory() {
        // Given
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // When
        let image = cache.cachedImage(for: request, caches: [.memory])

        // Then
        #expect(image != nil)
    }

    @Test func getCachedImageOnlyFromMemoryStoredOnDisk() {
        // Given
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // When
        let image = cache.cachedImage(for: request, caches: [.memory])

        // Then
        #expect(image == nil)
    }

    @Test func disableDiskCacheReads() {
        // Given
        cache.storeCachedData(Test.data, for: Test.request)
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheReads])

        // Then
        #expect(cache.cachedData(for: request) == nil)
    }

    @Test func disableDiskCacheWrites() {
        // Given
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])
        cache.storeCachedData(Test.data, for: request)

        // Then
        #expect(cache.cachedData(for: Test.request) == nil)
    }

    // MARK: Store Cached Image

    @Test func storeCachedImageMemoryCache() {
        // When
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // Then
        #expect(cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] != nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCachedImageInDiskCache() {
        // When
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // Then
        #expect(cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCachedImageInBothLayers() {
        // When
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // Then
        #expect(cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] != nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    // MARK: Cached Data

    @Test func storeCachedData() {
        // When
        let request = Test.request
        cache.storeCachedData(Test.data, for: request)

        // Then
        #expect(cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCacheImageWhenMemoryCacheWriteDisabled() {
        // When
        var request = Test.request
        request.options.insert(.disableMemoryCacheWrites)
        cache.storeCachedImage(Test.container, for: request, caches: [.memory])

        // Then
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func storeCacheDataWhenNoDataCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // When
        cache.storeCachedData(Test.data, for: Test.request)

        // Then just make sure it doesn't do anything weird
        #expect(cache.cachedData(for: Test.request) == nil)
    }

    @Test func getCachedDataWhenNoDataCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // Then just make sure it doesn't do anything weird
        #expect(cache.cachedData(for: Test.request) == nil)
        cache.removeCachedData(for: Test.request)
    }

    // MARK: Contains

    @Test func containsWhenStoredInMemoryCache() {
        // Given
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])

        // When/THEN
        #expect(cache.containsCachedImage(for: Test.request))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(!cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func containsWhenStoredInDiskCache() {
        // Given
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // When/THEN
        #expect(cache.containsCachedImage(for: Test.request))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(!cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func sContainsStoredInBoth() {
        // Given
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.all])

        // When/THEN
        #expect(cache.containsCachedImage(for: Test.request))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func containsData() {
        // Given
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // When/THEN
        #expect(cache.containsData(for: Test.request))
    }

    @Test func containsDataWithNoDataCache() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // When/THEN
        #expect(!cache.containsData(for: Test.request))
    }

    // MARK: Remove

    @Test func removeFromMemoryCache() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // When
        cache.removeCachedImage(for: request)

        // Then
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)
    }

    @Test func removeFromDiskCache() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // When
        cache.removeCachedImage(for: request, caches: [.disk])

        // Then
        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func removeFromAllCaches() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // When
        cache.removeCachedImage(for: request, caches: [.memory, .disk])

        // Then
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    // MARK: Remove All

    @Test func removeAll() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // When
        cache.removeAll()

        // Then
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func removeAllWithAllStatic() {
        // Given
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.all])

        // When
        cache.removeAll()

        // Then
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    // MARK: - Image Orientation

#if canImport(UIKit)
    @Test func thatImageOrientationIsPreserved() throws {
        // Given opaque jpeg with orientation
        let image = Test.image(named: "right-orientation", extension: "jpeg")
        #expect(image.cgImage!.isOpaque)
        #expect(image.imageOrientation == .right)

        // When
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: image), for: Test.request, caches: [.disk])
        let cached = pipeline.cache.cachedImage(for: Test.request, caches: [.disk])!.image

        // Then orientation is preserved
        #expect(cached.cgImage!.isOpaque)
        #expect(cached.imageOrientation == .right)
    }

    @Test func thatImageOrientationIsPreservedForProcessedImages() throws {
        // Given opaque jpeg with orientation
        let image = Test.image(named: "right-orientation", extension: "jpeg")
        #expect(image.cgImage!.isOpaque)
        #expect(image.imageOrientation == .right)

        let resized = try #require(ImageProcessors.Resize(width: 100).process(image))

        // When
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: resized), for: Test.request, caches: [.disk])
        let cached = pipeline.cache.cachedImage(for: Test.request, caches: [.disk])!.image

        // Then orientation is preserved
        #expect(cached.cgImage!.isOpaque)
        #expect(cached.imageOrientation == .right)
    }
#endif
}
