// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// What happens to the fetch of the original data (`TaskFetchOriginalData`)
/// before it reaches the data loader: the rate limiter and the data loading
/// queue, and the cancellation while it waits for either of them.
///
/// The tests drive the pipeline on its actor, so that the work they queue up
/// and the fetch they start are in the same turn, with nothing in between.
@Suite(.timeLimit(.minutes(5))) @ImagePipelineActor
struct ImagePipelineDataFetchSchedulingTests {
    private let dataLoader = MockDataLoader()

    // MARK: - Rate Limiter

    @Test func fetchCancelledWhileRateLimitedNeverReachesTheDataLoader() async throws {
        // GIVEN a fetch held by the rate limiter
        let pipeline = makePipeline()
        let limiter = try #require(pipeline.rateLimiter)
        exhaust(limiter)
        let subscription = subscribe(to: pipeline, Test.request)
        let isSubscribed = subscription._isPresent
        #expect(isSubscribed)

        // WHEN it is cancelled
        subscription?.unsubscribe()

        // THEN it doesn't start when the limiter lets it through
        await drain(limiter)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func fetchHeldByTheRateLimiterStartsWhenItsTurnComes() async throws {
        // GIVEN a fetch held by the rate limiter
        let pipeline = makePipeline()
        let limiter = try #require(pipeline.rateLimiter)
        exhaust(limiter)
        let finished = TestExpectation()
        let subscription = subscribe(to: pipeline, Test.request) {
            if case let .value(_, isCompleted) = $0, isCompleted { finished.fulfill() }
        }
        let isSubscribed = subscription._isPresent
        #expect(isSubscribed)
        #expect(dataLoader.createdTaskCount == 0)

        // WHEN/THEN
        await finished.wait()
        #expect(dataLoader.createdTaskCount == 1)
    }

    /// The rate limiter protects `URLSession`: the work that doesn't go
    /// through the data loader isn't held by it.
    @Test func closuresAndLocalResourcesAreNotRateLimited() async throws {
        // GIVEN a rate limiter that is out of tokens
        let pipeline = makePipeline()
        let limiter = try #require(pipeline.rateLimiter)
        exhaust(limiter)

        // WHEN
        var localEvents: [AsyncTask<(Data, URLResponse?), ImagePipeline.Error>.Event] = []
        let dataURL = try #require(URL(string: "data:image/jpeg;base64,\(Test.data.base64EncodedString())"))
        _ = subscribe(to: pipeline, ImageRequest(url: dataURL)) { localEvents.append($0) }
        let closure = subscribe(to: pipeline, ImageRequest(id: "closure", data: { Test.data }))

        // THEN the local resource is read in the same turn, and the closure
        // goes straight to the data loading queue
        #expect(localEvents.count == 1)
        if case let .value(value, isCompleted) = localEvents.first {
            #expect(value.0 == Test.data)
            #expect(isCompleted)
        } else {
            Issue.record("Expected the data, got \(localEvents)")
        }
        #expect(pipeline.configuration.dataLoadingQueue.operationCount == 1)
        closure?.unsubscribe()
    }

    /// With the rate limiter off, even more fetches than it lets through in
    /// a burst go to the data loading queue right away.
    @Test func fetchesWithoutTheRateLimiterStartImmediately() async throws {
        // GIVEN
        let pipeline = makePipeline { $0.isRateLimiterEnabled = false }
        #expect(pipeline.rateLimiter == nil)

        // WHEN more fetches start in one turn than the limiter's burst (25)
        for index in 0..<30 {
            let url = try #require(URL(string: "https://example.com/image-\(index).jpeg"))
            _ = subscribe(to: pipeline, ImageRequest(url: url))
        }

        // THEN all of them are in the data loading queue
        #expect(pipeline.configuration.dataLoadingQueue.operationCount == 30)
    }

    // MARK: - Skip Data Loading Queue

    /// With `.skipDataLoadingQueue`, the fetch runs in a `Task` of its own –
    /// cancelling the fetch before that task gets to run has to stop it.
    @Test func fetchSkippingTheQueueCancelledBeforeItRunsNeverReachesTheDataLoader() async throws {
        // GIVEN a fetch that skips the data loading queue
        let pipeline = makePipeline { $0.isRateLimiterEnabled = false }
        let request = ImageRequest(url: Test.url, options: [.skipDataLoadingQueue])
        let subscription = subscribe(to: pipeline, request)
        #expect(pipeline.configuration.dataLoadingQueue.operationCount == 0)

        // WHEN it's cancelled in the same turn
        subscription?.unsubscribe()

        // THEN
        await Task { @ImagePipelineActor in }.value
        await Task { @ImagePipelineActor in }.value
        #expect(dataLoader.createdTaskCount == 0)
    }

    /// A fetch that skips the queue doesn't join an equivalent fetch waiting
    /// in it: it gets a fetch of its own.
    @Test func fetchSkippingTheQueueDoesNotJoinAQueuedFetch() async throws {
        // GIVEN a fetch waiting in a suspended data loading queue
        let pipeline = makePipeline { $0.isRateLimiterEnabled = false }
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        let queued = subscribe(to: pipeline, Test.request)
        #expect(queue.operationCount == 1)

        // WHEN the same resource is fetched with `.skipDataLoadingQueue`
        let finished = TestExpectation()
        let request = ImageRequest(url: Test.url, options: [.skipDataLoadingQueue])
        _ = subscribe(to: pipeline, request) {
            if case let .value(_, isCompleted) = $0, isCompleted { finished.fulfill() }
        }

        // THEN it loads without waiting for the queue
        await finished.wait(timeout: .seconds(5))
        #expect(queue.operationCount == 1)
        #expect(dataLoader.createdTaskCount == 1)
        queued?.unsubscribe()
    }

    /// The same, with the only slot of the queue taken by unrelated work.
    @Test func imageTaskSkippingTheQueueDoesNotWaitForAQueuedEquivalent() async throws {
        // GIVEN the only slot taken and a request for "a" waiting for it
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let pipeline = makePipeline {
            $0.isRateLimiterEnabled = false
            $0.dataLoadingQueue = queue
        }
        let enqueued = TestExpectation(queue: queue, count: 2)
        let gate = TestExpectation()
        let blocker = pipeline.imageTask(with: ImageRequest(id: "blocker", data: {
            await gate.wait()
            return Test.data
        }))
        let queued = pipeline.imageTask(with: ImageRequest(id: "a", data: { Test.data }))
        await enqueued.wait()

        // WHEN "a" is requested with `.skipDataLoadingQueue`
        let finished = TestExpectation()
        let urgent = pipeline.imageTask(with: ImageRequest(id: "a", data: { Test.data }, options: [.skipDataLoadingQueue]))
        Task {
            _ = try? await urgent.response
            finished.fulfill()
        }

        // THEN it finishes while the slot is still taken
        await finished.wait(timeout: .seconds(5))
        #expect(urgent.state == .completed)
        #expect(queued.state == .running)

        gate.fulfill()
        _ = try await blocker.response
        _ = try await queued.response
    }

    // MARK: - Helpers

    private func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = true
            configure(&$0)
        }
    }

    /// Subscribes to the fetch of the original data the way the tasks that
    /// depend on it do, and starts it.
    private func subscribe(to pipeline: ImagePipeline, _ request: ImageRequest, _ onEvent: @escaping (AsyncTask<(Data, URLResponse?), ImagePipeline.Error>.Event) -> Void = { _ in }) -> TaskSubscription? {
        let subscriber = ImageTask(taskId: 1, request: request, isDataTask: true, pipeline: pipeline, onEvent: nil)
        let subscription = pipeline.makeTaskFetchOriginalData(for: request).subscribe(subscriber: subscriber, onEvent)
        subscribers.append(subscriber)
        return subscription
    }

    /// The subscriptions reference the subscribers weakly.
    private let subscribers = LockedArray<ImageTask>()
}

/// Takes every token out of the bucket and leaves a request waiting, so that
/// the work that comes next is held until the bucket refills.
@ImagePipelineActor
private func exhaust(_ limiter: RateLimiter) {
    var isHeld = false
    while !isHeld {
        var didRun = false
        limiter.execute {
            didRun = true
            return true
        }
        isHeld = !didRun
    }
}

/// Waits until the limiter executes everything submitted before the call.
@ImagePipelineActor
private func drain(_ limiter: RateLimiter) async {
    let expectation = TestExpectation()
    limiter.execute {
        expectation.fulfill()
        return true
    }
    await expectation.wait()
}

extension Optional where Wrapped: ~Copyable {
    /// `#expect(subscription != nil)` needs `Equatable`, which a noncopyable
    /// subscription can't conform to.
    fileprivate var _isPresent: Bool {
        switch self {
        case .none: false
        case .some: true
        }
    }
}

/// The lookups `AsyncPipelineTask` records when the diagnostics are on.
@Suite(.timeLimit(.minutes(5)))
struct AsyncPipelineTaskLookupDiagnosticsTests {
    @Test func finalImageFoundInTheMemoryCacheIsNotRecordedAsProgressive() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
            $0.isDiagnosticsEnabled = true
        }
        pipeline.cache[Test.request] = Test.container

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let lookup = try #require(task.metrics?.jobs.first?.stages.first)
        #expect(lookup.result == .hit)
        #expect(lookup.isProgressive == nil)
    }
}
