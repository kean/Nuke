// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

/// The formats `NukeUI` plays, each with a fixture.
enum AnimatedFixture: String, CaseIterable, CustomTestStringConvertible {
    case gif, apng, webp, heics, avif

    var testDescription: String { rawValue }

    /// `nil` if Image I/O on this platform can't write the fixture.
    var data: Data? {
        switch self {
        case .gif: Test.animatedGIF()
        case .apng: Test.animatedPNG()
        case .webp: Test.data(name: "animated", extension: "webp")
        case .heics: Test.animatedHEICS()
        case .avif: Test.data(name: "animated", extension: "avif")
        }
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineAnimatedDataCacheTests {
    private static let encodingPolicies: [ImagePipeline.DataCachePolicy] = [.automatic, .storeEncodedImages, .storeAll]

    private let dataCache = MockDataCache()

    private func makePipeline(
        data: Data,
        policy: ImagePipeline.DataCachePolicy,
        dataCache: (any DataCaching)? = nil,
        delegate: (any ImagePipeline.Delegate)? = nil,
        configure: (inout ImagePipeline.Configuration) -> Void = { _ in }
    ) -> ImagePipeline {
        let dataLoader = MockDataLoader()
        let response = URLResponse(url: Test.url, mimeType: nil, expectedContentLength: data.count, textEncodingName: nil)
        dataLoader.results[Test.url] = .success((data, response))
        return ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache ?? self.dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = policy
            configure(&$0)
        }
    }

    /// A pipeline with nothing in memory and no network, as after a relaunch
    /// with the connection down: what it returns came out of the disk cache.
    private func makeRelaunchedPipeline(dataCache: (any DataCaching)? = nil) -> (ImagePipeline, MockDataLoader) {
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache ?? self.dataCache
            $0.imageCache = nil
        }
        return (pipeline, dataLoader)
    }

    // MARK: Animations

    /// The test of record, on a real `DataCache`, written to disk and read by a
    /// new instance.
    @Test(arguments: AnimatedFixture.allCases)
    func storeEncodedImagesKeepsTheAnimationAcrossARelaunch(fixture: AnimatedFixture) async throws {
        guard let data = fixture.data else {
            return // Image I/O on this platform can't write the fixture
        }
        // GIVEN
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let dataCache = try DataCache(path: path)
        let pipeline = makePipeline(data: data, policy: .storeEncodedImages, dataCache: dataCache)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        await dataCache.flush()

        // THEN the disk cache has the animation, byte for byte
        let frameCount = try #require(response.container.animation?.frameCount)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == data)

        // THEN it's still an animation when it comes back
        let (relaunched, dataLoader) = makeRelaunchedPipeline(dataCache: try DataCache(path: path))
        let cached = try await relaunched.imageTask(with: Test.request).response
        #expect(cached.cacheType == .disk)
        #expect(cached.container.animation?.frameCount == frameCount)
        #expect(cached.container.data == data)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test(arguments: AnimatedFixture.allCases)
    func storeCachedImageKeepsTheAnimation(fixture: AnimatedFixture) async throws {
        guard let data = fixture.data else { return }

        // GIVEN
        let pipeline = makePipeline(data: data, policy: .storeOriginalData)
        let container = try ImageDecoders.Default().decode(data)
        let frameCount = try #require(container.animation?.frameCount)

        // WHEN it's stored with the public cache API
        pipeline.cache.storeCachedImage(container, for: Test.request, caches: [.disk])

        // THEN
        #expect(dataCache.store[Test.url.absoluteString] == data)
        let cached = try #require(pipeline.cache.cachedImage(for: Test.request, caches: [.disk]))
        #expect(cached.animation?.frameCount == frameCount)
    }

    /// With parsing off, `animation` is `nil` but the data is there for a
    /// renderer of the app's own, which needs it after a relaunch too.
    @Test(arguments: AnimatedFixture.allCases)
    func storeEncodedImagesKeepsTheDataWithParsingDisabled(fixture: AnimatedFixture) async throws {
        guard let data = fixture.data else { return }

        // GIVEN
        let pipeline = makePipeline(data: data, policy: .storeEncodedImages) {
            $0.isAnimatedImageParsingEnabled = false
        }

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(response.container.animation == nil)
        #expect(response.container.data == data)
        #expect(dataCache.store[Test.url.absoluteString] == data)
    }

    /// The other policies never encoded an image with no processors, so they
    /// have nothing to pass through.
    @Test(arguments: AnimatedFixture.allCases, [ImagePipeline.DataCachePolicy.automatic, .storeOriginalData, .storeAll])
    func otherPoliciesStoreTheOriginalDataOnce(fixture: AnimatedFixture, policy: ImagePipeline.DataCachePolicy) async throws {
        guard let data = fixture.data else { return }

        // GIVEN
        let encoder = MockImageEncoder(result: Test.data)
        let pipeline = makePipeline(data: data, policy: policy) {
            $0.makeImageEncoder = { _ in encoder }
        }

        // WHEN
        _ = try await pipeline.imageTask(with: Test.request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(encoder.contexts.isEmpty)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store == [Test.url.absoluteString: data])
    }

    // MARK: Delegate

    @Test(arguments: AnimatedFixture.allCases)
    func willCacheSeesTheOriginalData(fixture: AnimatedFixture) async throws {
        guard let data = fixture.data else { return }

        // GIVEN a delegate that replaces what's about to be stored
        let delegate = MockCachingDelegate()
        let replacement = Test.data
        delegate.willCacheTransform = { _ in replacement }
        let pipeline = makePipeline(data: data, policy: .storeEncodedImages, delegate: delegate)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN it's handed the animation and the container it came from
        let call = try #require(delegate.willCacheCalls.first)
        #expect(delegate.willCacheCalls.count == 1)
        #expect(call.data == data)
        #expect(call.image?.animation != nil)

        // THEN what it returned is stored, and the response keeps the animation
        #expect(dataCache.store == [Test.url.absoluteString: replacement])
        #expect(response.container.data == data)
    }

    @Test func willCacheCanRefuseAnAnimation() async throws {
        // GIVEN
        let data = try #require(AnimatedFixture.webp.data)
        let delegate = MockCachingDelegate()
        delegate.willCacheTransform = { _ in nil }
        let pipeline = makePipeline(data: data, policy: .storeEncodedImages, delegate: delegate)

        // WHEN
        _ = try await pipeline.imageTask(with: Test.request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(delegate.willCacheCalls.count == 1)
        #expect(dataCache.store.isEmpty)
    }

    // MARK: Stills

    /// A processor drops the animation, so the stored entry is the processed
    /// still. The bytes of the animation describe a different image.
    @Test(arguments: AnimatedFixture.allCases, encodingPolicies)
    func processedAnimationIsStoredAsAStill(fixture: AnimatedFixture, policy: ImagePipeline.DataCachePolicy) async throws {
        guard let data = fixture.data else { return }

        // GIVEN
        let pipeline = makePipeline(data: data, policy: policy)
        let request = ImageRequest(url: Test.url, processors: [.resize(size: CGSize(width: 4, height: 4), unit: .pixels)])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(response.container.animation == nil)
        #expect(response.container.data == nil)
        let key = pipeline.cache.makeDataCacheKey(for: request)
        let stored = try #require(dataCache.store[key])
        #expect(stored != data)
        #expect(AnimatedImageSource(data: stored) == nil)

        // THEN it comes back as the same still
        let (relaunched, _) = makeRelaunchedPipeline()
        let cached = try await relaunched.imageTask(with: request).response
        #expect(cached.cacheType == .disk)
        #expect(cached.container.animation == nil)
        #expect(cached.image.sizeInPixels == response.image.sizeInPixels)
    }

    /// Nothing but a processor that says so: one that implements
    /// `process(_:context:)` and keeps both has an animation to store.
    @Test func processorThatKeepsTheAnimationHasItStored() async throws {
        // GIVEN
        let data = try #require(AnimatedFixture.webp.data)
        let pipeline = makePipeline(data: data, policy: .automatic)
        let request = ImageRequest(url: Test.url, processors: [AnimationKeepingProcessor()])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(response.container.animation != nil)
        #expect(dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] == data)
    }

    /// A thumbnail is a still of its own size. Storing the original data under
    /// its key would hand a thumbnail request the full-size image.
    @Test(arguments: AnimatedFixture.allCases, encodingPolicies)
    func thumbnailOfAnimationIsStoredAsAStill(fixture: AnimatedFixture, policy: ImagePipeline.DataCachePolicy) async throws {
        guard let data = fixture.data else { return }

        // GIVEN
        let pipeline = makePipeline(data: data, policy: policy)
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 4)

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(response.container.animation == nil)
        #expect(response.container.data == nil)
        let stored = try #require(dataCache.store[pipeline.cache.makeDataCacheKey(for: request)])
        #expect(stored != data)
        #expect(AnimatedImageSource(data: stored) == nil)
        #expect(try ImageDecoders.Default().decode(stored).image.sizeInPixels == response.image.sizeInPixels)

        // THEN the original is stored only where the policy asks for it
        #expect((dataCache.store[Test.url.absoluteString] == data) == (policy != .storeEncodedImages))
    }

    @Test(arguments: [
        Still(name: "fixture", extension: "jpeg"),
        Still(name: "swift", extension: "png"),
        Still(name: "baseline", extension: "webp"),
        Still(name: "img_751", extension: "heic")
    ])
    func stillImagesAreReencoded(still: Still) async throws {
        // GIVEN
        let data = Test.data(name: still.name, extension: still.extension)
        let pipeline = makePipeline(data: data, policy: .storeEncodedImages)

        // WHEN
        _ = try await pipeline.imageTask(with: Test.request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN it went through the encoder, as the policy asks
        let stored = try #require(dataCache.store[Test.url.absoluteString])
        #expect(stored != data)
        #expect([AssetType.jpeg, .png].contains(try #require(AssetType(stored))))
    }

    struct Still: CustomTestStringConvertible, Sendable {
        let name: String
        let `extension`: String

        var testDescription: String { "\(name).\(`extension`)" }
    }

    private struct AnimationKeepingProcessor: ImageProcessing {
        let identifier = "com.github.kean/nuke/tests/animation-keeping"

        func process(_ image: PlatformImage) -> PlatformImage? { image }

        func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
            container
        }
    }
}
