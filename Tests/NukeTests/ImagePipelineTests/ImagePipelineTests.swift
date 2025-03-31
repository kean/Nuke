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
    private var recordedResult: Result<ImageResponse, ImagePipeline.Error>?
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

        var caughtError: Error?
        do {
            _ = try await task.value
        } catch {
            caughtError = error
        }
        #expect(caughtError is CancellationError)
    }

    @Test func cancelImmediately() async throws {
        dataLoader.queue.isSuspended = true

        let task = Task {
            try await pipeline.image(for: Test.url)
        }
        task.cancel()

        var caughtError: Error?
        do {
            _ = try await task.value
        } catch {
            caughtError = error
        }
        #expect(caughtError is CancellationError)
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
        var caughtError: Error?
        do {
            _ = try await (result1, result2)
        } catch {
            caughtError = error
        }
        #expect(caughtError is CancellationError)
        #expect(recordedProgress == [])
    }

    @Test func cancelAsyncImageTask() async throws {
        dataLoader.queue.isSuspended = true

        let task = pipeline.imageTask(with: Test.url)
        observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: OperationQueue()) { _ in
            task.cancel()
        }

        var caughtError: Error?
        do {
            _ = try await task.image
        } catch {
            caughtError = error
        }
        #expect(caughtError is CancellationError)
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

        let expectation1 = queue.expectItemAdded()
        let request = Test.request
        let task = pipeline.loadImage(with: request) { _ in
            Issue.record()
        }
        let workItem = await expectation1.wait()

        // When
        let expectation2 = queue.expectItemCancelled(workItem)
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

        var caughtError: Error?
        do {
            _ = try await task.value
        } catch {
            caughtError = error
        }
        #expect(caughtError is CancellationError)
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

    @Test func thatProgressivePreviewsAreDelivered() async throws {
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

    // MARK: - Update Priority

    @Test func updatedDataLoadingQueuePriority() async {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        // When
        let expectation = queue.expectItemAdded()
        let imageTask = pipeline.imageTask(with: request)
        Task {
            try await imageTask.response
        }
        let workItem = await expectation.wait()

        // Then
        #expect(workItem.priority == .normal)

        let expectation2 = queue.expectPriorityUpdated(for: workItem)
        imageTask.priority = .high
        let newPriority = await expectation2.wait()

        #expect(newPriority == .high)
        #expect(workItem.priority == .high)
    }

    @Test func updateDecodingPriority() async {
        // Given
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
        }

        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        let expectation = queue.expectItemAdded()
        let task = pipeline.loadImage(with: request) { _ in }
        let workItem = await expectation.wait()

        // When
        let expectation2 = queue.expectPriorityUpdated(for: workItem)
        task.priority = .high

        // Then
        let newPriority = await expectation2.wait()
        #expect(newPriority == .high)
    }

    @Test func updateProcessingPriority() async {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])
        #expect(request.priority == .normal)

        let expectation = queue.expectItemAdded()
        let task = pipeline.loadImage(with: request) { _ in }
        let workItem = await expectation.wait()

        // When
        let expectation2 = queue.expectPriorityUpdated(for: workItem)
        task.priority = .high

        // Then
        let newPriority = await expectation2.wait()
        #expect(newPriority == .high)
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
            if case let .dataLoadingFailed(error) = error as? ImagePipeline.Error {
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
                guard let error = (error as? ImagePipeline.Error),
                      (error.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained else {
                    throw error
                }
                return try await pipeline.image(for: lowQualityImageURL)
            }
        }

        _ = try await loadImage()
    }

    // MARK: - ImageTask Integration

    @available(macOS 12, iOS 15, tvOS 15, watchOS 9, *)
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
