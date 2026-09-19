// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// The synchronous ``ImagePipeline/Cache-swift.struct`` API: which layers each
/// call touches, how it honors the request options, and how it goes through
/// the delegate for the caches, the encoder, and the decoder.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineCacheAPIContractTests {
    private let memoryCache: MockImageCache
    private let diskCache: MockDataCache
    private let delegate: CachingDelegate
    private let pipeline: ImagePipeline
    private var cache: ImagePipeline.Cache { pipeline.cache }

    init() {
        let memoryCache = MockImageCache()
        let diskCache = MockDataCache()
        let delegate = CachingDelegate()
        self.memoryCache = memoryCache
        self.diskCache = diskCache
        self.delegate = delegate
        self.pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = memoryCache
            $0.dataCache = diskCache
        }
    }

    // MARK: Layer Selection

    @Test func emptyCachesOptionTouchesNoLayer() {
        // GIVEN an image stored in both layers
        cache.storeCachedImage(Test.container, for: Test.request)
        memoryCache.resetCounters()
        diskCache.resetCounters()
        let other = ImageRequest(url: URL(string: "http://test.com/other.jpeg"))

        // WHEN/THEN every call that takes an empty set of layers is a no-op
        #expect(cache.cachedImage(for: Test.request, caches: []) == nil)
        #expect(!cache.containsCachedImage(for: Test.request, caches: []))
        cache.storeCachedImage(Test.container, for: other, caches: [])
        cache.removeCachedImage(for: Test.request, caches: [])
        cache.removeAll(caches: [])

        #expect(memoryCache.readCount == 0)
        #expect(memoryCache.writeCount == 0)
        #expect(diskCache.readCount == 0)
        #expect(diskCache.writeCount == 0)
        #expect(memoryCache.images.count == 1)
        #expect(diskCache.store.count == 1)
    }

    @Test func cachedImageReturnsTheMemoryCachedInstanceWithoutReadingTheDisk() throws {
        // GIVEN different images in the two layers
        let memoryImage = ImageContainer(image: Test.image)
        cache.storeCachedImage(memoryImage, for: Test.request, caches: [.memory])
        cache.storeCachedData(Test.data, for: Test.request)
        diskCache.resetCounters()

        // WHEN
        let image = try #require(cache.cachedImage(for: Test.request))

        // THEN the memory cache wins, and the disk isn't read at all
        #expect(image.image === memoryImage.image)
        #expect(diskCache.readCount == 0)
    }

    @Test func cachedImageFallsBackToTheDiskWhenMemoryReadsAreDisabled() throws {
        // GIVEN different images in the two layers
        let memoryImage = ImageContainer(image: Test.image)
        cache.storeCachedImage(memoryImage, for: Test.request, caches: [.memory])
        cache.storeCachedData(Test.data, for: Test.request)

        // WHEN
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheReads])
        let image = try #require(cache.cachedImage(for: request))

        // THEN the image is decoded from the disk
        #expect(image.image !== memoryImage.image)
        #expect(image.image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(diskCache.readCount == 1)
    }

    @Test func subscriptDoesNotTouchTheDiskCache() {
        // GIVEN
        cache.storeCachedData(Test.data, for: Test.request)
        diskCache.resetCounters()

        // WHEN the image is written and then removed with the subscript
        cache[Test.request] = Test.container
        cache[Test.request] = nil

        // THEN only the memory cache is affected
        #expect(diskCache.readCount == 0)
        #expect(diskCache.writeCount == 0)
        #expect(cache.cachedData(for: Test.request) == Test.data)
    }

    @Test func removeAllRespectsTheSelectedLayers() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        cache.removeAll(caches: [.memory])

        // THEN
        #expect(cache.cachedImage(for: Test.request, caches: [.memory]) == nil)
        #expect(cache.containsData(for: Test.request))

        // WHEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])
        cache.removeAll(caches: [.disk])

        // THEN
        #expect(cache.cachedImage(for: Test.request, caches: [.memory]) != nil)
        #expect(!cache.containsData(for: Test.request))
    }

    // MARK: Request Options

    @Test func storeCachedImageHonorsTheWriteOptionsOfEachLayer() {
        // WHEN memory writes are disabled
        let noMemoryWrites = ImageRequest(url: Test.url, options: [.disableMemoryCacheWrites])
        cache.storeCachedImage(Test.container, for: noMemoryWrites)

        // THEN the image still reaches the disk
        #expect(memoryCache.images.isEmpty)
        #expect(diskCache.store.count == 1)

        // WHEN disk writes are disabled
        cache.removeAll()
        let noDiskWrites = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])
        cache.storeCachedImage(Test.container, for: noDiskWrites)

        // THEN the image still reaches the memory
        #expect(memoryCache.images.count == 1)
        #expect(diskCache.store.isEmpty)
    }

    @Test func containsCachedImageHonorsMemoryReadsOption() {
        // GIVEN an image stored only in memory
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])

        // WHEN/THEN it's invisible to a request that disables memory reads
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheReads])
        #expect(!cache.containsCachedImage(for: request))
        #expect(!cache.containsCachedImage(for: request, caches: [.memory]))
    }

    /// Removal is neither a read nor a write: a request that disables every
    /// layer still removes what an equivalent request stored.
    @Test func removalIsNotGatedByTheCacheOptions() {
        // GIVEN
        cache.storeCachedImage(Test.container, for: Test.request)
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCache, .disableDiskCache])

        // WHEN
        cache.removeCachedImage(for: request)

        // THEN
        #expect(memoryCache.images.isEmpty)
        #expect(diskCache.store.isEmpty)

        // WHEN the data is removed on its own
        cache.storeCachedData(Test.data, for: Test.request)
        cache.removeCachedData(for: request)

        // THEN
        #expect(diskCache.store.isEmpty)
    }

    // MARK: Encoding and Decoding

    @Test func storeCachedImageEncodesWithTheDelegateEncoder() throws {
        // GIVEN
        let encoded = Data("encoded".utf8)
        let encoder = ContextRecordingEncoder(result: encoded)
        delegate.encoder = { _ in encoder }
        let container = Test.container
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        cache.storeCachedImage(container, for: request, caches: [.disk])

        // THEN the encoder output is stored under the request's key
        #expect(diskCache.store == [Test.url.absoluteString + "p1": encoded])

        // THEN the context describes the image and the request, but there is
        // no URL response to pass outside of the pipeline
        let context = try #require(encoder.contexts.first)
        #expect(encoder.contexts.count == 1)
        #expect(context.image === container.image)
        #expect(context.request.url == Test.url)
        #expect(context.request.processors.count == 1)
        #expect(context.urlResponse == nil)
    }

    @Test func storeCachedImageSkipsTheDiskWhenTheImageCantBeEncoded() {
        // GIVEN an encoder that fails
        delegate.encoder = { _ in ContextRecordingEncoder(result: nil) }

        // WHEN
        cache.storeCachedImage(Test.container, for: Test.request)

        // THEN the memory cache still gets the image
        #expect(memoryCache.images.count == 1)
        #expect(diskCache.writeCount == 0)
    }

    @Test func storeCachedImageDoesNotEncodeWhenTheDiskIsNotSelected() {
        // GIVEN
        let encoder = ContextRecordingEncoder(result: Test.data)
        delegate.encoder = { _ in encoder }

        // WHEN
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])

        // THEN
        #expect(encoder.contexts.isEmpty)
    }

    @Test func cachedImageDecodesWithTheDelegateDecoder() throws {
        // GIVEN a pipeline that doesn't parse animated images
        let recorder = LockedArray<ImageDecodingContext>()
        delegate.decoder = { context in
            recorder.append(context)
            return ImageDecoders.Default()
        }
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.imageCache = nil
            $0.dataCache = diskCache
            $0.isAnimatedImageParsingEnabled = false
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        pipeline.cache.storeCachedData(Test.data, for: request)

        // WHEN
        let image = try #require(pipeline.cache.cachedImage(for: request, caches: [.disk]))

        // THEN the decoder is asked for a completed disk cache context
        #expect(image.image.sizeInPixels == CGSize(width: 640, height: 480))
        let context = try #require(recorder.values.first)
        #expect(recorder.values.count == 1)
        #expect(context.cacheType == .disk)
        #expect(context.isCompleted)
        #expect(context.data == Test.data)
        #expect(context.urlResponse == nil)
        #expect(context.request.processors.count == 1)
        #expect(!context.isAnimatedImageParsingEnabled)
    }

    // MARK: Delegate Caches

    @Test func delegateReturningNoImageCacheDisablesTheMemoryLayer() {
        // GIVEN an image in the configured memory cache
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])
        memoryCache.resetCounters()

        // WHEN the delegate stops providing a memory cache
        delegate.imageCache = { _ in nil }

        // THEN the configured cache is never touched
        #expect(cache[Test.request] == nil)
        #expect(cache.cachedImage(for: Test.request, caches: [.memory]) == nil)
        #expect(!cache.containsCachedImage(for: Test.request, caches: [.memory]))
        cache[Test.request] = Test.container
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.memory])
        cache.removeCachedImage(for: Test.request, caches: [.memory])
        #expect(memoryCache.readCount == 0)
        #expect(memoryCache.writeCount == 0)
        #expect(memoryCache.images.count == 1)
    }

    @Test func delegateReturningNoDataCacheDisablesTheDiskLayer() {
        // GIVEN data in the configured disk cache
        cache.storeCachedData(Test.data, for: Test.request)
        diskCache.resetCounters()

        // WHEN the delegate stops providing a disk cache
        delegate.dataCache = { _ in nil }

        // THEN the configured cache is never touched
        #expect(cache.cachedData(for: Test.request) == nil)
        #expect(!cache.containsData(for: Test.request))
        #expect(!cache.containsCachedImage(for: Test.request, caches: [.disk]))
        #expect(cache.cachedImage(for: Test.request, caches: [.disk]) == nil)
        cache.storeCachedData(Data("new".utf8), for: Test.request)
        cache.storeCachedImage(Test.container, for: Test.request, caches: [.disk])
        cache.removeCachedData(for: Test.request)
        cache.removeCachedImage(for: Test.request, caches: [.disk])
        #expect(diskCache.readCount == 0)
        #expect(diskCache.writeCount == 0)
        #expect(diskCache.store == [Test.url.absoluteString: Test.data])
    }

    @Test func delegateCanRouteRequestsToDifferentCaches() {
        // GIVEN a delegate that routes the avatars to their own caches
        let avatarMemoryCache = MockImageCache()
        let avatarDiskCache = MockDataCache()
        delegate.imageCache = { $0.userInfo["kind"] as? String == "avatar" ? avatarMemoryCache : memoryCache }
        delegate.dataCache = { $0.userInfo["kind"] as? String == "avatar" ? avatarDiskCache : diskCache }
        let avatar = ImageRequest(url: Test.url).with { $0.userInfo["kind"] = "avatar" }

        // WHEN
        cache.storeCachedImage(Test.container, for: avatar)

        // THEN
        #expect(avatarMemoryCache.images.count == 1)
        #expect(avatarDiskCache.store.count == 1)
        #expect(memoryCache.images.isEmpty)
        #expect(diskCache.store.isEmpty)
        #expect(cache.cachedImage(for: avatar, caches: [.memory]) != nil)
        #expect(cache.containsData(for: avatar))

        // THEN the same key in the default caches is still empty
        #expect(cache.cachedImage(for: Test.request) == nil)
    }

    /// Documented: ``ImagePipeline/Cache-swift.struct/removeAll(caches:)``
    /// clears only the caches from the configuration.
    @Test func removeAllDoesNotClearTheCachesProvidedByTheDelegate() {
        // GIVEN
        let avatarMemoryCache = MockImageCache()
        let avatarDiskCache = MockDataCache()
        delegate.imageCache = { $0.userInfo["kind"] as? String == "avatar" ? avatarMemoryCache : memoryCache }
        delegate.dataCache = { $0.userInfo["kind"] as? String == "avatar" ? avatarDiskCache : diskCache }
        let avatar = ImageRequest(url: Test.url).with { $0.userInfo["kind"] = "avatar" }
        cache.storeCachedImage(Test.container, for: avatar)
        cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        cache.removeAll()

        // THEN
        #expect(memoryCache.images.isEmpty)
        #expect(diskCache.store.isEmpty)
        #expect(avatarMemoryCache.images.count == 1)
        #expect(avatarDiskCache.store.count == 1)
    }
}

// MARK: - Helpers

private final class ContextRecordingEncoder: ImageEncoding, @unchecked Sendable {
    let result: Data?
    private let recorder = LockedArray<ImageEncodingContext>()
    var contexts: [ImageEncodingContext] { recorder.values }

    init(result: Data?) {
        self.result = result
    }

    func encode(_ image: PlatformImage) -> Data? {
        result
    }

    func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? {
        recorder.append(context)
        return result
    }
}
