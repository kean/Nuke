// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineAsyncAwaitTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline
    let pipelineDelegate: ImagePipelineObserver

    init() {
        let dataLoader = MockDataLoader()
        let pipelineDelegate = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.pipelineDelegate = pipelineDelegate
        self.pipeline = ImagePipeline(delegate: pipelineDelegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Basics

    @Test func imageIsLoaded() async throws {
        // WHEN
        let image = try await pipeline.image(for: Test.request)

        // THEN
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    // MARK: - Task-based API

    @Test func taskBasedImageResponse() async throws {
        // GIVEN
        let task = pipeline.imageTask(with: Test.request)

        // WHEN
        let response = try await task.response

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(task.status.result?.isSuccess == true)
    }

    @Test func taskBasedImage() async throws {
        // GIVEN
        let task = pipeline.imageTask(with: Test.request)

        // WHEN
        let image = try await task.image

        // THEN
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    // MARK: - Cancellation

    @Test func cancellation() async throws {
        dataLoader.queue.isSuspended = true

        // Observe before starting: the notification is posted from `loadData`,
        // and a run that registers too late never cancels the task, which then
        // never finishes – the data loading queue stays suspended.
        let didStartLoading = TestExpectation()
        let observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: OperationQueue()) { _ in
            didStartLoading.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let pipeline = self.pipeline
        let task = Task {
            try await pipeline.image(for: Test.url)
        }
        await didStartLoading.wait()
        task.cancel()

        var caughtError: ImagePipeline.Error?
        do {
            _ = try await task.value
        } catch let error as ImagePipeline.Error {
            caughtError = error
        }
        #expect(caughtError == .cancelled)
    }

    @Test func cancelFromTaskCreated() async throws {
        dataLoader.queue.isSuspended = true
        pipelineDelegate.onTaskCreated = { $0.cancel() }

        let pipeline = self.pipeline
        let task = Task {
            try await pipeline.image(for: Test.url)
        }

        var caughtError: ImagePipeline.Error?
        do {
            _ = try await task.value
        } catch let error as ImagePipeline.Error {
            caughtError = error
        }
        #expect(caughtError == .cancelled)
    }

    @Test func cancelImmediately() async throws {
        dataLoader.queue.isSuspended = true

        let pipeline = self.pipeline
        let task = Task {
            try await pipeline.image(for: Test.url)
        }
        task.cancel()

        var caughtError: ImagePipeline.Error?
        do {
            _ = try await task.value
        } catch let error as ImagePipeline.Error {
            caughtError = error
        }
        #expect(caughtError == .cancelled)
    }

    @Test func cancelFromProgress() async throws {
        dataLoader.queue.isSuspended = true

        nonisolated(unsafe) var recordedProgress: [ImageTask.Progress] = []
        let pipeline = self.pipeline
        let task = Task { @Sendable in
            let task = pipeline.imageTask(with: Test.url)
            for await value in task.progress {
                recordedProgress.append(value)
            }
        }

        task.cancel()

        _ = await task.value

        // THEN nothing is recorded because the task is cancelled and
        // stop observing the events
        #expect(recordedProgress == [])
    }

    @Test func observeProgressAndCancelFromOtherTask() async throws {
        dataLoader.queue.isSuspended = true

        nonisolated(unsafe) var recordedProgress: [ImageTask.Progress] = []
        let task = pipeline.imageTask(with: Test.url)

        let task1 = Task { @Sendable in
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
        var caughtError: ImagePipeline.Error?
        do {
            _ = try await (result1, result2)
        } catch let error as ImagePipeline.Error {
            caughtError = error
        }
        #expect(caughtError == .cancelled)
        #expect(recordedProgress == [])
    }

    @Test func cancelAsyncImageTask() async throws {
        dataLoader.queue.isSuspended = true

        // Observe before starting – see `cancellation()`.
        let didStartLoading = TestExpectation()
        let observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: OperationQueue()) { _ in
            didStartLoading.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let task = pipeline.imageTask(with: Test.url)
        await didStartLoading.wait()
        task.cancel()
        dataLoader.queue.isSuspended = false

        var caughtError: ImagePipeline.Error?
        do {
            _ = try await task.image
        } catch {
            caughtError = error
        }
        #expect(caughtError == .cancelled)
        #expect(task.isCancelled)
    }

    // MARK: - Load Data

    @Test func loadData() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success((Test.data, Test.urlResponse))

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(data.count == Test.data.count)
        #expect(response?.url != nil)
    }

    @Test func loadDataCancelImmediately() async throws {
        dataLoader.queue.isSuspended = true

        let pipeline = self.pipeline
        let task = Task {
            try await pipeline.data(for: Test.request)
        }
        task.cancel()

        var caughtError: ImagePipeline.Error?
        do {
            _ = try await task.value
        } catch let error as ImagePipeline.Error {
            caughtError = error
        }
        #expect(caughtError == .cancelled)
    }

    @Test func imageTaskReturnedImmediately() async throws {
        // GIVEN
        nonisolated(unsafe) var imageTask: ImageTask?
        pipelineDelegate.onTaskCreated = { imageTask = $0 }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(imageTask != nil)
    }

    // MARK: - Running on the Caller's Task

    @Test func taskCreatedByImageForCanBeAwaitedByOthers() async throws {
        // GIVEN an observer awaiting the task that `image(for:)` runs on the
        // caller's own Swift task
        nonisolated(unsafe) var imageTask: ImageTask?
        nonisolated(unsafe) var observer: Task<ImageResponse, any Error>?
        pipelineDelegate.onTaskCreated = { task in
            imageTask = task
            observer = Task { try await task.response }
        }

        // WHEN
        let image = try await pipeline.image(for: Test.request)

        // THEN the observer gets the same response
        let observerTask = try #require(observer)
        let response = try await observerTask.value
        #expect(response.image === image)
        #expect(try #require(imageTask)._task == nil)
    }

    @Test func cancellingAnotherAwaiterCancelsTaskCreatedByImageFor() async throws {
        // GIVEN a request that doesn't finish on its own, and an observer
        // awaiting the task that `image(for:)` runs
        dataLoader.queue.isSuspended = true
        let didCreateObserver = TestExpectation()
        nonisolated(unsafe) var observer: Task<ImageResponse, any Error>?
        pipelineDelegate.onTaskCreated = { task in
            observer = Task { try await task.response }
            didCreateObserver.fulfill()
        }
        let pipeline = self.pipeline
        let caller = Task {
            try await pipeline.image(for: Test.url)
        }
        await didCreateObserver.wait()
        let observerTask = try #require(observer)

        // WHEN
        observerTask.cancel()

        // THEN the task is cancelled for everyone awaiting it
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await caller.value
        }
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await observerTask.value
        }
    }

    @Test func imageForStartsTaskInTaskWhileAnotherCallerRunsOne() async throws {
        // GIVEN a caller that runs its task on its own Swift task and waits
        // for the data loader
        dataLoader.queue.isSuspended = true
        let didStartLoading = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let didCreateSecondTask = TestExpectation()
        nonisolated(unsafe) var tasks: [ImageTask] = []
        pipelineDelegate.onTaskCreated = { task in
            tasks.append(task)
            if tasks.count == 2 { didCreateSecondTask.fulfill() }
        }
        let pipeline = self.pipeline
        let first = Task {
            try await pipeline.image(for: Test.url)
        }
        await didStartLoading.wait()

        // WHEN another caller loads the image at the same time and is cancelled
        let second = Task {
            try await pipeline.image(for: Test.url)
        }
        await didCreateSecondTask.wait()
        second.cancel()

        // THEN the second task gets a `Task` of its own and is cancelled,
        // and the first one still finishes
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await second.value
        }
        dataLoader.queue.isSuspended = false
        _ = try await first.value
        #expect(tasks.count == 2)
        #expect(tasks.first?._task == nil)
        #expect(tasks.last?._task != nil)
    }

    @Test func imageForStartsTaskInTaskWhenCallerIsAlreadyCancelled() async throws {
        // GIVEN a caller that is cancelled before it asks for the image
        let pipeline = self.pipeline
        nonisolated(unsafe) var isStartCancelled: Bool?
        pipeline.onTaskStarted = { _ in isStartCancelled = Task.isCancelled }
        nonisolated(unsafe) var imageTask: ImageTask?
        pipelineDelegate.onTaskCreated = { imageTask = $0 }

        // WHEN
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.image(for: Test.request)
        }
        _ = try? await caller.value

        // THEN the task starts in a `Task` of its own, not on the cancelled one
        #expect(isStartCancelled == false)
        #expect(try #require(imageTask)._task != nil)
    }

    @Test func imageForRunsTaskOnCallersTaskAgainAfterCancellation() async throws {
        // GIVEN a caller that was cancelled
        dataLoader.queue.isSuspended = true
        let pipeline = self.pipeline
        let cancelled = Task {
            try await pipeline.image(for: Test.url)
        }
        cancelled.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await cancelled.value
        }
        dataLoader.queue.isSuspended = false

        // WHEN
        nonisolated(unsafe) var imageTask: ImageTask?
        pipelineDelegate.onTaskCreated = { imageTask = $0 }
        _ = try await pipeline.image(for: Test.request)

        // THEN the next request runs on its caller's task too
        #expect(try #require(imageTask)._task == nil)
    }

    @Test func imageForStartsTaskWithCallersPriority() async throws {
        // GIVEN
        let pipeline = self.pipeline
        nonisolated(unsafe) var startPriority: _Concurrency.TaskPriority?
        pipeline.onTaskStarted = { _ in startPriority = Task.currentPriority }

        // WHEN a utility task loads an image, resumed through a continuation
        // so that nothing escalates it
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                _ = try? await pipeline.image(for: Test.request)
                continuation.resume()
            }
        }

        // THEN
        #expect(startPriority == _Concurrency.TaskPriority.utility)
    }

    @Test func progressUpdated() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // WHEN
        var recordedProgress: [ImageTask.Progress] = []
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
        #expect(recordedProgress == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }

    @Test func thatProgressivePreviewsAreDelivered() async throws {
        // GIVEN
        let dataLoader = MockProgressiveDataLoader()
        dataLoader.servesFirstChunkAutomatically = false
        let pipeline = pipeline.reconfigured {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // WHEN
        var recordedPreviews: [ImageResponse] = []
        let task = pipeline.imageTask(with: Test.url)
        let stream = await task.subscribedPreviews()
        dataLoader.resume()
        for try await preview in stream {
            recordedPreviews.append(preview)
            dataLoader.resume()
        }
        let response = try await task.response

        // THEN
        #expect(!response.container.isPreview)
        #expect(recordedPreviews.count == 2)
        #expect(recordedPreviews.allSatisfy { $0.container.isPreview })
    }

    // MARK: - Update Priority

    @Test @ImagePipelineActor func updatePriority() async throws {
        // GIVEN
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        let expectation = TestExpectation(queue: queue, count: 1)
        let imageTask = pipeline.imageTask(with: request)
        Task.detached { try await imageTask.response }
        await expectation.wait()

        // WHEN/THEN
        let operation = try #require(expectation.operations.first)
        await queue.waitForPriorityChange(of: operation, to: .high) {
            imageTask.priority = .high
        }
    }

    // MARK: - ImageRequest with Async/Await (image container)

    @Test func imageRequestWithAsyncImageSuccess() async throws {
        // GIVEN
        let image = PlatformImage(data: Test.data)!
        let container = ImageContainer(image: image)

        // WHEN
        let request = ImageRequest(id: "test", image: { container })
        let result = try await pipeline.image(for: request)

        // THEN
        #expect(result.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func imageRequestWithAsyncImageFailure() async throws {
        // WHEN
        let request = ImageRequest(id: "test", image: {
            throw Foundation.URLError(.cancelled)
        })

        do {
            _ = try await pipeline.image(for: request)
            Issue.record("Expected failure")
        } catch {
            if case let .dataLoadingFailed(error) = error {
                #expect((error as? Foundation.URLError)?.code == .cancelled)
            } else {
                Issue.record("Unexpected error type")
            }
        }
    }

    @Test func imageRequestWithAsyncImageProcessorsApplied() async throws {
        // GIVEN
        let image = try #require(PlatformImage(data: Test.data))
        let container = ImageContainer(image: image)

        // WHEN
        let request = ImageRequest(
            id: "test",
            image: { container },
            processors: [.resize(size: CGSize(width: 160, height: 120), unit: .pixels)]
        )
        let result = try await pipeline.image(for: request)

        // THEN - image is resized (original is 640x480)
        #expect(result.sizeInPixels == CGSize(width: 160, height: 120))
    }

    // MARK: - ImageRequest with Async/Await

    @Test func imageRequestWithAsyncAwaitSuccess() async throws {
        // GIVEN
        let localURL = Test.url(forResource: "fixture", extension: "jpeg")

        // WHEN
        let request = ImageRequest(id: "test", data: {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: localURL))
            return data
        })

        let image = try await pipeline.image(for: request)

        // THEN
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func imageRequestWithAsyncAwaitFailure() async throws {
        // WHEN
        let request = ImageRequest(id: "test", data: {
            throw URLError(networkUnavailableReason: .cellular)
        })

        do {
            _ = try await pipeline.image(for: request)
            Issue.record("Expected failure")
        } catch {
            if case let .dataLoadingFailed(error) = error {
                #expect((error as? URLError)?.networkUnavailableReason == .cellular)
            } else {
                Issue.record("Unexpected error type")
            }
        }
    }

    @Test func imageRequestWithAsyncAwaitReturningEmptyData() async throws {
        // WHEN
        let request = ImageRequest(id: "test", data: { Data() })

        // THEN
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.image(for: request)
        }
    }

    @Test func imageRequestWithAsyncAwaitSkippingDataLoadingQueue() async throws {
        // GIVEN a request that bypasses the data loading queue
        let request = ImageRequest(
            id: "test",
            data: { Test.data },
            options: [.skipDataLoadingQueue]
        )

        // WHEN
        let image = try await pipeline.image(for: request)

        // THEN
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func imageRequestWithAsyncAwaitSkippingDataLoadingQueueIsCancellable() async throws {
        // GIVEN a fetch closure that doesn't finish on its own
        let entered = TestExpectation()
        let proceed = AsyncGate()
        let request = ImageRequest(
            id: "test",
            data: {
                entered.fulfill()
                await proceed.wait()
                return Test.data
            },
            options: [.skipDataLoadingQueue]
        )

        // WHEN the task is cancelled while the closure is in flight
        let task = pipeline.imageTask(with: request)
        await entered.wait()
        task.cancel()

        // THEN
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        proceed.open()
    }

    // MARK: Common Use Cases

    @Test func lowDataMode() async throws {
        // GIVEN
        let highQualityImageURL = URL(string: "https://example.com/high-quality-image.jpeg")!
        let lowQualityImageURL = URL(string: "https://example.com/low-quality-image.jpeg")!

        dataLoader.results[highQualityImageURL] = .failure(URLError(networkUnavailableReason: .constrained) as NSError)
        dataLoader.results[lowQualityImageURL] = .success((Test.data, Test.urlResponse))

        let pipeline = self.pipeline

        // Create the default request to fetch the high quality image.
        var urlRequest = URLRequest(url: highQualityImageURL)
        urlRequest.allowsConstrainedNetworkAccess = false
        let request = ImageRequest(urlRequest: urlRequest)

        // WHEN
        @Sendable func loadImage() async throws(ImagePipeline.Error) -> PlatformImage {
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
        // GIVEN
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = pipeline.reconfigured {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // WHEN
        var recordedPreviews: [ImageResponse] = []
        var recordedResult: Result<ImageResponse, ImagePipeline.Error>?
        var recordedEvents: [ImageTask.Event] = []

        let task = pipeline.imageTask(with: Test.request)
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
        try #require(recordedPreviews.count == 2, "Unexpected number of previews")

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

// MARK: - ImageTask State

@Suite(.timeLimit(.minutes(5)))
struct ImageTaskStatusTests {
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

    @Test func statusIsEmptyWhileInFlight() async throws {
        dataLoader.queue.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)
        Task.detached { try? await task.response }

        await notification(MockDataLoader.DidStartTask, object: dataLoader) {}

        #expect(task.status.result == nil)
        #expect(!task.status.isCancelled)
        dataLoader.queue.isSuspended = false
        _ = try await task.response
    }

    @Test func statusRecordsTheSuccess() async throws {
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response
        #expect(task.status.result?.isSuccess == true)
    }

    @Test func statusRecordsTheCancellation() async throws {
        dataLoader.queue.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)
        Task.detached { try? await task.response }
        await notification(MockDataLoader.DidStartTask, object: dataLoader) {}
        task.cancel()
        await notification(MockDataLoader.DidCancelTask, object: dataLoader) {}

        // `DidCancelTask` is posted from the data loader queue while the
        // pipeline is still on its way to recording the outcome, so wait for
        // the task itself to finish before reading the result.
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        #expect(task.status.isCancelled)
        #expect(task.status.result?.error == .cancelled)
    }

    @Test func statusRecordsTheFailure() async throws {
        dataLoader.results[Test.url] = .failure(Foundation.URLError(.notConnectedToInternet) as NSError)
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response
        #expect(task.status.result?.isSuccess == false)
        #expect(!task.status.isCancelled)
    }
}

// MARK: - ImageTask.Progress

@Suite(.timeLimit(.minutes(5)))
struct ImageTaskProgressTests {

    @Test func fractionIsZeroWhenTotalIsZero() {
        let progress = ImageTask.Progress(completed: 0, total: 0)
        #expect(progress.fraction == 0)
    }

    @Test func fractionIsCorrect() {
        let progress = ImageTask.Progress(completed: 50, total: 100)
        #expect(abs(progress.fraction - 0.5) < 0.001)
    }

    @Test func fractionIsClampedToOne() {
        // completed > total can happen due to rounding; fraction must not exceed 1
        let progress = ImageTask.Progress(completed: 150, total: 100)
        #expect(progress.fraction == 1)
    }

    @Test func fractionIsOneWhenComplete() {
        let progress = ImageTask.Progress(completed: 1000, total: 1000)
        #expect(progress.fraction == 1)
    }

    @Test func progressEquality() {
        let a = ImageTask.Progress(completed: 50, total: 100)
        let b = ImageTask.Progress(completed: 50, total: 100)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func progressInequality() {
        let a = ImageTask.Progress(completed: 50, total: 100)
        let b = ImageTask.Progress(completed: 60, total: 100)
        let c = ImageTask.Progress(completed: 50, total: 200)
        #expect(a != b)
        #expect(a != c)
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
