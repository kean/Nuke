// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineAsyncAwaitTests: XCTestCase, @unchecked Sendable {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    private var recordedEvents: [ImageTask.Event] = []
    private var recordedResult: Result<ImageResponse, ImagePipeline.Error>?
    private var recordedProgress: [ImageTask.Progress] = []
    private var recordedPreviews: [ImageResponse] = []
    private var pipelineDelegate = ImagePipelineObserver()
    private var imageTask: ImageTask?
    private let callbackQueue = DispatchQueue(label: "testChangingCallbackQueue")
    private let callbackQueueKey = DispatchSpecificKey<Void>()

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline(delegate: pipelineDelegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0._callbackQueue = callbackQueue
        }

        callbackQueue.setSpecific(key: callbackQueueKey, value: ())
    }

    // MARK: - Basics

    func testImageIsLoaded() async throws {
        // WHEN
        let image = try await pipeline.image(for: Test.request)

        // THEN
        XCTAssertEqual(image.sizeInPixels, CGSize(width: 640, height: 480))
    }

    // MARK: - Task-based API

    func testTaskBasedImageResponse() async throws {
        // GIVEN
        let task = pipeline.imageTask(with: Test.request)

        // WHEN
        let response = try await task.response

        // THEN
        XCTAssertEqual(response.image.sizeInPixels, CGSize(width: 640, height: 480))
    }

    func testTaskBasedImage() async throws {
        // GIVEN
        let task = pipeline.imageTask(with: Test.request)

        // WHEN
        let image = try await task.image

        // THEN
        XCTAssertEqual(image.sizeInPixels, CGSize(width: 640, height: 480))
    }

    private var observer: AnyObject?

    // MARK: - Cancellation

    func testCancellation() async throws {
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
        XCTAssertTrue(caughtError is CancellationError)
    }

    func testCancelFromTaskCreated() async throws {
        dataLoader.queue.isSuspended = true
        pipelineDelegate.onTaskCreated = { $0.cancel() }

        let task = Task {
            try await pipeline.image(for: Test.url)
        }

        var caughtError: Error?
        do {
            _ = try await task.value
        } catch {
            caughtError = error
        }
        XCTAssertTrue(caughtError is CancellationError)
    }

    func testCancelImmediately() async throws {
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
        XCTAssertTrue(caughtError is CancellationError)
    }

    func testCancelFromProgress() async throws {
        dataLoader.queue.isSuspended = true

        let task = Task {
            let task = pipeline.imageTask(with: Test.url)
            for await value in task.progress {
                recordedProgress.append(value)
            }
        }

        task.cancel()

        _ = await task.value

        // THEN nothing is recorded because the task is cancelled and
        // stop observing the events
        XCTAssertEqual(recordedProgress, [])
    }

    func testObserveProgressAndCancelFromOtherTask() async throws {
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

        // THEN you are able to observe `event` update because
        // this task does no get cancelled
        var caughtError: Error?
        do {
            _ = try await (result1, result2)
        } catch {
            caughtError = error
        }
        XCTAssertTrue(caughtError is CancellationError)
        XCTAssertEqual(recordedProgress, [])
    }

    #warning("reimplement")
//    func testCancelAsyncImageTask() async throws {
//        dataLoader.queue.isSuspended = true
//
//        pipeline.queue.suspend()
//        let task = pipeline.imageTask(with: Test.url)
//        observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: OperationQueue()) { _ in
//            task.cancel()
//        }
//        pipeline.queue.resume()
//
//        var caughtError: Error?
//        do {
//            _ = try await task.image
//        } catch {
//            caughtError = error
//        }
//        XCTAssertTrue(caughtError is CancellationError)
//    }

    // MARK: - Load Data

    func testLoadData() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success((Test.data, Test.urlResponse))

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        XCTAssertEqual(data.count, 22788)
        XCTAssertNotNil(response?.url, Test.url.absoluteString)
    }

    func testLoadDataCancelImmediately() async throws {
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
        XCTAssertTrue(caughtError is CancellationError)
    }

    func testImageTaskReturnedImmediately() async throws {
        // GIVEN
        pipelineDelegate.onTaskCreated = { [unowned self] in imageTask = $0 }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        XCTAssertNotNil(imageTask)
    }

    func testProgressUpdated() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // WHEN
        do {
            let task = pipeline.imageTask(with: Test.url)
            for await progress in task.progress {
                recordedProgress.append(progress)
            }
            _ = try await task.image
        } catch {
            // Do nothing
        }

        // THEN
        XCTAssertEqual(recordedProgress, [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }

    func testThatProgressivePreviewsAreDelivered() async throws {
        // GIVEN
        let dataLoader = MockProgressiveDataLoader()
        pipeline = pipeline.reconfigured {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.url)
        Task {
            for try await preview in task.previews {
                recordedPreviews.append(preview)
                dataLoader.resume()
            }
        }
        _ = try await task.image

        // THEN
        XCTAssertEqual(recordedPreviews.count, 2)
        XCTAssertTrue(recordedPreviews.allSatisfy { $0.container.isPreview })
    }

    // MARK: - Update Priority

    func testUpdatePriority() {
        // GIVEN
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        let observer = expect(queue).toEnqueueOperationsWithCount(1)
        let imageTask = pipeline.imageTask(with: request)

        Task.detached {
            try await imageTask.response
        }
        wait()

        // WHEN/THEN
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        imageTask.priority = .high
        wait()
    }

    // MARK: - ImageRequest with Async/Await

    func testImageRequestWithAsyncAwaitSuccess() async throws {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *) {
            // GIVEN
            let localURL = Test.url(forResource: "fixture", extension: "jpeg")

            // WHEN
            let request = ImageRequest(id: "test", data: {
                let (data, _) = try await URLSession.shared.data(for: URLRequest(url: localURL))
                return data
            })

            let image = try await pipeline.image(for: request)

            // THEN
            XCTAssertEqual(image.sizeInPixels, CGSize(width: 640, height: 480))
        }
    }

    func testImageRequestWithAsyncAwaitFailure() async throws {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *) {
            // WHEN
            let request = ImageRequest(id: "test", data: {
                throw URLError(networkUnavailableReason: .cellular)
            })

            do {
                _ = try await pipeline.image(for: request)
                XCTFail()
            } catch {
                if case let .dataLoadingFailed(error) = error as? ImagePipeline.Error {
                    XCTAssertEqual((error as? URLError)?.networkUnavailableReason, .cellular)
                } else {
                    XCTFail()
                }
            }
        }
    }

    // MARK: Common Use Cases

    func testLowDataMode() async throws {
        // GIVEN
        let highQualityImageURL = URL(string: "https://example.com/high-quality-image.jpeg")!
        let lowQualityImageURL = URL(string: "https://example.com/low-quality-image.jpeg")!

        dataLoader.results[highQualityImageURL] = .failure(URLError(networkUnavailableReason: .constrained) as NSError)
        dataLoader.results[lowQualityImageURL] = .success((Test.data, Test.urlResponse))

        // WHEN
        let pipeline = self.pipeline!

        // Create the default request to fetch the high quality image.
        var urlRequest = URLRequest(url: highQualityImageURL)
        urlRequest.allowsConstrainedNetworkAccess = false
        let request = ImageRequest(urlRequest: urlRequest)

        // WHEN
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
    func testImageTaskEvents() async {
        // GIVEN
        let dataLoader = MockProgressiveDataLoader()
        pipeline = pipeline.reconfigured {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
        }

        // WHEN
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

        // THEN
        guard recordedPreviews.count == 2 else {
            return XCTFail("Unexpected number of previews")
        }

        XCTAssertEqual(recordedEvents.filter {
            if case .progress = $0 {
                return false // There is guarantee if all will arrive
            }
            return true
        }, [
            .preview(recordedPreviews[0]),
            .preview(recordedPreviews[1]),
            .finished(try XCTUnwrap(recordedResult))
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

#if swift(>=6.0)
extension ImageTask.Event: @retroactive Equatable {
    public static func == (lhs: ImageTask.Event, rhs: ImageTask.Event) -> Bool {
        switch (lhs, rhs) {
        case let (.progress(lhs), .progress(rhs)):
            return lhs == rhs
        case let (.preview(lhs), .preview(rhs)):
            return lhs == rhs
        case (.cancelled, .cancelled):
            return true
        case let (.finished(lhs), .finished(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}
#else
extension ImageTask.Event: Equatable {
    public static func == (lhs: ImageTask.Event, rhs: ImageTask.Event) -> Bool {
        switch (lhs, rhs) {
        case let (.progress(lhs), .progress(rhs)):
            return lhs == rhs
        case let (.preview(lhs), .preview(rhs)):
            return lhs == rhs
        case (.cancelled, .cancelled):
            return true
        case let (.finished(lhs), .finished(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}
#endif
