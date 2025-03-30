// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Combine
import Foundation

@testable import Nuke

@Suite class ImagePipelineCallbacksTests {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    init() {
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Completion

    @Test func completionCalledOnMainThread() async throws {
        let response = try await withCheckedThrowingContinuation { continuation in
            pipeline.loadImage(with: Test.request) { result in
                #expect(Thread.isMainThread)
                continuation.resume(with: result)
            }
        }
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    // MARK: - Progress

    @Test func taskProgressIsUpdated() async {
        // Given
        let request = ImageRequest(url: Test.url)

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let recordedProgress = Mutex<[ImageTask.Progress]>(wrappedValue: [])
        await withCheckedContinuation { continuation in
            pipeline.loadImage(
                with: request,
                progress: { _, completed, total in
                    // Then
                    #expect(Thread.isMainThread)
                    recordedProgress.withLock {
                        $0.append(ImageTask.Progress(completed: completed, total: total))
                    }
                },
                completion: { _ in
                    continuation.resume()
                }
            )
        }

        // Then
        #expect(recordedProgress.wrappedValue == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }
}

//    @Test func decodingPriorityUpdated() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
//        }
//
//        let queue = pipeline.configuration.imageDecodingQueue
//        queue.isSuspended = true
//
//        let request = Test.request
//        #expect(request.priority == .normal)
//
//        let observer = expect(queue).toEnqueueOperationsWithCount(1)
//
//        let task = pipeline.loadImage(with: request) { _ in }
//        wait() // Wait till the operation is created.
//
//        // When/Then
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        expect(operation).toUpdatePriority()
//        task.priority = .high
//
//        wait()
//    }
//
//    @Test func processingPriorityUpdated() {
//        // Given
//        let queue = pipeline.configuration.imageProcessingQueue
//        queue.isSuspended = true
//
//        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])
//        #expect(request.priority == .normal)
//
//        let observer = expect(queue).toEnqueueOperationsWithCount(1)
//
//        let task = pipeline.loadImage(with: request) { _ in }
//        wait() // Wait till the operation is created.
//
//        // When/Then
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        expect(operation).toUpdatePriority()
//        task.priority = .high
//
//        wait()
//    }
//
//    // MARK: - Cancellation
//
//    @Test func dataLoadingOperationCancelled() {
//        dataLoader.queue.isSuspended = true
//
//        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
//        let task = pipeline.loadImage(with: Test.request) { _ in
//            Issue.record()
//        }
//        wait() // Wait till operation is created
//
//        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
//        task.cancel()
//        wait()
//    }
//
//    @Test func decodingOperationCancelled() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
//        }
//
//        let queue = pipeline.configuration.imageDecodingQueue
//        queue.isSuspended = true
//
//        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)
//
//        let request = Test.request
//
//        let task = pipeline.loadImage(with: request) { _ in
//            Issue.record()
//        }
//        wait() // Wait till operation is created
//
//        // When/Then
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        expect(operation).toCancel()
//
//        task.cancel()
//
//        wait()
//    }
//
//    @Test func processingOperationCancelled() {
//        // Given
//        let queue = pipeline.configuration.imageProcessingQueue
//        queue.isSuspended = true
//
//        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)
//
//        let processor = ImageProcessors.Anonymous(id: "1") {
//            Issue.record()
//            return $0
//        }
//        let request = ImageRequest(url: Test.url, processors: [processor])
//
//        let task = pipeline.loadImage(with: request) { _ in
//            Issue.record()
//        }
//        wait() // Wait till operation is created
//
//        // When/Then
//        let operation = observer.operations.first
//        #expect(operation != nil)
//        expect(operation!).toCancel()
//
//        task.cancel()
//
//        wait()
//    }
//
//    // MARK: Decompression
//
//#if !os(macOS)
//
//    @Test func disablingDecompression() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.isDecompressionEnabled = false
//        }
//
//        // When
//        let image = try await pipeline.image(for: Test.url)
//
//        // Then
//        #expect(true == ImageDecompression.isDecompressionNeeded(for: image))
//    }
//
//    @Test func disablingDecompressionForIndividualRequest() async throws {
//        // Given
//        let request = ImageRequest(url: Test.url, options: [.skipDecompression])
//
//        // When
//        let image = try await pipeline.image(for: request)
//
//        // Then
//        #expect(true == ImageDecompression.isDecompressionNeeded(for: image))
//    }
//
//    @Test func decompressionPerformed() async throws {
//        // When
//        let image = try await pipeline.image(for: Test.request)
//
//        // Then
//        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
//    }
//
//    @Test func decompressionNotPerformedWhenProcessorWasApplied() async throws {
//        // Given request with scaling processor
//        let input = Test.image
//        pipeline = pipeline.reconfigured {
//            $0.makeImageDecoder = { _ in MockAnonymousImageDecoder(output: input) }
//        }
//
//        let request = ImageRequest(url: Test.url, processors: [
//            .resize(size: CGSize(width: 40, height: 40))
//        ])
//
//        // When
//        _ = try await pipeline.image(for: request)
//
//        // Then
//        #expect(true == ImageDecompression.isDecompressionNeeded(for: input))
//    }
//
//    @Test func decompressionPerformedWhenProcessorIsAppliedButDoesNothing() {
//        // Given request with scaling processor
//        let request = ImageRequest(url: Test.url, processors: [MockEmptyImageProcessor()])
//
//        expect(pipeline).toLoadImage(with: request) { result in
//            guard let image = result.value?.image else {
//                return Issue.record("Expected image to be loaded")
//            }
//
//            // Expect decompression to be performed (processor was applied but it did nothing)
//            #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
//        }
//        wait()
//    }
//
//#endif
//
//    // MARK: - Thumbnail
//
//    @Test func thatThumbnailIsGenerated() {
//        // Given
//        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
//        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
//
//        // When
//        expect(pipeline).toLoadImage(with: request) { result in
//            // Then
//            guard let image = result.value?.image else {
//                return Issue.record()
//            }
//            #expect(image.sizeInPixels == CGSize(width: 400, height: 300))
//        }
//        wait()
//    }
//
//    @Test func thumbnailIsGeneratedOnDecodingQueue() {
//        // Given
//        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
//        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
//
//        // When/Them
//        expect(pipeline.configuration.imageDecodingQueue).toEnqueueOperationsWithCount(1)
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//    }
//
//#if os(iOS) || os(visionOS)
//    @Test func thumnbailIsntDecompressed() {
//        pipeline.configuration.imageDecompressingQueue.isSuspended = true
//
//        // Given
//        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
//        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
//
//        // When/Them
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//    }
//#endif
//
//    // MARK: - CacheKey
//
//    @Test func cacheKeyForRequest() {
//        let request = Test.request
//        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpeg")
//    }
//
//    @Test func cacheKeyForRequestWithProcessors() {
//        var request = Test.request
//        request.processors = [ImageProcessors.Anonymous(id: "1", { $0 })]
//        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpeg1")
//    }
//
//    @Test func cacheKeyForRequestWithThumbnail() {
//        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
//        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
//        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpegcom.github/kean/nuke/thumbnail?maxPixelSize=400.0,options=truetruetruetrue")
//    }
//
//    @Test func cacheKeyForRequestWithThumbnailFlexibleSize() {
//        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit)
//        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
//        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpegcom.github/kean/nuke/thumbnail?width=400.0,height=400.0,contentMode=.aspectFit,options=truetruetruetrue")
//    }
//
//    // MARK: - Invalidate
//
//    @Test func whenInvalidatedTasksAreCancelled() {
//        dataLoader.queue.isSuspended = true
//
//        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
//        pipeline.loadImage(with: Test.request) { _ in
//            Issue.record()
//        }
//        wait() // Wait till operation is created
//
//        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
//        pipeline.invalidate()
//        wait()
//    }
//
//    @Test func thatInvalidatedTasksFailWithError() async throws {
//        // When
//        pipeline.invalidate()
//
//        // Then
//        do {
//            _ = try await pipeline.image(for: Test.request)
//            Issue.record()
//        } catch {
//            #expect(error as? ImagePipeline.Error == .pipelineInvalidated)
//        }
//    }
//
//    // MARK: Error Handling
//
//    @Test func dataLoadingFailedErrorReturned() {
//        // Given
//        let dataLoader = MockDataLoader()
//        let pipeline = ImagePipeline {
//            $0.dataLoader = dataLoader
//            $0.imageCache = nil
//        }
//
//        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
//        dataLoader.results[Test.url] = .failure(expectedError)
//
//        // When/Then
//        expect(pipeline).toFailRequest(Test.request, with: .dataLoadingFailed(error: expectedError))
//        wait()
//    }
//
//    @Test func dataLoaderReturnsEmptyData() {
//        // Given
//        let dataLoader = MockDataLoader()
//        let pipeline = ImagePipeline {
//            $0.dataLoader = dataLoader
//            $0.imageCache = nil
//        }
//
//        dataLoader.results[Test.url] = .success((Data(), Test.urlResponse))
//
//        // When/Then
//        expect(pipeline).toFailRequest(Test.request, with: .dataIsEmpty)
//        wait()
//    }
//
//    @Test func decoderNotRegistered() {
//        // Given
//        let pipeline = ImagePipeline {
//            $0.dataLoader = MockDataLoader()
//            $0.makeImageDecoder = { _ in
//                nil
//            }
//            $0.imageCache = nil
//        }
//
//        expect(pipeline).toFailRequest(Test.request) { result in
//            guard let error = result.error else {
//                return Issue.record("Expected error")
//            }
//            guard case let .decoderNotRegistered(context) = error else {
//                return Issue.record("Expected .decoderNotRegistered")
//            }
//            #expect(context.request.url == Test.request.url)
//            #expect(context.data.count == 22789)
//            #expect(context.isCompleted)
//            #expect(context.urlResponse?.url == Test.url)
//        }
//        wait()
//    }
//
//    @Test func decodingFailedErrorReturned() async {
//        // Given
//        let decoder = MockFailingDecoder()
//        let pipeline = ImagePipeline {
//            $0.dataLoader = MockDataLoader()
//            $0.makeImageDecoder = { _ in decoder }
//            $0.imageCache = nil
//        }
//
//        // When/Then
//        do {
//            _ = try await pipeline.image(for: Test.request)
//            Issue.record("Expected failure")
//        } catch {
//            if case let .decodingFailed(failedDecoder, context, error) = error as? ImagePipeline.Error {
//                #expect((failedDecoder as? MockFailingDecoder) === decoder)
//
//                #expect(context.request.url == Test.request.url)
//                #expect(context.data == Test.data)
//                #expect(context.isCompleted)
//                #expect(context.urlResponse?.url == Test.url)
//
//                #expect(error as? MockError == MockError(description: "decoder-failed"))
//            } else {
//                Issue.record("Unexpected error: \(error)")
//            }
//        }
//    }
//
//    @Test func processingFailedErrorReturned() {
//        // Given
//        let pipeline = ImagePipeline {
//            $0.dataLoader = MockDataLoader()
//        }
//
//        let request = ImageRequest(url: Test.url, processors: [MockFailingProcessor()])
//
//        // When/Them
//        expect(pipeline).toFailRequest(request) { result in
//            guard case .failure(let error) = result,
//                  case let .processingFailed(processor, context, error) = error else {
//                return Issue.record()
//            }
//
//            #expect(processor is MockFailingProcessor)
//
//            #expect(context.request.url == Test.url)
//            #expect(context.response.container.image.sizeInPixels == CGSize(width: 640, height: 480))
//            #expect(context.response.cacheType == nil)
//            #expect(context.isCompleted == true)
//
//            #expect(error as? ImageProcessingError == .unknown)
//        }
//        wait()
//    }
//
//    @Test func imageContainerUserInfo() { // Just to make sure we have 100% coverage
//        // When
//        let container = ImageContainer(image: Test.image, type: nil, isPreview: false, data: nil, userInfo: [.init("a"): 1])
//
//        // Then
//        #expect(container.userInfo["a"] as? Int == 1)
//    }
//
//    @Test func errorDescription() {
//        #expect(!ImagePipeline.Error.dataLoadingFailed(error: URLError(.unknown)).description.isEmpty) // Just padding here // Just padding here
//
//        #expect(!ImagePipeline.Error.decodingFailed(decoder: MockImageDecoder(name: "test"), context: .mock, error: MockError(description: "decoding-failed")).description.isEmpty) // Just padding // Just padding
//
//        let processor = ImageProcessors.Resize(width: 100, unit: .pixels)
//        let error = ImagePipeline.Error.processingFailed(processor: processor, context: .mock, error: MockError(description: "processing-failed"))
//        let expected = "Failed to process the image using processor Resize(size: (100.0, 9999.0) pixels, contentMode: .aspectFit, crop: false, upscale: false). Underlying error: MockError(description: \"processing-failed\")."
//        #expect(error.description == expected)
//        #expect("\(error)" == expected)
//
//        #expect(error.dataLoadingError == nil)
//    }
//
//    // MARK: Skip Data Loading Queue Option
//
//    @Test func skipDataLoadingQueuePerRequestWithURL() throws {
//        // Given
//        let queue = pipeline.configuration.dataLoadingQueue
//        queue.isSuspended = true
//
//        let request = ImageRequest(url: Test.url, options: [
//            .skipDataLoadingQueue
//        ])
//
//        // Then image is still loaded
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//    }
//
//    // MARK: Misc
//
//    @Test func loadWithStringLiteral() async throws {
//        let image = try await pipeline.image(for: "https://example.com/image.jpeg")
//        #expect(image.size != .zero)
//    }
//
//    @Test func loadWithInvalidURL() throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataLoader = DataLoader()
//        }
//
//        // When
//        for _ in 0...10 {
//            expect(pipeline).toFailRequest(ImageRequest(url: URL(string: "")))
//            wait()
//        }
//    }
//
//#if !os(macOS)
//    @Test func overridingImageScale() throws {
//        // Given
//        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        let image = try #require(record.image)
//        #expect(image.scale == 7)
//    }
//
//    @Test func overridingImageScaleWithFloat() throws {
//        // Given
//        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7.0])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        let image = try #require(record.image)
//        #expect(image.scale == 7)
//    }
//#endif
//}
