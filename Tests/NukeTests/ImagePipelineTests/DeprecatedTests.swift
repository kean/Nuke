// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct DeprecationTests {
    private let pipeline: ImagePipeline
    private let dataLoader: MockDataLoader

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - loadImage

    @Test func loadImageWithURL() async {
        dataLoader.isSuspended = true
        let result: Result<ImageResponse, ImagePipeline.Error> = await withCheckedContinuation { continuation in
            pipeline.loadImage(with: Test.url) { result in
                continuation.resume(returning: result)
            }
            dataLoader.isSuspended = false
        }
        #expect(result.isSuccess)
    }

    @Test func loadImageWithRequest() async {
        dataLoader.isSuspended = true
        let taskRef = Ref<ImageTask?>(nil)
        let resultInsideCallback = Ref<Result<ImageResponse, ImagePipeline.Error>?>(nil)
        let result: Result<ImageResponse, ImagePipeline.Error> = await withCheckedContinuation { continuation in
            taskRef.value = pipeline.loadImage(with: Test.request) { result in
                resultInsideCallback.value = taskRef.value!.status.result
                continuation.resume(returning: result)
            }
            dataLoader.isSuspended = false
        }
        #expect(result.isSuccess)
        #expect(resultInsideCallback.value?.isSuccess == true)
    }

    @Test func loadImageCompletionOnMainThread() async {
        dataLoader.isSuspended = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadImage(with: Test.request) { _ in
                #expect(Thread.isMainThread)
                continuation.resume()
            }
            dataLoader.isSuspended = false
        }
    }

    @Test func loadImageProgress() async {
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let progressValues = Ref<[(Int64, Int64)]>([])
        dataLoader.isSuspended = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadImage(
                with: Test.request,
                progress: { _, completed, total in
                    #expect(Thread.isMainThread)
                    progressValues.value.append((completed, total))
                },
                completion: { _ in continuation.resume() }
            )
            dataLoader.isSuspended = false
        }
        #expect(progressValues.value.count == 2)
        #expect(progressValues.value[0] == (10, 20))
        #expect(progressValues.value[1] == (20, 20))
    }

    @Test func loadImageProgressReportsPreviews() async {
        // Given
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = dataLoader.makePipeline()

        // When
        let previews = Ref<[(response: ImageResponse, completed: Int64)]>([])
        let result: Result<ImageResponse, ImagePipeline.Error> = await withCheckedContinuation { continuation in
            pipeline.loadImage(
                with: Test.request,
                progress: { response, completed, _ in
                    #expect(Thread.isMainThread)
                    guard let response else { return }
                    previews.value.append((response, completed))
                    dataLoader.resume() // Serve the next chunk
                },
                completion: { continuation.resume(returning: $0) }
            )
        }

        // Then the previews arrive through the progress closure, along with
        // the progress at the time they are delivered
        #expect(result.value?.container.isPreview == false)
        #expect(previews.value.count == 2)
        #expect(previews.value.allSatisfy { $0.response.container.isPreview })
        #expect(previews.value.allSatisfy { $0.completed > 0 })
    }

    /// Unlike a cancellation requested by the caller, the one caused by the
    /// invalidation of the pipeline is reported: nobody else would tell the
    /// caller that the request is over.
    @Test func loadImageReportsTheCancellationCausedByInvalidation() async {
        // Given
        dataLoader.isSuspended = true
        let didStartLoading = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let pipeline = self.pipeline

        // When
        let result: Result<ImageResponse, ImagePipeline.Error> = await withCheckedContinuation { continuation in
            pipeline.loadImage(with: Test.request) { continuation.resume(returning: $0) }
            Task {
                await didStartLoading.wait()
                pipeline.invalidate()
            }
        }

        // Then
        #expect(result.error == .cancelled)
    }

    @Test func loadImageCancellation() async {
        dataLoader.isSuspended = true
        let task = await withCheckedContinuation { (continuation: CheckedContinuation<ImageTask, Never>) in
            let task = pipeline.loadImage(with: Test.request) { _ in
                Issue.record("Should not be called")
            }
            Task { @ImagePipelineActor in
                task.cancel()
                continuation.resume(returning: task)
            }
        }
        #expect(task.isCancelled)
    }

    @Test func loadImageCancellationCompletionNotCalled() async {
        dataLoader.isSuspended = true
        let completionCalled = Ref(false)
        let task = pipeline.loadImage(with: Test.request) { _ in
            completionCalled.value = true
        }
        task.cancel()
        // Wait for the pipeline actor to process cancellation and dispatch events
        await drainPipeline()
        // Simulate data arriving after cancellation
        dataLoader.isSuspended = false
        // Flush any DispatchQueue.main.async callbacks
        await MainActor.run {}
        #expect(!completionCalled.value)
        #expect(task.isCancelled)
    }

    // MARK: - loadData

    @Test func loadData() async {
        dataLoader.isSuspended = true
        let result: Result<(data: Data, response: URLResponse?), ImagePipeline.Error> = await withCheckedContinuation { continuation in
            pipeline.loadData(with: Test.request) { result in
                continuation.resume(returning: result)
            }
            dataLoader.isSuspended = false
        }
        #expect((try? result.get().data.count) == 22789)
    }

    @Test func loadDataCompletionOnMainThread() async {
        dataLoader.isSuspended = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadData(with: Test.request) { _ in
                #expect(Thread.isMainThread)
                continuation.resume()
            }
            dataLoader.isSuspended = false
        }
    }

    @Test func loadDataProgress() async {
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let progressValues = Ref<[(Int64, Int64)]>([])
        dataLoader.isSuspended = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadData(
                with: Test.request,
                progress: { completed, total in
                    #expect(Thread.isMainThread)
                    progressValues.value.append((completed, total))
                },
                completion: { _ in continuation.resume() }
            )
            dataLoader.isSuspended = false
        }
        #expect(progressValues.value.count == 2)
        #expect(progressValues.value[0] == (10, 20))
        #expect(progressValues.value[1] == (20, 20))
    }
}

/// `ImageTask.state` is no longer stored – it is derived from `status`. These
/// tests pin the mapping to what the stored property used to report.
///
/// Each test is deprecated along with the property it reads, which is what
/// keeps the compiler quiet: the attribute has to go on the tests rather than
/// on the suite, which swift-testing refuses to mark deprecated.
@Suite(.timeLimit(.minutes(5)))
struct DeprecatedImageTaskStateTests {
    private let pipeline: ImagePipeline
    private let dataLoader: MockDataLoader

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @available(*, deprecated)
    @Test func stateIsRunningWhileInFlight() {
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        #expect(task.state == .running)
        task.cancel()
    }

    @available(*, deprecated)
    @Test func stateIsCancelledAsSoonAsCancelIsCalled() {
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        task.cancel()

        // Reads as `.cancelled` whether or not the pipeline has processed the
        // cancellation yet, matching the old stored state, which flipped
        // synchronously inside `cancel()`.
        #expect(task.state == .cancelled)
    }

    @available(*, deprecated)
    @Test func stateIsCancelledAfterThePipelineProcessesTheCancellation() async throws {
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }

        #expect(task.state == .cancelled)
    }

    @available(*, deprecated)
    @Test func stateIsCompletedAfterSuccess() async throws {
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        #expect(task.state == .completed)
    }

    @available(*, deprecated)
    @Test func stateIsCompletedWhenTheTaskFails() async throws {
        dataLoader.results[Test.url] = .failure(Foundation.URLError(.notConnectedToInternet) as NSError)
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response

        #expect(task.state == .completed)
    }

    @available(*, deprecated)
    @Test func stateStaysCompletedWhenAFinishedTaskIsCancelled() async throws {
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // Cancelling after the fact records the request but must not rewrite
        // the outcome, which is what the stored state used to guarantee.
        task.cancel()

        #expect(task.isCancelled)
        #expect(task.state == .completed)
    }
}

@Suite(.timeLimit(.minutes(5)))
struct DeprecatedImageTaskProgressTests {
    private let pipeline: ImagePipeline
    private let dataLoader: MockDataLoader

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @available(*, deprecated)
    @Test func currentProgressMatchesTheStatus() async throws {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)
        #expect(task.currentProgress == ImageTask.Progress(completed: 0, total: 0))

        // When
        dataLoader.isSuspended = false
        _ = try await task.response

        // Then
        #expect(task.currentProgress == task.status.progress)
        #expect(task.currentProgress.fraction == 1)
    }
}

/// The deprecated names forward to the new ones, including the side effects.
@Suite(.timeLimit(.minutes(5))) @ImagePipelineActor
struct DeprecatedTaskQueueTests {
    @available(*, deprecated)
    @Test func initializerSetsTheLimit() {
        let queue = TaskQueue(maxConcurrentOperationCount: 3)
        #expect(queue.maxConcurrentTaskCount == 3)
        #expect(queue.maxConcurrentOperationCount == 3)
    }

    @available(*, deprecated)
    @Test func raisingTheLimitStartsPendingWork() async {
        // Given
        let queue = TaskQueue(maxConcurrentOperationCount: 0)
        let didRun = TestExpectation()
        queue.add { didRun.fulfill() }

        // When
        queue.maxConcurrentOperationCount = 1

        // Then
        #expect(queue.maxConcurrentTaskCount == 1)
        await didRun.wait()
    }
}
