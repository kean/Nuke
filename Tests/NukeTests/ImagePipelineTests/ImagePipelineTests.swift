// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(2)))
struct ImagePipelineTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Progress

    @Test func progressUpdated() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let task = pipeline.imageTask(with: Test.url)
        var progressValues: [ImageTask.Progress] = []
        for await progress in task.progress {
            progressValues.append(progress)
        }
        _ = try? await task.response

        // Then
        #expect(progressValues == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }

    // MARK: - Updating Priority

    @Test @ImagePipelineActor func dataLoadingPriorityUpdated() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        let expectation = TestExpectation(queue: queue, count: 1)
        let imageTask = pipeline.imageTask(with: request)
        Task.detached { try await imageTask.response }
        await expectation.wait()

        // When/Then
        let operation = try #require(expectation.operations.first)
        await queue.waitForPriorityChange(of: operation, to: .high) {
            imageTask.priority = .high
        }
    }

    @Test @ImagePipelineActor func decodingPriorityUpdated() async throws {
        // Given
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
        }

        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        let expectation = TestExpectation(queue: queue, count: 1)
        let imageTask = pipeline.imageTask(with: request)
        Task.detached { try await imageTask.response }
        await expectation.wait()

        // When/Then
        let operation = try #require(expectation.operations.first)
        await queue.waitForPriorityChange(of: operation, to: .high) {
            imageTask.priority = .high
        }
    }

    @Test @ImagePipelineActor func processingPriorityUpdated() async throws {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])
        #expect(request.priority == .normal)

        let expectation = TestExpectation(queue: queue, count: 1)
        let imageTask = pipeline.imageTask(with: request)
        Task.detached { try await imageTask.response }
        await expectation.wait()

        // When/Then
        let operation = try #require(expectation.operations.first)
        await queue.waitForPriorityChange(of: operation, to: .high) {
            imageTask.priority = .high
        }
    }

    // MARK: - Cancellation

    @Test func dataLoadingOperationCancelled() async {
        dataLoader.queue.isSuspended = true

        let startExpectation = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        Task.detached { try? await task.response }
        await startExpectation.wait()

        await notification(MockDataLoader.DidCancelTask, object: dataLoader) {
            task.cancel()
        }
    }

    @Test @ImagePipelineActor func decodingOperationCancelled() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
        }

        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.imageTask(with: Test.request)
        Task.detached { try? await task.response }
        await expectation.wait()

        // When/Then
        let operation = try #require(expectation.operations.first)
        await queue.waitForCancellation(of: operation) {
            task.cancel()
        }
    }

    @Test @ImagePipelineActor func processingOperationCancelled() async throws {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])

        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.imageTask(with: request)
        Task.detached { try? await task.response }
        await expectation.wait()

        // When/Then
        let operation = try #require(expectation.operations.first)
        await queue.waitForCancellation(of: operation) {
            task.cancel()
        }
    }

    // MARK: Decompression

#if !os(macOS)

    @Test func disablingDecompression() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.isDecompressionEnabled = false
        }

        // WHEN
        let image = try await pipeline.image(for: Test.url)

        // THEN
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == true)
    }

    @Test func disablingDecompressionForIndividualRequest() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, options: [.skipDecompression])

        // WHEN
        let image = try await pipeline.image(for: request)

        // THEN
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == true)
    }

    @Test func decompressionPerformed() async throws {
        // WHEN
        let image = try await pipeline.image(for: Test.request)

        // THEN
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }

    @Test func decompressionNotPerformedWhenProcessorWasApplied() async throws {
        // GIVEN request with scaling processor
        let input = Test.image
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockAnonymousImageDecoder(output: input) }
        }

        let request = ImageRequest(url: Test.url, processors: [
            .resize(size: CGSize(width: 40, height: 40))
        ])

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN
        #expect(ImageDecompression.isDecompressionNeeded(for: input) == true)
    }

    @Test func decompressionPerformedWhenProcessorIsAppliedButDoesNothing() async throws {
        // Given request with scaling processor
        let request = ImageRequest(url: Test.url, processors: [MockEmptyImageProcessor()])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then - Expect decompression to be performed (processor was applied but it did nothing)
        #expect(ImageDecompression.isDecompressionNeeded(for: response.image) == nil)
    }

#endif

    // MARK: - Thumbnail

    @Test func thumbnailIsGenerated() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 400) }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 400, height: 300))
    }

    @Test @ImagePipelineActor func thumbnailIsGeneratedOnDecodingQueue() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 400) }
        let observer = TaskQueueObserver(queue: pipeline.configuration.imageDecodingQueue)

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN
        #expect(observer.operations.count >= 1)
    }

#if os(iOS) || os(visionOS)
    @Test @ImagePipelineActor func thumbnailIsntDecompressed() async throws {
        pipeline.configuration.imageDecompressingQueue.isSuspended = true

        // GIVEN
        let request = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 400) }

        // WHEN/THEN - image loads even though decompression queue is suspended
        _ = try await pipeline.image(for: request)
    }
#endif

    // MARK: - CacheKey

    @Test func cacheKeyForRequest() {
        let request = Test.request
        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpeg")
    }

    @Test func cacheKeyForRequestWithProcessors() {
        var request = Test.request
        request.processors = [ImageProcessors.Anonymous(id: "1", { $0 })]
        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpeg1")
    }

    @Test func cacheKeyForRequestWithThumbnail() {
        let request = ImageRequest(url: Test.url).with {
            $0.thumbnail = .init(maxPixelSize: 400)
        }
        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpegcom.github/kean/nuke/thumbnail?maxPixelSize=400.0,options=truetruetruetrue")
    }

    @Test func cacheKeyForRequestWithThumbnailFlexibleSize() {
        let request = ImageRequest(url: Test.url).with {
            $0.thumbnail = .init(
                size: CGSize(width: 400, height: 400),
                unit: .pixels,
                contentMode: .aspectFit
            )
        }
        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpegcom.github/kean/nuke/thumbnail?width=400.0,height=400.0,contentMode=.aspectFit,options=truetruetruetrue")
    }

    // MARK: - Invalidate

    @Test func whenInvalidatedTasksAreCancelled() async {
        dataLoader.queue.isSuspended = true

        let startExpectation = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        Task.detached { try? await task.response }
        await startExpectation.wait()

        await notification(MockDataLoader.DidCancelTask, object: dataLoader) {
            pipeline.invalidate()
        }
    }

    @Test func invalidatedTasksFailWithError() async throws {
        // WHEN
        pipeline.invalidate()

        // THEN
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            #expect(error == .pipelineInvalidated)
        }
    }

    // MARK: Error Handling

    @Test func dataLoadingFailedErrorReturned() async {
        // Given
        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[Test.url] = .failure(expectedError)

        // When/Then
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            #expect(error == .dataLoadingFailed(error: expectedError))
        }
    }

    @Test func dataLoaderReturnsEmptyData() async {
        // Given
        dataLoader.results[Test.url] = .success((Data(), Test.urlResponse))

        // When/Then
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            #expect(error == .dataIsEmpty)
        }
    }

    @Test func decoderNotRegistered() async {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.makeImageDecoder = { _ in nil }
            $0.imageCache = nil
        }

        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            guard case let .decoderNotRegistered(context) = error else {
                Issue.record("Expected .decoderNotRegistered")
                return
            }
            #expect(context.request.url == Test.request.url)
            #expect(context.data.count == 22789)
            #expect(context.isCompleted)
            #expect(context.urlResponse?.url == Test.url)
        }
    }

    @Test func decodingFailedErrorReturned() async {
        // Given
        let decoder = MockFailingDecoder()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.makeImageDecoder = { _ in decoder }
            $0.imageCache = nil
        }

        // When/Then
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            if case let .decodingFailed(failedDecoder, context, error) = error {
                #expect((failedDecoder as? MockFailingDecoder) === decoder)
                #expect(context.request.url == Test.request.url)
                #expect(context.data == Test.data)
                #expect(context.isCompleted)
                #expect(context.urlResponse?.url == Test.url)
                #expect(error as? MockError == MockError(description: "decoder-failed"))
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func processingFailedErrorReturned() async {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [MockFailingProcessor()])

        // WHEN/THEN
        do {
            _ = try await pipeline.image(for: request)
            Issue.record("Expected failure")
        } catch {
            guard case let .processingFailed(processor, context, underlyingError) = error else {
                Issue.record("Expected .processingFailed")
                return
            }
            #expect(processor is MockFailingProcessor)
            #expect(context.request.url == Test.url)
            #expect(context.response.container.image.sizeInPixels == CGSize(width: 640, height: 480))
            #expect(context.response.cacheType == nil)
            #expect(context.isCompleted == true)
            #expect(underlyingError as? ImageProcessingError == .unknown)
        }
    }

    @Test func imageContainerUserInfo() {
        // WHEN
        let container = ImageContainer(image: Test.image, type: nil, isPreview: false, data: nil, userInfo: [.init("a"): 1])

        // THEN
        #expect(container.userInfo["a"] as? Int == 1)
    }

    @Test func errorDescription() {
        #expect(!ImagePipeline.Error.dataLoadingFailed(error: Foundation.URLError(.unknown)).description.isEmpty)

        #expect(!ImagePipeline.Error.decodingFailed(decoder: MockImageDecoder(name: "test"), context: .mock, error: MockError(description: "decoding-failed")).description.isEmpty)

        let processor = ImageProcessors.Resize(width: 100, unit: .pixels)
        let error = ImagePipeline.Error.processingFailed(processor: processor, context: .mock, error: MockError(description: "processing-failed"))
        let expected = "Failed to process the image using processor Resize(size: (100.0, 9999.0) pixels, contentMode: .aspectFit, crop: false, upscale: false). Underlying error: MockError(description: \"processing-failed\")."
        #expect(error.description == expected)
        #expect("\(error)" == expected)

        #expect(error.dataLoadingError == nil)
    }

    // MARK: Skip Data Loading Queue Option

    @Test @ImagePipelineActor func skipDataLoadingQueuePerRequestWithURL() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = ImageRequest(url: Test.url, options: [
            .skipDataLoadingQueue
        ])

        // Then image is still loaded
        _ = try await pipeline.image(for: request)
    }

    @Test @ImagePipelineActor func skipDataLoadingQueuePerRequestWithPublisher() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = ImageRequest(id: "a", data: { Test.data }, options: [
            .skipDataLoadingQueue
        ])

        // Then image is still loaded
        _ = try await pipeline.image(for: request)
    }

    // MARK: Misc

    @Test func loadWithStringLiteral() async throws {
        let image = try await pipeline.image(for: "https://example.com/image.jpeg")
        #expect(image.size != .zero)
    }

    @Test func loadWithInvalidURL() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }

        // WHEN
        for _ in 0...10 {
            do {
                _ = try await pipeline.image(for: ImageRequest(url: URL(string: "")))
                Issue.record("Expected failure")
            } catch {
                // Expected
            }
        }
    }

#if !os(macOS)
    @Test func overridingImageScale() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url).with { $0.scale = 7 }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.scale == 7)
    }

    @Test func overridingImageScaleWithFloat() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url).with { $0.scale = 7.0 }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.scale == 7)
    }
#endif

    // MARK: - Error Propagation

    @Test func errorPropagatedWhenDataLoadingFails() async {
        // GIVEN - data loader configured to fail
        let error = NSError(domain: "test", code: -1)
        dataLoader.results[Test.url] = .failure(error)

        // WHEN
        do {
            _ = try await pipeline.imageTask(with: Test.request).response
            Issue.record("Expected error to be thrown")
        } catch {
            // THEN - the underlying error is wrapped in a pipeline error
            #expect(error.dataLoadingError != nil)
        }
    }

    @Test func errorPropagatedToBothCoalescedSubscribers() async {
        // GIVEN - two tasks for the same URL, data loader will fail
        let error = NSError(domain: "test", code: -1)
        dataLoader.results[Test.url] = .failure(error)

        // WHEN - both tasks are started concurrently
        async let result1: ImageResponse = pipeline.imageTask(with: Test.request).response
        async let result2: ImageResponse = pipeline.imageTask(with: Test.request).response

        var errorCount = 0
        do { _ = try await result1 } catch { errorCount += 1 }
        do { _ = try await result2 } catch { errorCount += 1 }

        // THEN - both subscribers receive an error
        #expect(errorCount == 2)
        // Only one network request was made (coalesced)
        #expect(dataLoader.createdTaskCount == 1)
    }
}
