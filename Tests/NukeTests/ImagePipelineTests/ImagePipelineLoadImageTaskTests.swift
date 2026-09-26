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

    @Test func previewsAreNotStoredInMemoryCacheWhenDisabled() async throws {
        // GIVEN
        let dataLoader = MockProgressiveDataLoader()
        let imageCache = imageCache
        let pipeline = dataLoader.makePipeline {
            $0.imageCache = imageCache
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
        let pipeline = dataLoader.makePipeline {
            $0.imageCache = MockImageCache()
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

    /// The same for a processed image in the memory cache.
    @Test func processedImageInMemoryIsReusedForALongerProcessorChain() async throws {
        // GIVEN
        let processors = MockProcessorFactory()
        imageCache[ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])] = Test.container

        // WHEN
        let request = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2"), processors.make(id: "3")])
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.nk_test_processorIDs == ["3"])
        #expect(dataLoader.createdTaskCount == 0)
        #expect(processors.numberOfProcessorsApplied == 1)
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
            MockThrowingProcessor(identifier: "failing", error: error)
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
            MockThrowingProcessor(identifier: "failing", error: MockError(description: "processor-failed")),
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
        let encoder = MockImageEncoder(result: Test.data)
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.makeImageEncoder = { _ in encoder }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(encoder.contexts.count == 1)
        let context = try #require(encoder.contexts.first)
        #expect(context.image === response.image)
        #expect(context.request.processors.count == 1)
        #expect(context.urlResponse?.url == Test.url)
        #expect(dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] != nil)
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

    @Test func processorsAreAppliedToTheImageFromTheClosure() async throws {
        // GIVEN
        let image = try #require(PlatformImage(data: Test.data))
        let container = ImageContainer(image: image)

        // WHEN
        let request = ImageRequest(
            id: "closure-image",
            image: { container },
            processors: [.resize(size: CGSize(width: 160, height: 120), unit: .pixels)]
        )
        let result = try await pipeline.image(for: request)

        // THEN the image is resized (the original is 640x480)
        #expect(result.sizeInPixels == CGSize(width: 160, height: 120))
    }

    /// The error of the closure is reported as is – even a cancellation
    /// error, since the task itself wasn't cancelled.
    @Test func imageClosureErrorIsReportedAsDataLoadingFailed() async throws {
        // GIVEN
        let request = ImageRequest(id: "closure-image", image: {
            throw URLError(.cancelled)
        })

        // WHEN/THEN
        do {
            _ = try await pipeline.image(for: request)
            Issue.record("Expected failure")
        } catch {
            if case let .dataLoadingFailed(error) = error {
                #expect((error as? URLError)?.code == .cancelled)
            } else {
                Issue.record("Unexpected error type")
            }
        }
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
