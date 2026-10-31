// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

/// How the pipeline consults the caching hooks of ``ImagePipeline/Delegate-swift.protocol``
/// while it loads images.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDelegateCachingTests {
    private let dataLoader: MockDataLoader
    private let imageCache: MockImageCache
    private let dataCache: MockDataCache
    private let delegate: MockCachingDelegate

    init() {
        self.dataLoader = MockDataLoader()
        self.imageCache = MockImageCache()
        self.dataCache = MockDataCache()
        self.delegate = MockCachingDelegate()
    }

    private func makePipeline(_ policy: ImagePipeline.DataCachePolicy = .storeOriginalData, _ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
            $0.dataCachePolicy = policy
            configure(&$0)
        }
    }

    // MARK: willCache

    /// Documented: `image` is non-nil only when the pipeline stores an
    /// encoded image. The original data is stored for a request that has
    /// nothing to do with the processing.
    @Test func willCacheDistinguishesOriginalDataFromEncodedImages() async throws {
        // GIVEN
        let encoded = Test.data(name: "fixture-tiny", extension: "jpeg")
        let pipeline = makePipeline(.storeAll) {
            $0.makeImageEncoder = { _ in MockImageEncoder(result: encoded) }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN the original data is offered first: it's stored before the
        // processing can even start
        let calls = delegate.willCacheCalls
        try #require(calls.count == 2)

        #expect(calls[0].data == Test.data)
        #expect(calls[0].image == nil)
        #expect(calls[0].request.processors.isEmpty)
        #expect(calls[0].request.url == Test.url)

        #expect(calls[1].data == encoded)
        #expect(calls[1].image?.image.nk_test_processorIDs == ["p1"])
        #expect(calls[1].request.processors.count == 1)

        #expect(dataCache.store == [Test.url.absoluteString: Test.data, Test.url.absoluteString + "p1": encoded])
    }

    @Test func willCacheReceivesTheOriginalRequestWithoutTheThumbnail() async throws {
        // GIVEN
        let pipeline = makePipeline(.storeOriginalData)
        let request = ImageRequest(url: Test.url).with {
            $0.thumbnail = .init(maxPixelSize: 100)
            $0.userInfo["label"] = "feed"
        }

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN the original data is stored for the full image, but the rest of
        // the request is intact, so the delegate can still tell them apart
        let call = try #require(delegate.willCacheCalls.first)
        #expect(delegate.willCacheCalls.count == 1)
        #expect(call.request.thumbnail == nil)
        #expect(call.request.userInfo["label"] as? String == "feed")
        #expect(dataCache.store.keys.sorted() == [Test.url.absoluteString])
    }

    @Test func willCacheCanReplaceTheEncodedImage() async throws {
        // GIVEN a delegate that replaces what the pipeline stores, e.g. to
        // encrypt it
        delegate.willCacheTransform = { Data("sealed".utf8) + $0 }
        let pipeline = makePipeline(.automatic) {
            $0.makeImageEncoder = { _ in MockImageEncoder(result: Data("encoded".utf8)) }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(dataCache.store == [Test.url.absoluteString + "p1": Data("sealedencoded".utf8)])
    }

    // MARK: willCache With a Completion Closure

    private func makePipeline(delegate: any ImagePipeline.Delegate, _ policy: ImagePipeline.DataCachePolicy = .storeOriginalData, _ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = policy
            configure(&$0)
        }
    }

    /// The method compiles after an upgrade with no diagnostic, so if the
    /// pipeline stopped calling it, private images would end up on the disk.
    @Test func nuke13WillCacheKeepsDataOffTheDisk() async throws {
        // GIVEN a delegate written for Nuke 13
        let delegate = Nuke13CachingDelegate { _, completion in completion(nil) }
        let pipeline = makePipeline(delegate: delegate)

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(delegate.callCount == 1)
        #expect(dataCache.store.isEmpty)
    }

    @Test func nuke13WillCacheDeclaredInAnExtensionKeepsDataOffTheDisk() async throws {
        // GIVEN
        let delegate = Nuke13ExtensionDelegate()
        let pipeline = makePipeline(delegate: delegate)

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(delegate.isCalled.withLock { $0 })
        #expect(dataCache.store.isEmpty)
    }

    @Test func nuke13WillCacheCanReplaceTheData() async throws {
        // GIVEN
        let delegate = Nuke13CachingDelegate { data, completion in completion(Data("sealed".utf8) + data) }
        let pipeline = makePipeline(delegate: delegate)

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(dataCache.store == [Test.url.absoluteString: Data("sealed".utf8) + Test.data])
    }

    @Test func nuke13WillCacheCanPreventStoringTheEncodedImage() async throws {
        // GIVEN
        let delegate = Nuke13CachingDelegate { _, completion in completion(nil) }
        let pipeline = makePipeline(delegate: delegate, .automatic) {
            $0.makeImageEncoder = { _ in MockImageEncoder(result: Data("encoded".utf8)) }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(delegate.callCount == 1)
        #expect(dataCache.store.isEmpty)
    }

    /// The reason to take a closure: encrypting the data on a queue of its
    /// own, for example. The closure must not assume it's called on the actor.
    @Test func nuke13WillCacheCanCompleteOnAnotherThread() async throws {
        // GIVEN
        let delegate = Nuke13CachingDelegate { data, completion in
            nonisolated(unsafe) let completion = completion
            DispatchQueue.global().async { completion(Data("sealed".utf8) + data) }
        }
        let pipeline = makePipeline(delegate: delegate)

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(dataCache.store == [Test.url.absoluteString: Data("sealed".utf8) + Test.data])
    }

    /// Nuke 13 didn't wait for the closure, so leaving it uncalled kept the
    /// data off the disk, and the image still loaded. The pipeline now waits,
    /// and must not wait forever.
    @Test func nuke13WillCacheThatNeverCompletesDoesNotBlockTheLoad() async throws {
        // GIVEN
        let delegate = Nuke13CachingDelegate { _, _ in }
        let pipeline = makePipeline(delegate: delegate)

        // WHEN
        let image = try await pipeline.image(for: Test.request)

        // THEN
        #expect(image.size == Test.image.size)
        #expect(delegate.callCount == 1)
        #expect(dataCache.store.isEmpty)
    }

    /// Nuke 13 stored the data on each call, so it survived the mistake.
    @Test func nuke13WillCacheThatCompletesTwiceUsesTheFirstResult() async throws {
        // GIVEN
        let delegate = Nuke13CachingDelegate { data, completion in
            completion(data)
            completion(nil)
        }
        let pipeline = makePipeline(delegate: delegate)

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(dataCache.store == [Test.url.absoluteString: Test.data])
    }

    @Test func delegateWithoutWillCacheStoresTheData() async throws {
        // GIVEN
        final class Delegate: ImagePipeline.Delegate {}
        let pipeline = makePipeline(delegate: Delegate())

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(dataCache.store == [Test.url.absoluteString: Test.data])
    }

    @Test func asyncWillCacheWinsOverTheNuke13Method() async throws {
        // GIVEN a delegate that adopted the new method and left the old one
        let delegate = Nuke13CachingDelegate { _, completion in completion(nil) }
        let migrated = MigratedCachingDelegate(nuke13: delegate)
        let pipeline = makePipeline(delegate: migrated)

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(delegate.callCount == 0)
        #expect(dataCache.store == [Test.url.absoluteString: Data("async".utf8)])
    }

    /// Documented: "This method is called only if the request parameters and
    /// data caching policy of the pipeline already allow caching."
    @Test func willCacheIsNotCalledForOriginalDataWhenTheRequestDisablesDiskWrites() async throws {
        // GIVEN
        let pipeline = makePipeline(.storeOriginalData)
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN
        #expect(delegate.willCacheCalls.isEmpty)
        #expect(dataCache.writeCount == 0)
    }

    @Test func willCacheIsNotCalledWhenThePolicyDoesNotStoreTheOriginalData() async throws {
        // GIVEN a policy that stores only encoded images, which a data task
        // never produces
        let pipeline = makePipeline(.storeEncodedImages)

        // WHEN
        _ = try await pipeline.data(for: Test.request)

        // THEN
        #expect(delegate.willCacheCalls.isEmpty)
        #expect(dataCache.writeCount == 0)
    }

    // MARK: dataCache(for:)

    @Test func delegateReturningNoDataCacheSkipsEncodingAndStoring() async throws {
        // GIVEN a policy that stores everything, but no disk cache for the request
        let encoder = MockImageEncoder(result: Test.data)
        let pipeline = makePipeline(.storeAll) {
            $0.makeImageEncoder = { _ in encoder }
        }
        delegate.dataCache = { _ in nil }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN nothing is encoded or offered to the delegate
        #expect(encoder.encodeCount == 0)
        #expect(delegate.willCacheCalls.isEmpty)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.readCount == 0)
    }

    @Test func pipelineStoresAndReadsTheDataCacheProvidedByTheDelegate() async throws {
        // GIVEN a delegate that stores the avatars in their own disk cache
        let avatarCache = MockDataCache()
        delegate.dataCache = { $0.userInfo["kind"] as? String == "avatar" ? avatarCache : dataCache }
        let pipeline = makePipeline(.storeOriginalData) {
            $0.imageCache = nil
        }
        let avatar = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]).with {
            $0.userInfo["kind"] = "avatar"
        }

        // WHEN
        _ = try await pipeline.image(for: avatar)

        // THEN
        #expect(avatarCache.store.keys.sorted() == [Test.url.absoluteString])
        #expect(dataCache.store.isEmpty)

        // WHEN the image is requested again
        let response = try await pipeline.imageTask(with: avatar).response

        // THEN it comes from the delegate's cache
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(dataCache.readCount == 0)
    }

    // MARK: imageCache(for:)

    @Test func pipelineStoresAndReadsTheImageCacheProvidedByTheDelegate() async throws {
        // GIVEN
        let avatarCache = MockImageCache()
        delegate.imageCache = { $0.userInfo["kind"] as? String == "avatar" ? avatarCache : imageCache }
        let pipeline = makePipeline()
        let avatar = ImageRequest(url: Test.url).with { $0.userInfo["kind"] = "avatar" }

        // WHEN
        _ = try await pipeline.image(for: avatar)

        // THEN
        #expect(avatarCache.images.count == 1)
        #expect(imageCache.images.isEmpty)

        // WHEN the image is requested again
        let response = try await pipeline.imageTask(with: avatar).response

        // THEN it comes from the delegate's cache
        #expect(response.cacheType == .memory)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(imageCache.readCount == 0)
    }

    @Test func delegateReturningNoImageCacheBypassesTheConfiguredOne() async throws {
        // GIVEN an image in the configured memory cache
        imageCache[ImageCacheKey(request: Test.request)] = Test.container
        imageCache.resetCounters()
        delegate.imageCache = { _ in nil }
        let pipeline = makePipeline {
            $0.dataCache = nil
        }

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN the image is loaded, and the configured cache is never touched
        #expect(response.cacheType == nil)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(imageCache.readCount == 0)
        #expect(imageCache.writeCount == 0)
    }

    // MARK: cacheKey(for:)

    @Test func requestsWithTheSameDelegateKeyShareTheMemoryCacheEntry() async throws {
        // GIVEN two URLs for the same image
        delegate.cacheKey = { $0.userInfo["id"] as? String }
        let pipeline = makePipeline()
        let small = ImageRequest(url: URL(string: "http://test.com/small.jpeg")).with { $0.userInfo["id"] = "image-1" }
        let large = ImageRequest(url: URL(string: "http://test.com/large.jpeg")).with { $0.userInfo["id"] = "image-1" }

        // WHEN
        _ = try await pipeline.image(for: large)
        let response = try await pipeline.imageTask(with: small).response

        // THEN
        #expect(response.cacheType == .memory)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(imageCache.images.count == 1)
        #expect(dataCache.store.keys.sorted() == ["image-1"])
    }

    // MARK: imageDecoder(for:) and imageEncoder(for:)

    @Test func cachedDataWithNoDecoderFallsBackToLoading() async throws {
        // GIVEN data in the disk cache the delegate has no decoder for
        dataCache.store[Test.url.absoluteString] = Test.data
        let contexts = LockedArray<ImageDecodingContext>()
        delegate.decoder = { context in
            contexts.append(context)
            return context.cacheType == .disk ? nil : ImageDecoders.Default()
        }
        let pipeline = makePipeline()

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(response.cacheType == nil)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(contexts.values.map(\.cacheType) == [.disk, nil])
    }

    @Test func encoderForProcessedImagesReceivesTheURLResponse() async throws {
        // GIVEN
        let encoder = MockImageEncoder(result: Test.data)
        delegate.encoder = { _ in encoder }
        let pipeline = makePipeline(.automatic)
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        let context = try #require(encoder.contexts.first)
        #expect(encoder.contexts.count == 1)
        #expect(context.urlResponse?.url == Test.url)
        #expect(context.request.processors.count == 1)
        #expect(context.image.nk_test_processorIDs == ["p1"])
    }
}

// MARK: - Helpers

/// A delegate written for Nuke 13, when `willCache` took a completion closure.
private final class Nuke13CachingDelegate: ImagePipeline.Delegate, Sendable {
    typealias Handler = @Sendable (Data, @escaping (Data?) -> Void) -> Void

    private let handler: Handler
    private let _callCount = OSAllocatedUnfairLock(initialState: 0)

    var callCount: Int { _callCount.withLock { $0 } }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        _callCount.withLock { $0 += 1 }
        handler(data, completion)
    }
}

/// The way the migration guide says to declare a conformance.
private final class Nuke13ExtensionDelegate: Sendable {
    let isCalled = OSAllocatedUnfairLock(initialState: false)
}

extension Nuke13ExtensionDelegate: ImagePipeline.Delegate {
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        isCalled.withLock { $0 = true }
        completion(nil)
    }
}

/// Implements both forms of `willCache`.
private final class MigratedCachingDelegate: ImagePipeline.Delegate, Sendable {
    private let nuke13: Nuke13CachingDelegate

    init(nuke13: Nuke13CachingDelegate) {
        self.nuke13 = nuke13
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        Data("async".utf8)
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        nuke13.willCache(data: data, image: image, for: request, pipeline: pipeline, completion: completion)
    }
}
