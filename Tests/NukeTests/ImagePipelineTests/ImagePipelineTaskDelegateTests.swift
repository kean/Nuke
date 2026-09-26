// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineTaskDelegateTests {
    private let dataLoader: MockDataLoader
    private let pipeline: ImagePipeline
    private let delegate: ImagePipelineObserver

    init() {
        let dataLoader = MockDataLoader()
        let delegate = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.delegate = delegate
        self.pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func startAndCompletedEvents() async throws {
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: delegate)
        let response = try await pipeline.imageTask(with: Test.request).response
        await completed.wait()

        // Then
        #expect(delegate.events == [
            ImageTaskEvent.created,
            .started,
            .progressUpdated(completedUnitCount: 22789, totalUnitCount: 22789),
            .completed(result: .success(response))
        ])
    }

    @Test func startIsReportedThroughTheDedicatedDelegateMethod() async throws {
        // WHEN
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: delegate)
        let task = pipeline.imageTask(with: Test.request)
        var events: [ImageTask.Event] = []
        for await event in task.events {
            events.append(event)
        }
        await completed.wait()

        // THEN the start is reported to `imageTaskDidStart` before any of the
        // events observed by the task stream
        #expect(delegate.startedTaskCount == 1)
        #expect(Array(delegate.events.prefix(2)) == [ImageTaskEvent.created, .started])
        #expect(events.count == delegate.events.count - 2)
    }

    /// Documented: unlike the other task events, `imageTaskCreated` is called
    /// immediately, in the context that created the task.
    @Test @MainActor func taskCreationIsReportedSynchronouslyOnTheCallingThread() async throws {
        // GIVEN
        dataLoader.isSuspended = true
        var created: [(task: ImageTask, isMainThread: Bool)] = []
        delegate.onTaskCreated = { created.append(($0, Thread.isMainThread)) }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)

        // THEN it was reported before `imageTask(with:)` returned
        #expect(created.count == 1)
        #expect(created.first?.task === task)
        #expect(created.first?.isMainThread == true)
        task.cancel()
    }

    /// The task is reported before the pipeline starts it, but it is already
    /// wired: the delegate can await its response.
    @Test func taskIsWiredWhenItsCreationIsReported() async throws {
        // GIVEN
        let wasWired = Ref<Bool?>(nil)
        delegate.onTaskCreated = { wasWired.value = $0._task != nil }

        // WHEN
        _ = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(wasWired.value == true)
    }

    /// A delegate that observes the outcome of every task from `imageTaskCreated`,
    /// e.g. for logging, with the observer getting to the task while the
    /// delegate is still running.
    @Test func awaitingTheResponseFromImageTaskCreatedDoesNotCrash() async throws {
        // GIVEN
        let observed = TestExpectation()
        delegate.onTaskCreated = { task in
            let didStart = DispatchSemaphore(value: 0)
            Task.detached {
                didStart.signal()
                _ = try? await task.response
                observed.fulfill()
            }
            didStart.wait()
            Thread.sleep(forTimeInterval: 0.25) // Some synchronous work in the delegate
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response
        await observed.wait()

        // THEN
        #expect(task.status.result?.isSuccess == true)
        #expect(delegate.events.prefix(2) == [.created, .started])
    }

    @Test func dataTasksAreNotReportedToTheDelegate() async throws {
        // WHEN
        _ = try await pipeline.data(for: Test.request)

        // THEN
        #expect(delegate.events.isEmpty)
        #expect(delegate.startedTaskCount == 0)

        // WHEN an image task is started after it
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: delegate)
        _ = try await pipeline.image(for: Test.request)
        await completed.wait()

        // THEN only the image task is reported
        #expect(delegate.startedTaskCount == 1)
        #expect(delegate.completedTaskCount == 1)
        #expect(delegate.events.filter { $0 == .created }.count == 1)
    }

    @Test func progressUpdateEvents() async throws {
        let request = ImageRequest(url: Test.url)
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: delegate)
        var result: Result<ImageResponse, ImagePipeline.Error>?
        do {
            let response = try await pipeline.imageTask(with: request).response
            result = .success(response)
        } catch {
            result = .failure(error)
        }
        await completed.wait()

        // Then
        #expect(delegate.events == [
            ImageTaskEvent.created,
            .started,
            .progressUpdated(completedUnitCount: 10, totalUnitCount: 20),
            .progressUpdated(completedUnitCount: 20, totalUnitCount: 20),
            .completed(result: try #require(result))
        ])
    }

    @Test func cancellationEvents() async {
        dataLoader.queue.isSuspended = true

        let startExpectation = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        Task.detached { try? await task.response }
        await startExpectation.wait()

        await notification(ImagePipelineObserver.didCancelTask, object: delegate) {
            task.cancel()
        }
        await Task.yield()

        // Then
        #expect(delegate.events == [
            ImageTaskEvent.created,
            .started,
            .cancelled
        ])
    }

    @Test func errorCompletionEventDelivered() async throws {
        // GIVEN a data loader that fails
        let error = URLError(.notConnectedToInternet)
        dataLoader.results[Test.url] = .failure(error as NSError)

        // WHEN
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: delegate)
        _ = try? await pipeline.imageTask(with: Test.request).response
        await completed.wait()

        // THEN the delegate receives a completed(.failure(...)) event
        let events = delegate.events
        guard case .completed(let result) = events.last else {
            Issue.record("Expected completed event, got \(events)")
            return
        }
        if case .success = result {
            Issue.record("Expected failure result")
        }
    }

    @Test func intermediateResponseEventsDelivered() async throws {
        // GIVEN a pipeline with progressive decoding
        let dataLoader = MockProgressiveDataLoader()
        dataLoader.servesFirstChunkAutomatically = false
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.url)
        let stream = task.previews
        dataLoader.resume()
        for try await _ in stream {
            dataLoader.resume()
        }
        _ = try await task.response

        // THEN intermediate response events are recorded
        let previews = delegate.events.filter {
            if case .intermediateResponseReceived = $0 { return true }
            return false
        }
        #expect(previews.count >= 1)
    }
}
