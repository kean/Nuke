// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePrefetcherLifecycleTests {
    private let pipeline: ImagePipeline
    private let dataLoader: MockDataLoader
    private let observer: ImagePipelineObserver
    private let prefetcher: ImagePrefetcher

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let imageCache = MockImageCache()
        let observer = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.observer = observer
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
        self.pipeline = pipeline
        prefetcher = ImagePrefetcher(pipeline: pipeline)
    }

    // MARK: Configuration

    @Test @ImagePipelineActor func defaults() {
        #expect(prefetcher.priority == .low)
        #expect(prefetcher.isPaused == false)
        #expect(prefetcher.didComplete == nil)
        #expect(prefetcher.queue.maxConcurrentTaskCount == 2)
    }

    // MARK: Concurrency

    @Test @ImagePipelineActor func maxConcurrentRequestCountLimitsHowManyPrefetchesRunAtATime() async {
        // GIVEN
        let prefetcher = ImagePrefetcher(pipeline: pipeline, maxConcurrentRequestCount: 3)
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }

        // WHEN
        prefetcher.startPrefetching(with: Self.makeURLs(count: 5))
        await started.wait(for: 3)

        // THEN three are loading, and the rest wait for a free slot
        #expect(observer.startedTaskCount == 3)
        #expect(prefetcher.queue.runningCount == 3)
        #expect(prefetcher.queue.pendingCount == 2)

        // WHEN the loads go through
        dataLoader.isSuspended = false
        await completed.wait(for: 1)

        // THEN the waiting ones run too
        #expect(observer.startedTaskCount == 5)
    }

    // MARK: Pause

    /// Documented: "the prefetcher will finish outstanding tasks and pause the rest".
    @Test @ImagePipelineActor func pausingLetsTheRunningPrefetchesFinishAndHoldsTheRest() async {
        // GIVEN two prefetches loading, and two waiting in the queue
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        let urls = Self.makeURLs(count: 4)
        prefetcher.startPrefetching(with: urls)
        await started.wait(for: 2)

        // WHEN the prefetcher is paused and the loads in flight go through
        prefetcher.isPaused = true
        #expect(prefetcher.isPaused)
        let finished = EventCounter()
        prefetcher.queue.onEvent = { if case .finished = $0 { finished.increment() } }
        dataLoader.isSuspended = false
        await finished.wait(for: 2)
        await waitForDelivery()

        // THEN the two in flight finish, the other two never start, and the
        // prefetcher doesn't report that it's done
        #expect(observer.startedTaskCount == 2)
        #expect(pipeline.cache[ImageRequest(url: urls[0])] != nil)
        #expect(pipeline.cache[ImageRequest(url: urls[1])] != nil)
        #expect(prefetcher.queue.pendingCount == 2)
        #expect(completed.count == 0)

        // WHEN
        prefetcher.isPaused = false
        #expect(!prefetcher.isPaused)
        await completed.wait(for: 1)

        // THEN
        #expect(observer.startedTaskCount == 4)
        for url in urls {
            #expect(pipeline.cache[ImageRequest(url: url)] != nil)
        }
    }

    @Test @ImagePipelineActor func prefetchesStoppedWhilePausedNeverStart() async {
        // GIVEN
        prefetcher.isPaused = true
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        let urls = Self.makeURLs(count: 3)
        _ = await prefetcher.queue.waitForOperations(count: urls.count) {
            prefetcher.startPrefetching(with: urls)
        }

        // WHEN
        prefetcher.stopPrefetching(with: urls)
        await completed.wait(for: 1)
        prefetcher.isPaused = false
        await prefetcher.queue.waitUntilAllOperationsAreFinished()
        await waitForDelivery()

        // THEN
        #expect(prefetcher.queue.operationCount == 0)
        #expect(observer.startedTaskCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
        #expect(completed.count == 1)
    }

    // MARK: Stop

    @Test @ImagePipelineActor func stoppingARequestThatWasNeverStartedLeavesTheOthersAlone() async {
        // GIVEN
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [Test.url])
        await started.wait(for: 1)

        // WHEN
        prefetcher.stopPrefetching(with: [Self.otherURL])
        await waitForDelivery()

        // THEN nothing is cancelled, and there is still work outstanding
        #expect(observer.cancelledTaskCount == 0)
        #expect(completed.count == 0)

        // WHEN
        dataLoader.isSuspended = false
        await completed.wait(for: 1)

        // THEN
        #expect(pipeline.cache[Test.request] != nil)
    }

    /// Documented: "You don't need to balance the number of `start` and `stop`
    /// requests."
    @Test @ImagePipelineActor func singleStopCancelsARequestThatWasStartedTwice() async {
        // GIVEN
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [Test.url])
        prefetcher.startPrefetching(with: [Test.url])
        await started.wait(for: 1)

        // WHEN
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            prefetcher.stopPrefetching(with: [Test.url])
        }

        // THEN nothing is left outstanding
        await completed.wait(for: 1)
        #expect(observer.startedTaskCount == 1)
        #expect(observer.cancelledTaskCount == 1)
    }

    /// The prefetcher identifies the requests the same way the pipeline
    /// coalesces them, so a request doesn't have to be the same instance, or
    /// even be created the same way, to stop the prefetch.
    @Test(arguments: [
        ImageRequest(url: Test.url, priority: .veryHigh),
        ImageRequest(urlRequest: URLRequest(url: Test.url)),
    ])
    @ImagePipelineActor func stoppingWithAnEquivalentRequestCancelsThePrefetch(_ stopRequest: ImageRequest) async {
        // GIVEN
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        prefetcher.startPrefetching(with: [Test.url])
        await started.wait(for: 1)

        // WHEN/THEN
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            prefetcher.stopPrefetching(with: [stopRequest])
        }
    }

    @Test(arguments: [
        ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")]),
        ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadIgnoringLocalCacheData)),
    ])
    @ImagePipelineActor func stoppingWithADifferentRequestForTheSameURLDoesNothing(_ stopRequest: ImageRequest) async {
        // GIVEN
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [Test.url])
        await started.wait(for: 1)

        // WHEN
        prefetcher.stopPrefetching(with: [stopRequest])
        await waitForDelivery()

        // THEN
        #expect(observer.cancelledTaskCount == 0)
        #expect(completed.count == 0)

        // Cleanup
        prefetcher.stopPrefetching()
        await completed.wait(for: 1)
    }

    /// When a stopped prefetch is started again right away, the cancelled
    /// load is still unwinding. It must not remove the new prefetch that took
    /// its place, which would report completion while the image is loading.
    @Test @ImagePipelineActor func restartingAStoppedPrefetchIsNotEndedByTheCancelledOne() async {
        // GIVEN
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [Test.url])
        await started.wait(for: 1)

        // WHEN
        let finished = EventCounter()
        prefetcher.queue.onEvent = { if case .finished = $0 { finished.increment() } }
        prefetcher.stopPrefetching(with: [Test.url])
        prefetcher.startPrefetching(with: [Test.url])
        await finished.wait(for: 1) // The cancelled prefetch is done
        await started.wait(for: 2) // The new one is loading
        await waitForDelivery()

        // THEN only the stop reported that the prefetcher ran out of work
        #expect(completed.count == 1)
        #expect(observer.cancelledTaskCount == 1)

        // WHEN
        dataLoader.isSuspended = false
        await completed.wait(for: 2)

        // THEN
        #expect(pipeline.cache[Test.request] != nil)
    }

    @Test @ImagePipelineActor func stoppingAPrefetchDoesNotCancelARegularLoadOfTheSameImage() async throws {
        // GIVEN a prefetch and a regular load that share the download
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        prefetcher.startPrefetching(with: [Test.url])
        await started.wait(for: 1)
        let task = pipeline.imageTask(with: Test.request)
        await started.wait(for: 2)

        // WHEN
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            prefetcher.stopPrefetching(with: [Test.url])
        }
        dataLoader.isSuspended = false

        // THEN the regular load completes with the download it shared
        _ = try await task.response
        #expect(dataLoader.createdTaskCount == 1)
        #expect(observer.cancelledTaskCount == 1)
    }

    /// Documented: "If you have multiple screens with prefetching, create
    /// multiple instances of ImagePrefetcher."
    @Test @ImagePipelineActor func stoppingOnePrefetcherDoesNotAffectAnotherOne() async {
        // GIVEN two prefetchers prefetching the same image
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        let other = ImagePrefetcher(pipeline: pipeline)
        let completed = EventCounter()
        other.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [Test.url])
        other.startPrefetching(with: [Test.url])
        await started.wait(for: 2)

        // WHEN
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            prefetcher.stopPrefetching()
        }
        dataLoader.isSuspended = false
        await completed.wait(for: 1)

        // THEN
        #expect(pipeline.cache[Test.request] != nil)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(observer.cancelledTaskCount == 1)
    }

    // MARK: Requests

    @Test func requestsWithDifferentProcessorsArePrefetchedSeparately() async {
        // GIVEN
        let requests = [
            ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]),
            ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p2")]),
        ]
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }

        // WHEN
        await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            prefetcher.startPrefetching(with: requests)
        }
        await completed.wait(for: 1)

        // THEN each variant is cached, and they share a single download
        #expect(pipeline.cache[requests[0]]?.image.nk_test_processorIDs == ["p1"])
        #expect(pipeline.cache[requests[1]]?.image.nk_test_processorIDs == ["p2"])
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func requestWithProcessorsIsPrefetchedWhenOnlyTheOriginalIsInMemory() async {
        // GIVEN the original image in the memory cache
        pipeline.cache[Test.request] = Test.container
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [request])
        await completed.wait(for: 1)

        // THEN the processed variant is produced from the cached original
        #expect(observer.startedTaskCount == 1)
        #expect(pipeline.cache[request]?.image.nk_test_processorIDs == ["p1"])
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func requestThatSkipsMemoryCacheReadsIsPrefetchedEvenWhenCached() async {
        // GIVEN
        pipeline.cache[Test.request] = Test.container
        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheReads])

        // WHEN
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [request])
        await completed.wait(for: 1)

        // THEN
        #expect(observer.startedTaskCount == 1)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: Failures

    /// Documented: "The closure is always called on completion, regardless of
    /// whether the requests succeed or some fail."
    @Test func didCompleteIsCalledWhenPrefetchingFailsAndTheRequestCanBeRetried() async {
        // GIVEN
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: -1))
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])
        await completed.wait(for: 1)

        // THEN
        #expect(pipeline.cache[Test.request] == nil)
        #expect(pipeline.cache.cachedData(for: Test.request) == nil)

        // WHEN the same image is prefetched again after the failure
        dataLoader.results[Test.url] = nil
        prefetcher.startPrefetching(with: [Test.url])
        await completed.wait(for: 2)

        // THEN the failed prefetch didn't linger, so this one loads the image
        #expect(observer.startedTaskCount == 2)
        #expect(pipeline.cache[Test.request] != nil)
    }

    @Test @ImagePipelineActor func didCompleteIsCalledOnceWhenThePipelineIsInvalidated() async {
        // GIVEN two prefetches loading, and two waiting in the queue
        dataLoader.isSuspended = true
        let started = EventCounter()
        pipeline.onTaskStarted = { _ in started.increment() }
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: Self.makeURLs(count: 4))
        await started.wait(for: 2)

        // WHEN
        pipeline.invalidate()
        await completed.wait(for: 1)
        await prefetcher.queue.waitUntilAllOperationsAreFinished()
        await waitForDelivery()

        // THEN the loads in flight are cancelled, the rest fail without
        // starting, and the prefetcher reports running out of work once
        #expect(observer.cancelledTaskCount == 2)
        #expect(observer.completedTaskCount == 2)
        #expect(observer.startedTaskCount == 2)
        #expect(completed.count == 1)
    }

    // MARK: Destination

    @Test func prefetchedImageIsServedFromTheMemoryCache() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [request])
        await completed.wait(for: 1)

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.cacheType == .memory)
        #expect(response.image.nk_test_processorIDs == ["p1"])
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func imagePrefetchedToDiskIsDecodedFromTheDiskCache() async throws {
        // GIVEN
        let prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .diskCache)
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [Test.url])
        await completed.wait(for: 1)
        #expect(pipeline.cache[Test.request] == nil)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func diskCacheDestinationStoresTheOriginalDataWithoutProcessing() async {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
            $0.makeImageDecoder = { _ in
                Issue.record("Expect image not to be decoded")
                return nil
            }
        }
        let prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .diskCache)
        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "p1") {
            Issue.record("Expect image not to be processed")
            return $0
        }])

        // WHEN
        let completed = EventCounter()
        prefetcher.didComplete = { completed.increment() }
        prefetcher.startPrefetching(with: [request])
        await completed.wait(for: 1)

        // THEN
        #expect(pipeline.cache.cachedData(for: Test.request) == Test.data)
        #expect(pipeline.cache[request] == nil)
    }

    // MARK: Deallocation

    /// Documented: "The prefetcher cancels all of the outstanding tasks when
    /// deallocated", including the ones that are still waiting in its queue.
    ///
    /// The queue goes away with the prefetcher, so a queued prefetch can't
    /// start either way. What cancelling it does is release it: its operation
    /// and the prefetch task retain each other until the operation either runs
    /// or is cancelled.
    @Test @ImagePipelineActor func deallocatingThePrefetcherCancelsAndReleasesTheQueuedPrefetches() async {
        // GIVEN
        var prefetcher: ImagePrefetcher? = ImagePrefetcher(pipeline: pipeline)
        prefetcher?.isPaused = true
        let operations = await prefetcher!.queue.waitForOperations(count: 2) {
            prefetcher?.startPrefetching(with: Self.makeURLs(count: 2))
        }.map { WeakRef($0) }
        let cancelled = EventCounter()
        for operation in operations {
            operation.value?.onCancelled = { cancelled.increment() }
        }

        // WHEN
        prefetcher = nil

        // THEN
        await cancelled.wait(for: 2)
        await Task { @ImagePipelineActor in }.value
        #expect(operations.allSatisfy { $0.value == nil })
    }

    // MARK: Helpers

    private static let otherURL = URL(string: "http://test.com/example-2.jpeg")!

    private static func makeURLs(count: Int) -> [URL] {
        (0..<count).map { URL(string: "http://test.com/lifecycle-\($0).jpeg")! }
    }
}

/// Counts events, such as `didComplete` calls, and lets the test wait for the
/// n-th one.
private final class EventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var waiters: [(count: Int, expectation: TestExpectation)] = []

    var count: Int { lock.withLock { _count } }

    func increment() {
        let ready = lock.withLock {
            _count += 1
            let ready = waiters.filter { $0.count <= _count }
            waiters.removeAll { $0.count <= _count }
            return ready
        }
        for waiter in ready {
            waiter.expectation.fulfill()
        }
    }

    func wait(for count: Int) async {
        let expectation = TestExpectation()
        let isReached = lock.withLock {
            guard _count < count else { return true }
            waiters.append((count, expectation))
            return false
        }
        if !isReached {
            await expectation.wait()
        }
    }
}
