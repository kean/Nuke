// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineCacheTests {
    let memoryCache: MockImageCache
    let diskCache: MockDataCache
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline
    var cache: ImagePipeline.Cache { pipeline.cache }

    init() {
        let dataLoader = MockDataLoader()
        let diskCache = MockDataCache()
        let memoryCache = MockImageCache()
        self.dataLoader = dataLoader
        self.diskCache = diskCache
        self.memoryCache = memoryCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = memoryCache
            $0.dataCache = diskCache
        }
    }

    // MARK: Subscripts

    @Test func `subscript`() {
        // GIVEN
        cache[Test.request] = Test.container

        // THEN
        #expect(cache[Test.request] != nil)
    }

    @Test func disableMemoryCacheRead() {
        // GIVEN
        cache[Test.request] = Test.container
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheReads])

        // THEN
        #expect(cache[request] == nil)
    }

    @Test func disableMemoryCacheWrite() {
        // GIVEN
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheWrites])
        cache[request] = Test.container

        // THEN
        #expect(cache[Test.request] == nil)
    }

    @Test func subscriptRemove() {
        // GIVEN
        cache[Test.request] = Test.container

        // WHEN
        cache[Test.request] = nil

        // THEN
        #expect(cache[Test.request] == nil)
    }

    @Test func subscriptStoringPreviewWhenDisabled() {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = false
        }

        // WHEN
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // THEN
        #expect(pipeline.cache[Test.request] == nil)
    }

    @Test func subscriptStoringPreviewWhenEnabled() throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = true
        }

        // WHEN
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // THEN
        let response = try #require(pipeline.cache[Test.request])
        #expect(response.isPreview)
    }

    @Test func subscriptWhenNoImageCache() {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.imageCache = nil
        }
        pipeline.cache[Test.request] = Test.container

        // THEN
        #expect(pipeline.cache[Test.request] == nil)
    }

    @Test func subscriptWithRealImageCache() {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.imageCache = ImageCache()
        }
        pipeline.cache[Test.request] = Test.container

        // THEN
        #expect(pipeline.cache[Test.request] != nil)
    }

    // MARK: Cached Image

    @Test func getCachedImageDefaultFromMemoryCache() {
        // GIVEN
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        let image = cache.cachedImage(for: request)

        // THEN
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultFromDiskCache() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request)

        // THEN
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultFromDiskCacheWhenOptionEnabled() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request, caches: [.disk])

        // THEN returns nil because queries only memory cache by default
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultNotStored() {
        // GIVEN
        let request = Test.request

        // WHEN
        let image = cache.cachedImage(for: request)

        // THEN
        #expect(image == nil)
    }

    @Test func getCachedImageDefaultFromMemoryCacheWhenCachePolicyPreventsLookup() {
        // GIVEN
        var request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        request.options = [.reloadIgnoringCachedData]
        let image = cache.cachedImage(for: request)

        // THEN
        #expect(image == nil)
    }

    @Test func getCachedImageDefaultFromDiskCacheWhenCachePolicyPreventsLookup() {
        // GIVEN
        var request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        request.options = [.reloadIgnoringCachedData]
        let image = cache.cachedImage(for: request, caches: [.disk])

        // THEN
        #expect(image == nil)
    }

    @Test func getCachedImageOnlyFromMemoryStoredInMemory() {
        // GIVEN
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        let image = cache.cachedImage(for: request, caches: [.memory])

        // THEN
        #expect(image != nil)
    }

    @Test func getCachedImageOnlyFromMemoryStoredOnDisk() {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = cache.cachedImage(for: request, caches: [.memory])

        // THEN
        #expect(image == nil)
    }

    @Test func disableDiskCacheReads() {
        // GIVEN
        cache.storeCachedData(Test.data, for: Test.request)
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheReads])

        // THEN
        #expect(cache.cachedData(for: request) == nil)
    }

    @Test func disableDiskCacheWrites() {
        // GIVEN
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])
        cache.storeCachedData(Test.data, for: request)

        // THEN
        #expect(cache.cachedData(for: Test.request) == nil)
    }

    // MARK: Store Cached Image

    @Test func storeCachedImageMemoryCache() {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // THEN
        #expect(cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] != nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCachedImageInDiskCache() {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // THEN
        #expect(cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCachedImageInBothLayers() {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // THEN
        #expect(cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] != nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    // MARK: Cached Data

    @Test func storeCachedData() {
        // WHEN
        let request = Test.request
        cache.storeCachedData(Test.data, for: request)

        // THEN
        #expect(cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCacheImageWhenMemoryCacheWriteDisabled() {
        // WHEN
        var request = Test.request
        request.options.insert(.disableMemoryCacheWrites)
        cache.storeCachedImage(Test.container, for: request, caches: [.memory])

        // THEN
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func storeCacheDataWhenNoDataCache() {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // WHEN
        pipeline.cache.storeCachedData(Test.data, for: Test.request)

        // THEN just make sure it doesn't do anything weird
        #expect(pipeline.cache.cachedData(for: Test.request) == nil)
    }

    @Test func getCachedDataWhenNoDataCache() {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // THEN just make sure it doesn't do anything weird
        #expect(pipeline.cache.cachedData(for: Test.request) == nil)
        pipeline.cache.removeCachedData(for: Test.request)
    }

    // MARK: Contains

    @Test func containsWhenStoredInMemoryCache() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])

        // WHEN/THEN
        #expect(cache.containsCachedImage(for: Test.request))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(!cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func containsWhenStoredInDiskCache() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // WHEN/THEN
        #expect(cache.containsCachedImage(for: Test.request))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(!cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func containsStoredInBoth() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.all])

        // WHEN/THEN
        #expect(cache.containsCachedImage(for: Test.request))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func containsData() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // WHEN/THEN
        #expect(cache.containsData(for: Test.request))
    }

    @Test func containsDataWithNoDataCache() {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // WHEN/THEN
        #expect(!pipeline.cache.containsData(for: Test.request))
    }

    // MARK: Remove

    @Test func removeFromMemoryCache() {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // WHEN
        cache.removeCachedImage(for: request)

        // THEN
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)
    }

    @Test func removeFromDiskCache() {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // WHEN
        cache.removeCachedImage(for: request, caches: [.disk])

        // THEN
        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func removeFromAllCaches() {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // WHEN
        cache.removeCachedImage(for: request, caches: [.memory, .disk])

        // THEN
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    // MARK: Remove All

    @Test func removeAll() {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // WHEN
        cache.removeAll()

        // THEN
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func removeAllWithAllStatic() {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.all])

        // WHEN
        cache.removeAll()

        // THEN
        #expect(cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    // MARK: - Image Orientation

#if canImport(UIKit)
    @Test func thatImageOrientationIsPreserved() throws {
        // GIVEN opaque jpeg with orientation
        let image = Test.image(named: "right-orientation", extension: "jpeg")
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.isOpaque)
        #expect(image.imageOrientation == .right)

        // WHEN
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: image), for: Test.request, caches: [.disk])
        let cached = try #require(pipeline.cache.cachedImage(for: Test.request, caches: [.disk])?.image)

        // THEN orientation is preserved
        let cachedCGImage = try #require(cached.cgImage)
        #expect(cachedCGImage.isOpaque)
        #expect(cached.imageOrientation == .right)
    }

    @Test func thatImageOrientationIsPreservedForProcessedImages() throws {
        // GIVEN opaque jpeg with orientation
        let image = Test.image(named: "right-orientation", extension: "jpeg")
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.isOpaque)
        #expect(image.imageOrientation == .right)

        let resized = try #require(ImageProcessors.Resize(width: 100).process(image))

        // WHEN
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: resized), for: Test.request, caches: [.disk])
        let cached = try #require(pipeline.cache.cachedImage(for: Test.request, caches: [.disk])?.image)

        // THEN orientation is preserved
        let cachedCGImage = try #require(cached.cgImage)
        #expect(cachedCGImage.isOpaque)
        #expect(cached.imageOrientation == .right)
    }
#endif
}
