// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Covers `TaskLoadImage`: the cache lookups it performs before loading an
/// image, what it does when the cached data can't be used, how it applies the
/// processors, and what it stores once the image is ready.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineLoadImageTaskTests {
    let dataLoader: MockDataLoader
    let dataCache: MockDataCache
    let imageCache: MockImageCache
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let imageCache = MockImageCache()
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.imageCache = imageCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = imageCache
        }
    }

    // MARK: - Cached Data That Can't Be Used

    /// The decoder is picked per context, so a factory can decline the data
    /// read from the disk cache – the image is then loaded as if there was no
    /// data in the cache.
    @Test func cachedDataWithNoDecoderIsLoadedFromTheNetwork() async throws {
        // GIVEN a factory that has no decoder for the data from the disk cache
        let cacheTypes = LockedArray<ImageResponse.CacheType?>()
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { context in
                cacheTypes.append(context.cacheType)
                guard context.cacheType != .disk else { return nil }
                return ImageDecoders.Default(context: context)
            }
        }
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(response.cacheType == nil)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(cacheTypes.values == [.disk, nil])
    }

    /// Data in the disk cache that fails to decode doesn't fail the request,
    /// and the downloaded data replaces it, so the next load doesn't pay for
    /// the failed decode again.
    @Test func corruptedCachedDataIsReplacedWithTheDownloadedData() async throws {
        // GIVEN
        dataCache.store[Test.url.absoluteString] = Data("corrupted".utf8)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(response.cacheType == nil)
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(dataLoader.createdTaskCount == 1)
        #expect(dataCache.store[Test.url.absoluteString] == Test.data)
    }

    @Test func corruptedCachedDataFailsTheRequestWhenLoadingIsNotAllowed() async throws {
        // GIVEN
        dataCache.store[Test.url.absoluteString] = Data("corrupted".utf8)
        let request = ImageRequest(url: Test.url, options: [.returnCacheDataDontLoad])

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataMissingInCache) {
            try await pipeline.image(for: request)
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    /// The fallback to the network happens when the decode of the cached data
    /// fails, which can be long after the task was cancelled.
    @Test func cancelledTaskDoesNotFallBackToTheNetworkWhenCachedDataFailsToDecode() async throws {
        // GIVEN a decoder that fails, but only once the test lets it
        let decoder = GatedFailingDecoder()
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN the task is cancelled while the cached data is being decoded
        let task = pipeline.imageTask(with: Test.request)
        await decoder.didStartDecoding.wait()
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        decoder.finishDecoding()
        await pipeline.configuration.imageDecodingQueue.waitUntilAllOperationsAreFinished()
        await pipeline.configuration.dataLoadingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: - Memory Cache Previews

    @Test func previewInMemoryCacheIsDeliveredBeforeTheImageFromDiskCache() async throws {
        // GIVEN a preview in the memory cache and the image data on disk
        let preview = ImageContainer(image: Test.image, isPreview: true)
        imageCache[Test.request] = preview
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN
        let events = LockedArray<ImageTask.Event>()
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            events.append(event)
        }
        let response = try await task.response

        // THEN the preview is delivered first, followed by the image from disk
        let values = events.values
        #expect(values.count == 2)
        guard case .preview(let delivered) = values.first else {
            Issue.record("Expected a preview, got \(values)")
            return
        }
        #expect(delivered.image === preview.image)
        #expect(delivered.cacheType == .memory)
        #expect(response.cacheType == .disk)
        #expect(!response.isPreview)
        #expect(dataLoader.createdTaskCount == 0)

        // THEN the image replaces the preview in the memory cache
        #expect(imageCache[Test.request]?.isPreview == false)
    }

    @Test func previewsAreNotStoredInMemoryCacheWhenDisabled() async throws {
        // GIVEN
        let dataLoader = MockProgressiveDataLoader()
        let imageCache = imageCache
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.isStoringPreviewsInMemoryCache = false
        }

        // WHEN
        let isCachedWhenDelivered = LockedArray<Bool>()
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            if case .preview = event {
                isCachedWhenDelivered.append(imageCache[Test.request] != nil)
                dataLoader.resume()
            }
        }
        let response = try await task.response

        // THEN the previews are delivered, but only the image is cached
        #expect(isCachedWhenDelivered.values == [false, false])
        #expect(imageCache.writeCount == 1)
        #expect(imageCache[Test.request]?.image === response.image)
    }

    @Test func previewsStoredInMemoryCacheAreRecordedAsProgressive() async throws {
        // GIVEN
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            if case .preview = event {
                dataLoader.resume()
            }
        }
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        let stores = metrics.jobs[0].stages.filter { $0.kind == .memoryStore }
        #expect(stores.map(\.isProgressive) == [true, true, nil])
        #expect(Set(stores.map(\.cacheKey)).count == 1)
    }

    // MARK: - Reusing Cached Images

    /// A processed image from the disk cache is reused for any request that
    /// adds more processors, and only the remaining ones are applied.
    @Test func processedImageOnDiskIsReusedForALongerProcessorChain() async throws {
        // GIVEN
        let processors = MockProcessorFactory()
        let p1 = processors.make(id: "1")
        let p2 = processors.make(id: "2")
        let p3 = processors.make(id: "3")
        let request = ImageRequest(url: Test.url, processors: [p1, p2, p3])
        let intermediateRequest = ImageRequest(url: Test.url, processors: [p1, p2])
        dataCache.store[pipeline.cache.makeDataCacheKey(for: intermediateRequest)] = Test.data

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.nk_test_processorIDs == ["3"])
        #expect(response.cacheType == .disk)
        #expect(processors.numberOfProcessorsApplied == 1)
        #expect(dataLoader.createdTaskCount == 0)
        #expect(dataCache.readCount == 2) // [1, 2, 3], then [1, 2]

        // THEN only the requested image is stored in the memory cache
        #expect(imageCache[request] != nil)
        #expect(imageCache[intermediateRequest] == nil)
    }

    @Test func thumbnailWithProcessorsIsGeneratedFromCachedOriginalData() async throws {
        // GIVEN only the original image data in the disk cache
        dataCache.store[Test.url.absoluteString] = Test.data
        var request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        request.thumbnail = .init(maxPixelSize: 400)

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN the thumbnail is generated from it and processed
        #expect(response.image.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func thumbnailIsGeneratedFromCachedOriginalDataWhenLoadingIsNotAllowed() async throws {
        // GIVEN only the original image data in the disk cache
        dataCache.store[Test.url.absoluteString] = Test.data
        var request = ImageRequest(url: Test.url, options: [.returnCacheDataDontLoad])
        request.thumbnail = .init(maxPixelSize: 400)

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func thumbnailDataOnDiskIsPreferredOverTheOriginalData() async throws {
        // GIVEN both the thumbnail and the original image data on disk
        var request = ImageRequest(url: Test.url)
        request.thumbnail = .init(maxPixelSize: 400)
        dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] = Test.data(name: "fixture-tiny", extension: "jpeg")
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN the stored thumbnail is used, and the original data isn't read
        #expect(response.image.sizeInPixels == CGSize(width: 200, height: 150))
        #expect(response.cacheType == .disk)
        #expect(dataCache.readCount == 1)
    }

    // MARK: - Processing

    @Test func processingFailureReportsTheFailingProcessorAndItsInput() async throws {
        // GIVEN a processor that fails after one that succeeds
        let error = MockError(description: "processor-failed")
        let request = ImageRequest(url: Test.url, processors: [
            MockImageProcessor(id: "1"),
            ThrowingProcessor(identifier: "failing", error: error)
        ])

        // WHEN
        do {
            _ = try await pipeline.imageTask(with: request).response
            Issue.record("Expected the request to fail")
        } catch {
            // THEN the error carries the processor, the image it was given,
            // and the error it threw
            guard case let .processingFailed(processor, context, underlyingError) = error else {
                Issue.record("Expected .processingFailed, got \(error)")
                return
            }
            #expect(processor.identifier == "failing")
            #expect(underlyingError as? MockError == MockError(description: "processor-failed"))
            #expect(context.response.image.nk_test_processorIDs == ["1"])
            #expect(context.isCompleted)
            #expect(context.request.processors.count == 2)
        }

        // THEN nothing is cached
        #expect(imageCache.writeCount == 0)
    }

    @Test func processorsAfterTheOneThatFailedAreNotApplied() async throws {
        // GIVEN
        let processors = MockProcessorFactory()
        let request = ImageRequest(url: Test.url, processors: [
            ThrowingProcessor(identifier: "failing", error: MockError(description: "processor-failed")),
            processors.make(id: "2")
        ])

        // WHEN
        do {
            _ = try await pipeline.imageTask(with: request).response
            Issue.record("Expected the request to fail")
        } catch {
            // THEN
            guard case let .processingFailed(processor, _, _) = error else {
                Issue.record("Expected .processingFailed, got \(error)")
                return
            }
            #expect(processor.identifier == "failing")
        }
        #expect(processors.numberOfProcessorsApplied == 0)
    }

    @Test func processedImageKeepsTheURLResponse() async throws {
        // WHEN
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.urlResponse?.url == Test.url)
        #expect(response.cacheType == nil)
    }

    // MARK: - Animated Images

    @Test func processingAnAnimatedImageDropsItsAnimation() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success(
            (Test.animatedGIF(frameCount: 3), URLResponse(url: Test.url, mimeType: "gif", expectedContentLength: 0, textEncodingName: nil))
        )
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN the still is processed, and the animation of the original image
        // is not played in its place
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(response.container.animation == nil)
        #expect(response.container.data == nil)
    }

    @Test(arguments: [true, false])
    func animatedImageFromDiskCacheIsParsedWhenParsingIsEnabled(isEnabled: Bool) async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.isAnimatedImageParsingEnabled = isEnabled
        }
        let data = Test.animatedGIF(frameCount: 5)
        dataCache.store[Test.url.absoluteString] = data

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(response.cacheType == .disk)
        #expect(response.container.data == data)
        #expect(response.container.animation?.frameCount == (isEnabled ? 5 : nil))
    }

    // MARK: - Storing Encoded Images

    @Test func encoderReceivesTheProcessedImageAndTheURLResponse() async throws {
        // GIVEN
        let contexts = LockedArray<ImageEncodingContext>()
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.makeImageEncoder = { context in
                contexts.append(context)
                return ImageEncoders.Default()
            }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(contexts.count == 1)
        let context = try #require(contexts.values.first)
        #expect(context.image === response.image)
        #expect(context.request.processors.count == 1)
        #expect(context.urlResponse?.url == Test.url)
        #expect(dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] != nil)
    }

    @Test func imagesAreNotEncodedWithoutADataCache() async throws {
        // GIVEN a policy that stores encoded images, but no data cache
        let encoderCount = LockedArray<Void>()
        let pipeline = pipeline.reconfigured {
            $0.dataCache = nil
            $0.dataCachePolicy = .storeEncodedImages
            $0.makeImageEncoder = { _ in
                encoderCount.append(())
                return ImageEncoders.Default()
            }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN
        _ = try await pipeline.imageTask(with: request).response

        // THEN the image isn't encoded for nothing
        #expect(encoderCount.count == 0)
    }

    @Test func encoderReturningEmptyDataStoresNothing() async throws {
        // GIVEN
        let encoder = MockImageEncoder(result: Data())
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
            $0.makeImageEncoder = { _ in encoder }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN
        _ = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.writeCount == 0)
    }

    // MARK: - Async Image Closure

    @Test func imageClosureIsNotCalledWhenTheImageIsInMemoryCache() async throws {
        // GIVEN
        let calls = LockedArray<Void>()
        let request = ImageRequest(id: "closure-image", image: {
            calls.append(())
            return Test.container
        })
        imageCache[request] = Test.container

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.cacheType == .memory)
        #expect(calls.count == 0)
    }

    /// There is no data to store for an image returned by a closure.
    @Test func imageFromClosureIsStoredInMemoryCacheOnly() async throws {
        // GIVEN
        let request = ImageRequest(id: "closure-image", image: { Test.container })

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(response.cacheType == nil)
        #expect(imageCache[request]?.image === response.image)
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func imageClosureIsNotCalledWhenLoadingIsNotAllowed() async throws {
        // GIVEN
        let calls = LockedArray<Void>()
        let request = ImageRequest(id: "closure-image", image: {
            calls.append(())
            return Test.container
        }, options: [.returnCacheDataDontLoad])

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataMissingInCache) {
            try await pipeline.image(for: request)
        }
        #expect(calls.count == 0)
    }

    @Test func imageClosureIsCancelledWithTheTask() async throws {
        // GIVEN a closure that waits until it is cancelled
        let didStart = TestExpectation()
        let didCancel = TestExpectation()
        let gate = AsyncGate()
        defer { gate.open() }
        let request = ImageRequest(id: "closure-image", image: {
            await withTaskCancellationHandler {
                didStart.fulfill()
                await gate.wait()
            } onCancel: {
                didCancel.fulfill()
                gate.open()
            }
            throw CancellationError()
        })

        // WHEN
        let task = pipeline.imageTask(with: request)
        await didStart.wait()
        task.cancel()

        // THEN the cancellation reaches the closure
        await didCancel.wait()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
    }

    @Test @ImagePipelineActor func imageClosureWaitsForTheDataLoadingQueue() async throws {
        // GIVEN a suspended data loading queue
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        let calls = LockedArray<Void>()
        let request = ImageRequest(id: "closure-image", image: {
            calls.append(())
            return Test.container
        })

        // WHEN
        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.imageTask(with: request)
        await expectation.wait()

        // THEN the closure is called only when the queue lets it
        #expect(calls.count == 0)
        queue.isSuspended = false
        _ = try await task.response
        #expect(calls.count == 1)
    }
}

// MARK: - Helpers

private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []

    func append(_ element: Element) {
        lock.withLock { elements.append(element) }
    }

    var values: [Element] {
        lock.withLock { elements }
    }

    var count: Int {
        values.count
    }
}

/// A processor that always throws the given error.
private struct ThrowingProcessor: ImageProcessing {
    let identifier: String
    let error: MockError

    func process(_ image: PlatformImage) -> PlatformImage? {
        nil
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        throw error
    }
}

/// A decoder that runs on the decoding queue and fails, but not before the
/// test calls ``finishDecoding()``.
private final class GatedFailingDecoder: ImageDecoding, @unchecked Sendable {
    let didStartDecoding = TestExpectation()
    private let semaphore = DispatchSemaphore(value: 0)

    func decode(_ data: Data) throws -> ImageContainer {
        didStartDecoding.fulfill()
        _ = semaphore.wait(timeout: .now() + 60)
        throw MockError(description: "decoder-failed")
    }

    func finishDecoding() {
        semaphore.signal()
    }
}
