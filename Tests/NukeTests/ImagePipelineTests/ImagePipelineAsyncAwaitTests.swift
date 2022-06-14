// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineAsyncAwaitTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    private var recordedProgress: [Progress] = []
    private var taskDelegate = AnonymousImateTaskDelegate()
    private var imageTask: ImageTask?
    private let callbackQueue = DispatchQueue(label: "testChangingCallbackQueue")
    private let callbackQueueKey = DispatchSpecificKey<Void>()

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.callbackQueue = callbackQueue
        }

        callbackQueue.setSpecific(key: callbackQueueKey, value: ())
    }

    // MARK: - Basics

    func testImageIsLoaded() async throws {
        // WHEN
        let response = try await pipeline.image(for: Test.request)

        // THEN
        XCTAssertEqual(response.image.sizeInPixels, CGSize(width: 640, height: 480))
    }

    private var observer: AnyObject?

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
            let _ = try await task.value
        } catch {
            caughtError = error
        }
        XCTAssertTrue(caughtError is CancellationError)
    }

    func testLoadData() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success((Test.data, Test.urlResponse))

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        XCTAssertEqual(data.count, 22788)
        XCTAssertNotNil(response?.url, Test.url.absoluteString)
    }

    // MARK: - ImageTaskDelegate

    func testImageTaskReturnedImmediately() async throws {
        // GIVEN
        taskDelegate.onWillStart = { [unowned self] in imageTask = $0 }

        // WHEN
        _ = try await pipeline.image(for: Test.request, delegate: taskDelegate)

        // THEN
        XCTAssertNotNil(imageTask)
    }

    func testImageTaskDelegateDidCancelIsCalled() async throws {
        // GIVEN
        dataLoader.queue.isSuspended = true
        taskDelegate.onWillStart = { [unowned self] in imageTask = $0 }

        observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: OperationQueue()) { [unowned self] _ in
            imageTask?.cancel()
        }

        // WHEN/THEN

        var isOnCancelCalled = false
        taskDelegate.onCancel = { [unowned self] in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: callbackQueueKey))
            isOnCancelCalled = true
        }

        do {
            _ = try await pipeline.image(for: Test.url, delegate: taskDelegate)
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertTrue(isOnCancelCalled)
    }

    

    // MARK: - Progress Monitoring

    // TODO: reimplement
//    func testMonitoringProgress() async throws {
//        // GIVEN
//        dataLoader.results[Test.url] = .success(
//            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
//        )
//
//        // WHEN
//        do {
//            try await pipeline.image(for: Test.request, progress: {
//                self.recordedProgress.append(Progress(completed: $0, total: $1))
//            })
//        } catch {
//            // Do nothing
//        }
//
//        // THEN
//        XCTAssertEqual(recordedProgress, [
//            Progress(completed: 10, total: 20),
//            Progress(completed: 20, total: 20),
//        ])
//    }

    // TODO: reimplement
//    func testMonitoringProgressLoadData() async throws {
//        // GIVEN
//        dataLoader.results[Test.url] = .success(
//            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
//        )
//
//        // WHEN
//        do {
//            try await pipeline.data(for: Test.request, progress: {
//                self.recordedProgress.append(Progress(completed: $0, total: $1))
//            })
//        } catch {
//            // Do nothing
//        }
//
//        // THEN
//        XCTAssertEqual(recordedProgress, [
//            Progress(completed: 10, total: 20),
//            Progress(completed: 20, total: 20),
//        ])
//    }

    // MARK: - Update Priority

    // TODO: reimplement
//    func testUpdatePriority() {
//        // GIVEN
//        let queue = pipeline.configuration.dataLoadingQueue
//        queue.isSuspended = true
//
//        let request = Test.request
//        XCTAssertEqual(request.priority, .normal)
//
//        let observer = expect(queue).toEnqueueOperationsWithCount(1)
//        let task = AsyncImageTask()
//        Task.detached {
//            try await self.pipeline.image(for: request, task: task)
//        }
//        wait()
//
//        // WHEN/THEN
//        guard let operation = observer.operations.first else {
//            return XCTFail("Failed to find operation")
//        }
//        expect(operation).toUpdatePriority()
//        task.setPriority(.high)
//        wait()
//    }

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

            let container = try await pipeline.image(for: request)

            // THEN
            XCTAssertEqual(container.image.sizeInPixels, CGSize(width: 640, height: 480))
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
        @Sendable func loadImage() async throws -> ImageResponse {
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

        let response = try await loadImage()
        XCTAssertNotNil(response.image)
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

private struct Progress: Equatable {
    let completed, total: Int64
}

private final class AnonymousImateTaskDelegate: ImageTaskDelegate {
    var onWillStart: ((ImageTask) -> Void)?

    func imageTaskWillStart(_ task: ImageTask) {
        onWillStart?(task)
    }

    var onProgress: ((_ completed: Int64, _ total: Int64) -> Void)?

    func imageTask(_ task: ImageTask, didUpdateProgress progress: (completed: Int64, total: Int64)) {
        onProgress?(progress.completed, progress.total)
    }

    var onProgressiveResponse: ((ImageResponse) -> Void)?

    func imageTask(_ task: ImageTask, didProduceProgressiveResponse response: ImageResponse) {
        onProgressiveResponse?(response)
    }

    var onCancel: (() -> Void)?

    func imageTaskDidCancel(_ task: ImageTask) {
        onCancel?()
    }

    var onResult: ((Result<ImageResponse, ImagePipeline.Error>) -> Void)?

    func imageTask(_ task: ImageTask, didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>) {
        onResult?(result)
    }

    var onDataResult: ((Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void)?

    func dataTask(_ task: ImageTask, didCompleteWithResult result: Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) {
        onDataResult?(result)
    }
}
