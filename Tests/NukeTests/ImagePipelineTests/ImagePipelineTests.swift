// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

@ImagePipelineActor
@Suite class ImagePipelineTests {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    private var recordedEvents: [ImageTask.Event] = []
    private var recordedResult: Result<ImageResponse, ImageTask.Error>?
    private var recordedProgress: [ImageTask.Progress] = []
    private var recordedPreviews: [ImageResponse] = []
    private var pipelineDelegate = ImagePipelineObserver()
    private var imageTask: ImageTask?

    init() {
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline(delegate: pipelineDelegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Basics

    @Test func imageIsLoaded() async throws {
        // When
        let image = try await pipeline.image(for: Test.request)

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    // MARK: - Task-based API

    @Test func taskBasedImageResponse() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)

        // When
        let response = try await task.response

        // Then
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func taskBasedImage() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)

        // When
        let image = try await task.image

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    private var observer: AnyObject?

    // MARK: - Cancellation

    @Test func cancellation() async throws {
        dataLoader.queue.isSuspended = true

        let task = Task {
            try await pipeline.image(for: Test.url)
        }

        observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: OperationQueue()) { _ in
            task.cancel()
        }

        do {
            _ = try await task.value
        } catch {
            #expect((error as? ImageTask.Error) == .cancelled)
        }
    }

    @Test func cancelImmediately() async throws {
        dataLoader.queue.isSuspended = true

        let task = Task {
            try await pipeline.image(for: Test.url)
        }
        task.cancel()

        do {
            _ = try await task.value
        } catch {
            #expect((error as? ImageTask.Error) == .cancelled)
        }
    }

    @Test func cancelFromProgress() async throws {
        dataLoader.queue.isSuspended = true

        let task = Task {
            let task = pipeline.imageTask(with: Test.url)
            for await value in task.progress {
                recordedProgress.append(value)
            }
        }

        task.cancel()

        _ = await task.value

        // Then nothing is recorded because the task is cancelled and
        // stop observing the events
        #expect(recordedProgress == [])
    }

    @Test func observeProgressAndCancelFromOtherTask() async throws {
        dataLoader.queue.isSuspended = true

        let task = pipeline.imageTask(with: Test.url)

        let task1 = Task {
            for await event in task.progress {
                recordedProgress.append(event)
            }
        }

        let task2 = Task {
            try await task.response
        }

        task2.cancel()

        async let result1: () = task1.value
        async let result2 = task2.value

        // Then you are able to observe `event` update because
        // this task does no get cancelled
        do {
            _ = try await (result1, result2)
        } catch {
            #expect((error as? ImageTask.Error) == .cancelled)
        }
        #expect(recordedProgress == [])
    }

    @Test func cancelAsyncImageTask() async throws {
        dataLoader.queue.isSuspended = true

        let task = pipeline.imageTask(with: Test.url)
        observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: OperationQueue()) { _ in
            task.cancel()
        }

        do {
            _ = try await task.image
        } catch {
            #expect(error == .cancelled)
        }
    }

    @Test func dataLoadingOperationCancelled() async {
        //  Given
        dataLoader.queue.isSuspended = true

        let expectation1 = AsyncExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.loadImage(with: Test.request) { _ in
            Issue.record()
        }
        await expectation1.wait() // Wait till operation is created

        // When
        let expectation2 = AsyncExpectation(notification: MockDataLoader.DidCancelTask, object: dataLoader)
        task.cancel()

        // Then
        await expectation2.wait()
    }

    @Test func decodingOperationCancelled() async {
        // Given
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
        }

        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let expectation1 = queue.expectJobAdded()
        let request = Test.request
        let task = pipeline.imageTask(with: request).resume()
        let job = await expectation1.wait()

        // When
        let expectation2 = queue.expectJobCancelled(job)
        task.cancel()

        // Then
        await expectation2.wait()
    }

    @Test func processingOperationCancelled() async {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let processor = ImageProcessors.Anonymous(id: "1") {
            Issue.record()
            return $0
        }
        let expectation1 = queue.expectJobAdded()
        let request = ImageRequest(url: Test.url, processors: [processor])
        let task = pipeline.imageTask(with: request).resume()
        let job = await expectation1.wait()

        // When
        let expectation2 = queue.expectJobCancelled(job)
        task.cancel()

        // Then
        await expectation2.wait()
    }

    // MARK: - Load Data

    @Test func loadData() async throws {
        // Given
        dataLoader.results[Test.url] = .success((Test.data, Test.urlResponse))

        // When
        let (data, response) = try await pipeline.data(for: Test.request)

        // Then
        #expect(data.count == 22788)
        #expect(response?.url == Test.url)
    }

    @Test func loadDataCancelImmediately() async throws {
        dataLoader.queue.isSuspended = true

        let task = Task {
            try await pipeline.data(for: Test.request)
        }
        task.cancel()

        do {
            _ = try await task.value
        } catch {
            #expect((error as? ImageTask.Error) == .cancelled)
        }
    }

    @Test func progressUpdated() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        do {
            let task = pipeline.imageTask(with: Test.url)
            for await progress in task.progress {
                recordedProgress.append(progress)
            }
            _ = try await task.image
        } catch {
            // Do nothing
        }

        // Then
        #expect(recordedProgress == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }

    @Test func progressivePreviews() async throws {
        // Given
        let dataLoader = MockProgressiveDataLoader()
        pipeline = pipeline.reconfigured {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
        }

        // When
        let task = pipeline.imageTask(with: Test.url)
        Task {
            for try await preview in task.previews {
                recordedPreviews.append(preview)
                dataLoader.resume()
            }
        }
        _ = try await task.image

        // Then
        #expect(recordedPreviews.count == 2)
        #expect(recordedPreviews.allSatisfy { $0.container.isPreview })
    }

    // MARK: - ImageRequest

    @Test func imageRequestWithAsyncAwaitSuccess() async throws {
        // Given
        let localURL = Test.url(forResource: "fixture", extension: "jpeg")

        // When
        let request = ImageRequest(id: "test", data: {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: localURL))
            return data
        })

        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func imageRequestWithAsyncAwaitFailure() async throws {
        // When
        let request = ImageRequest(id: "test", data: {
            throw URLError(networkUnavailableReason: .cellular)
        })
        
        do {
            _ = try await pipeline.image(for: request)
            Issue.record()
        } catch {
            if case let .dataLoadingFailed(error) = error {
                #expect((error as? URLError)?.networkUnavailableReason == .cellular)
            } else {
                Issue.record()
            }
        }
    }

    // MARK: Common Use Cases

    @Test func lowDataMode() async throws {
        // Given
        let highQualityImageURL = URL(string: "https://example.com/high-quality-image.jpeg")!
        let lowQualityImageURL = URL(string: "https://example.com/low-quality-image.jpeg")!

        dataLoader.results[highQualityImageURL] = .failure(URLError(networkUnavailableReason: .constrained) as NSError)
        dataLoader.results[lowQualityImageURL] = .success((Test.data, Test.urlResponse))

        // When
        let pipeline = self.pipeline!

        // Create the default request to fetch the high quality image.
        var urlRequest = URLRequest(url: highQualityImageURL)
        urlRequest.allowsConstrainedNetworkAccess = false
        let request = ImageRequest(urlRequest: urlRequest)

        // When
        @Sendable func loadImage() async throws -> PlatformImage {
            do {
                return try await pipeline.image(for: request)
            } catch {
                guard (error.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained else {
                    throw error
                }
                return try await pipeline.image(for: lowQualityImageURL)
            }
        }

        _ = try await loadImage()
    }

    // MARK: - ImageTask Integration

    @Test func imageTaskEvents() async throws {
        // Given
        let dataLoader = MockProgressiveDataLoader()
        pipeline = pipeline.reconfigured {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
        }

        // When
        let task = pipeline.loadImage(with: Test.request) { _ in }
        for await event in task.events {
            switch event {
            case .preview(let response):
                recordedPreviews.append(response)
                dataLoader.resume()
            case .finished(let result):
                recordedResult = result
            default:
                break
            }
            recordedEvents.append(event)
        }

        // Then
        try #require(recordedPreviews.count == 2)

        let result = try #require(recordedResult)

        #expect(recordedEvents.filter {
            if case .progress = $0 {
                return false // There is guarantee if all will arrive
            }
            return true
        } == [
            .preview(recordedPreviews[0]),
            .preview(recordedPreviews[1]),
            .finished(result)
        ])
    }

    // MARK: - Thumbnails

    @Test func thatThumbnailIsGenerated() async throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])

        // When
        let image = try await pipeline.image(for: request)
        #expect(image.sizeInPixels == CGSize(width: 400, height: 300))
    }

    @Test func thumbnailIsGeneratedOnDecodingQueue() async {
        // Given
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])

        // When
        let expectation = pipeline.configuration.imageDecodingQueue.expectJobAdded()
        pipeline.imageTask(with: request).resume()

        // Then work item is created on an expected queue
        await expectation.wait()
    }

#if os(iOS) || os(visionOS)
    @Test func thumnbailIsntDecompressed() async throws {
        // Given a suspended queue so no work can be performed
        pipeline.configuration.imageDecompressingQueue.isSuspended = true

        // When
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])

        // Then image is loaded without decompression
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
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpegcom.github/kean/nuke/thumbnail?maxPixelSize=400.0,options=truetruetruetrue")
    }

    @Test func cacheKeyForRequestWithThumbnailFlexibleSize() {
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
        #expect(pipeline.cache.makeDataCacheKey(for: request) == "http://test.com/example.jpegcom.github/kean/nuke/thumbnail?width=400.0,height=400.0,contentMode=.aspectFit,options=truetruetruetrue")
    }

    // MARK: - Invalidate

    @Test func whenInvalidatedTasksAreCancelled() async {
        // Given
        dataLoader.queue.isSuspended = true

        let expectation1 = AsyncExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        pipeline.imageTask(with: Test.request).resume()
        await expectation1.wait()

        // When
        let expectation2 = AsyncExpectation(notification: MockDataLoader.DidCancelTask, object: dataLoader)
        pipeline.invalidate()

        // Then
        await expectation2.wait()
    }

    @Test func thatInvalidatedTasksFailWithError() async throws {
        // When
        pipeline.invalidate()

        // Then
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record()
        } catch {
            #expect(error == .pipelineInvalidated)
        }
    }

    // MARK: - Error Handling

    @Test func dataLoadingFailedErrorReturned() async throws {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[Test.url] = .failure(expectedError)

        // When
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Unexpected success")
        } catch {
            // Then
            #expect(error == .dataLoadingFailed(error: expectedError))
        }
    }

    @Test func dataLoaderReturnsEmptyData() async throws {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        dataLoader.results[Test.url] = .success((Data(), Test.urlResponse))

        // When
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Unexpected success")
        } catch {
            // Then
            #expect(error == .dataIsEmpty)
        }
    }

    @Test func decoderNotRegistered() async throws {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.makeImageDecoder = { _ in nil }
            $0.imageCache = nil
        }

        // When
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Unexpected success")
        } catch {
            // Then
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

    @Test func decodingFailedErrorReturned() async throws {
        // Given
        let decoder = MockFailingDecoder()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.makeImageDecoder = { _ in decoder }
            $0.imageCache = nil
        }

        // When
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Unexpected success")
        } catch {
            // Then
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

    @Test func processingFailedErrorReturned() async throws {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
        }

        let request = ImageRequest(url: Test.url, processors: [MockFailingProcessor()])

        // When/Then
        do {
            _ = try await pipeline.image(for: request)
            Issue.record("Unexpected success")
        } catch {
            // Then
            if case let .processingFailed(processor, context, error) = error {
                #expect(processor is MockFailingProcessor)

                #expect(context.request.url == Test.url)
                #expect(context.response.container.image.sizeInPixels == CGSize(width: 640, height: 480))
                #expect(context.response.cacheType == nil)
                #expect(context.isCompleted == true)

                #expect(error as? ImageProcessingError == .unknown)
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func errorDescription() {
        let dataLoadingError = ImageTask.Error.dataLoadingFailed(error: Foundation.URLError(.unknown))
        #expect(!dataLoadingError.description.isEmpty) // Just padding here

        #expect(!ImageTask.Error.decodingFailed(decoder: MockImageDecoder(name: "test"), context: .mock, error: MockError(description: "decoding-failed")).description.isEmpty) // Just padding // Just padding

        let processor = ImageProcessors.Resize(width: 100, unit: .pixels)
        let error = ImageTask.Error.processingFailed(processor: processor, context: .mock, error: MockError(description: "processing-failed"))
        let expected = "Failed to process the image using processor Resize(size: (100.0, 9999.0) pixels, contentMode: .aspectFit, crop: false, upscale: false). Underlying error: MockError(description: \"processing-failed\")."
        #expect(error.description == expected)
        #expect("\(error)" == expected)

        #expect(error.dataLoadingError == nil)
    }

    // MARK: - Misc

    @Test func imageContainerUserInfo() { // Just to make sure we have 100% coverage
        // When
        let container = ImageContainer(image: Test.image, type: nil, isPreview: false, data: nil, userInfo: [.init("a"): 1])

        // Then
        #expect(container.userInfo["a"] as? Int == 1)
    }

    @Test func skipDataLoadingQueuePerRequestWithURL() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = ImageRequest(url: Test.url, options: [
            .skipDataLoadingQueue
        ])

        // Then image is still loaded
        _ = try await pipeline.image(for: request)
    }

    @Test func loadWithStringLiteral() async throws {
        let image = try await pipeline.image(for: "https://example.com/image.jpeg")
        #expect(image.size != .zero)
    }

    @Test func loadWithInvalidURL() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }

        // When
        for _ in 0...10 {
            do {
                _ = try await pipeline.image(for: ImageRequest(url: URL(string: "")))
                Issue.record("Unexpected success")
            } catch {
                // Expected
            }
        }
    }

#if !os(macOS)
    @Test func overridingImageScale() async throws {
        // Given
        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7])

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.scale == 7)
    }

    @Test func overridingImageScaleWithFloat() async throws {
        // Given
        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7.0])

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.scale == 7)
    }
#endif
}

/// We have to mock it because there is no way to construct native `URLError`
/// with a `networkUnavailableReason`.
private struct URLError: Swift.Error {
    var networkUnavailableReason: NetworkUnavailableReason?

    enum NetworkUnavailableReason {
        case cellular
        case expensive
        case constrained
    }
}
