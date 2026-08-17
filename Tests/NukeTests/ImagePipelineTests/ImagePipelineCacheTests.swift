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

    @Test func subscriptWithURL() {
        // GIVEN
        cache[Test.url] = Test.container

        // THEN the URL and the request subscripts address the same entry
        #expect(cache[Test.url] != nil)
        #expect(cache[ImageRequest(url: Test.url)] != nil)
    }

    @Test func subscriptWithURLRemove() {
        // GIVEN
        cache[Test.url] = Test.container

        // WHEN
        cache[Test.url] = nil

        // THEN
        #expect(cache[Test.url] == nil)
    }

    @Test func subscriptRemoveWhenNoImageCache() {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.imageCache = nil
        }

        // WHEN/THEN it's a no-op instead of a crash
        pipeline.cache[Test.request] = nil
        #expect(pipeline.cache[Test.request] == nil)
    }

    // MARK: Cached Image

    @Test func getCachedImageDefaultFromMemoryCache() async {
        // GIVEN
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        let image = await cache.cachedImage(for: request)

        // THEN
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultFromDiskCache() async {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = await cache.cachedImage(for: request)

        // THEN
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultFromDiskCacheWhenOptionEnabled() async {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = await cache.cachedImage(for: request, caches: [.disk])

        // THEN returns nil because queries only memory cache by default
        #expect(image != nil)
    }

    @Test func getCachedImageDefaultNotStored() async {
        // GIVEN
        let request = Test.request

        // WHEN
        let image = await cache.cachedImage(for: request)

        // THEN
        #expect(image == nil)
    }

    @Test func getCachedImageDefaultFromMemoryCacheWhenCachePolicyPreventsLookup() async {
        // GIVEN
        var request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        request.options = [.reloadIgnoringCachedData]
        let image = await cache.cachedImage(for: request)

        // THEN
        #expect(image == nil)
    }

    @Test func getCachedImageDefaultFromDiskCacheWhenCachePolicyPreventsLookup() async {
        // GIVEN
        var request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        request.options = [.reloadIgnoringCachedData]
        let image = await cache.cachedImage(for: request, caches: [.disk])

        // THEN
        #expect(image == nil)
    }

    @Test func getCachedImageOnlyFromMemoryStoredInMemory() async {
        // GIVEN
        let request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        let image = await cache.cachedImage(for: request, caches: [.memory])

        // THEN
        #expect(image != nil)
    }

    @Test func getCachedImageOnlyFromMemoryStoredOnDisk() async {
        // GIVEN
        let request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        let image = await cache.cachedImage(for: request, caches: [.memory])

        // THEN
        #expect(image == nil)
    }

    @Test func disableDiskCacheReads() async {
        // GIVEN
        cache.storeCachedData(Test.data, for: Test.request)
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheReads])

        // THEN
        #expect(await cache.cachedData(for: request) == nil)
    }

    @Test func disableDiskCacheWrites() async {
        // GIVEN
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])
        cache.storeCachedData(Test.data, for: request)

        // THEN
        #expect(await cache.cachedData(for: Test.request) == nil)
    }

    // MARK: Store Cached Image

    @Test func storeCachedImageMemoryCache() async {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // THEN
        #expect(await cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] != nil)

        #expect(await cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCachedImageInDiskCache() async {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // THEN
        #expect(await cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(await cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCachedImageInBothLayers() async {
        // WHEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // THEN
        #expect(await cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] != nil)

        #expect(await cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCachedImagePreviewIsNotStoredInDiskCache() async {
        // GIVEN a progressive preview
        let request = Test.request
        let preview = ImageContainer(image: Test.image, isPreview: true)

        // WHEN
        cache.storeCachedImage(preview, for: request)

        // THEN it never reaches the disk cache
        #expect(await cache.cachedData(for: request) == nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
        #expect(await !cache.containsData(for: request))
    }

    @Test func storeCachedImagePreviewIsNotStoredInDiskCacheWhenDiskIsTheOnlyLayer() async {
        // GIVEN a progressive preview
        let request = Test.request
        let preview = ImageContainer(image: Test.image, isPreview: true)

        // WHEN
        cache.storeCachedImage(preview, for: request, caches: [.disk])

        // THEN nothing is written to either layer
        #expect(await cache.cachedData(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)
    }

    @Test func storeCachedImageNonPreviewIsStoredInDiskCache() async {
        // GIVEN a final image
        let request = Test.request

        // WHEN
        cache.storeCachedImage(Test.container, for: request)

        // THEN it is written to the disk cache
        #expect(await cache.cachedData(for: request) != nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCachedImagePreviewInMemoryCacheWhenEnabled() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = true
        }
        let request = Test.request

        // WHEN
        pipeline.cache.storeCachedImage(ImageContainer(image: Test.image, isPreview: true), for: request)

        // THEN the memory cache behavior is unchanged, the disk cache is untouched
        let image = try #require(await pipeline.cache.cachedImage(for: request, caches: [.memory]))
        #expect(image.isPreview)
        #expect(await pipeline.cache.cachedData(for: request) == nil)
    }

    @Test func storeCachedImagePreviewInMemoryCacheWhenDisabled() async {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.isStoringPreviewsInMemoryCache = false
        }
        let request = Test.request

        // WHEN
        pipeline.cache.storeCachedImage(ImageContainer(image: Test.image, isPreview: true), for: request)

        // THEN it's stored in neither layer
        #expect(await pipeline.cache.cachedImage(for: request, caches: [.memory]) == nil)
        #expect(await pipeline.cache.cachedData(for: request) == nil)
    }

    // MARK: Cached Data

    @Test func storeCachedData() async {
        // WHEN
        let request = Test.request
        cache.storeCachedData(Test.data, for: request)

        // THEN
        #expect(await cache.cachedImage(for: request) != nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(await cache.cachedImage(for: request, caches: [.disk]) != nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) != nil)
    }

    @Test func storeCacheImageWhenMemoryCacheWriteDisabled() async {
        // WHEN
        var request = Test.request
        request.options.insert(.disableMemoryCacheWrites)
        cache.storeCachedImage(Test.container, for: request, caches: [.memory])

        // THEN
        #expect(await cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(await cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func storeCacheDataWhenNoDataCache() async {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // WHEN
        pipeline.cache.storeCachedData(Test.data, for: Test.request)

        // THEN just make sure it doesn't do anything weird
        #expect(await pipeline.cache.cachedData(for: Test.request) == nil)
    }

    @Test func getCachedDataWhenNoDataCache() async {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // THEN just make sure it doesn't do anything weird
        #expect(await pipeline.cache.cachedData(for: Test.request) == nil)
        pipeline.cache.removeCachedData(for: Test.request)
    }

    // MARK: Contains

    @Test func containsWhenStoredInMemoryCache() async {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])

        // WHEN/THEN
        #expect(await cache.containsCachedImage(for: Test.request))
        #expect(await cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(await cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(await !cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func containsWhenStoredInDiskCache() async {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // WHEN/THEN
        #expect(await cache.containsCachedImage(for: Test.request))
        #expect(await cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(await !cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(await cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func containsStoredInBoth() async {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.all])

        // WHEN/THEN
        #expect(await cache.containsCachedImage(for: Test.request))
        #expect(await cache.containsCachedImage(for: Test.request, caches: [.all]))
        #expect(await cache.containsCachedImage(for: Test.request, caches: [.memory]))
        #expect(await cache.containsCachedImage(for: Test.request, caches: [.disk]))
    }

    @Test func containsData() async {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])

        // WHEN/THEN
        #expect(await cache.containsData(for: Test.request))
    }

    @Test func containsDataWithNoDataCache() async {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCache = nil
        }

        // WHEN/THEN
        #expect(await !pipeline.cache.containsData(for: Test.request))
    }

    // MARK: Remove

    @Test func removeFromMemoryCache() async {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request)

        // WHEN
        cache.removeCachedImage(for: request)

        // THEN
        #expect(await cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)
    }

    @Test func removeFromDiskCache() async {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.disk])

        // WHEN
        cache.removeCachedImage(for: request, caches: [.disk])

        // THEN
        #expect(await cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func removeFromAllCaches() async {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // WHEN
        cache.removeCachedImage(for: request, caches: [.memory, .disk])

        // THEN
        #expect(await cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(await cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    // MARK: Remove All

    @Test func removeAll() async {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.memory, .disk])

        // WHEN
        cache.removeAll()

        // THEN
        #expect(await cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(await cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    @Test func removeAllWithAllStatic() async {
        // GIVEN
        let request = Test.request
        cache.storeCachedImage(Test.container, for: request, caches: [.all])

        // WHEN
        cache.removeAll()

        // THEN
        #expect(await cache.cachedImage(for: request) == nil)
        #expect(memoryCache[cache.makeImageCacheKey(for: request)] == nil)

        #expect(await cache.cachedImage(for: request, caches: [.disk]) == nil)
        #expect(await diskCache.cachedData(for: cache.makeDataCacheKey(for: request)) == nil)
    }

    // MARK: Keys

    @Test func makeImageCacheKeyUsesTheCustomKeyFromTheDelegate() {
        // GIVEN a delegate that maps every request to the same key
        let delegate = MockCustomCacheKeyDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = memoryCache
        }
        let other = ImageRequest(url: URL(string: "http://test.com/other.jpeg")!)

        // THEN both requests resolve to the same memory cache entry
        #expect(pipeline.cache.makeImageCacheKey(for: Test.request) == pipeline.cache.makeImageCacheKey(for: other))

        // ...and an image stored for one is returned for the other
        pipeline.cache[Test.request] = Test.container
        #expect(pipeline.cache[other] != nil)
    }

    @Test func makeImageCacheKeyFallsBackToTheDefaultKey() {
        // GIVEN requests with different URLs and no delegate customization
        let other = ImageRequest(url: URL(string: "http://test.com/other.jpeg")!)

        // THEN
        #expect(cache.makeImageCacheKey(for: Test.request) != cache.makeImageCacheKey(for: other))
    }

    // MARK: Decoding Cached Data

    @Test func cachedImageIsNilWhenNoDecoderIsRegistered() async {
        // GIVEN data stored on disk and a pipeline that can't decode it
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in nil }
        }
        pipeline.cache.storeCachedData(Test.data, for: Test.request)

        // THEN the data is there, but it can't be turned into an image
        #expect(await pipeline.cache.cachedData(for: Test.request) != nil)
        #expect(await pipeline.cache.cachedImage(for: Test.request, caches: [.disk]) == nil)
    }

    @Test func cachedImageIsNilWhenTheCachedDataIsCorrupted() async {
        // GIVEN
        cache.storeCachedData(Data("not-an-image".utf8), for: Test.request)

        // THEN
        #expect(await cache.cachedImage(for: Test.request, caches: [.disk]) == nil)
    }

    // MARK: - Image Orientation

#if canImport(UIKit)
    @Test func thatImageOrientationIsPreserved() async throws {
        // GIVEN opaque jpeg with orientation
        let image = Test.image(named: "right-orientation", extension: "jpeg")
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.isOpaque)
        #expect(image.imageOrientation == .right)

        // WHEN
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: image), for: Test.request, caches: [.disk])
        let cached = try #require(await pipeline.cache.cachedImage(for: Test.request, caches: [.disk])?.image)

        // THEN orientation is preserved
        let cachedCGImage = try #require(cached.cgImage)
        #expect(cachedCGImage.isOpaque)
        #expect(cached.imageOrientation == .right)
    }

    @Test func thatImageOrientationIsPreservedForProcessedImages() async throws {
        // GIVEN opaque jpeg with orientation
        let image = Test.image(named: "right-orientation", extension: "jpeg")
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.isOpaque)
        #expect(image.imageOrientation == .right)

        let resized = try #require(ImageProcessors.Resize(width: 100).process(image))

        // WHEN
        let pipeline = ImagePipeline(configuration: .withDataCache)
        pipeline.cache.storeCachedImage(ImageContainer(image: resized), for: Test.request, caches: [.disk])
        let cached = try #require(await pipeline.cache.cachedImage(for: Test.request, caches: [.disk])?.image)

        // THEN orientation is preserved
        let cachedCGImage = try #require(cached.cgImage)
        #expect(cachedCGImage.isOpaque)
        #expect(cached.imageOrientation == .right)
    }
#endif
}

private final class MockCustomCacheKeyDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        "custom-cache-key"
    }
}
