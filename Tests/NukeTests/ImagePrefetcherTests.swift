// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePrefetcherTests {
    private let pipeline: ImagePipeline
    private let dataLoader: MockDataLoader
    private let dataCache: MockDataCache
    private let imageCache: MockImageCache
    private let observer: ImagePipelineObserver
    private let prefetcher: ImagePrefetcher

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let imageCache = MockImageCache()
        let observer = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.imageCache = imageCache
        self.observer = observer
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
        self.pipeline = pipeline
        prefetcher = ImagePrefetcher(pipeline: pipeline)
    }

    // MARK: Basics

    /// Start prefetching for the request and then request an image separately.
    @Test @ImagePipelineActor func basicScenario() async {
        dataLoader.isSuspended = true

        _ = await prefetcher.queue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.request])
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadImage(with: Test.request, progress: nil) { _ in
                continuation.resume()
            }
            Task { @ImagePipelineActor in
                dataLoader.isSuspended = false
            }
        }

        // THEN
        #expect(dataLoader.createdTaskCount == 1)
        #expect(observer.startedTaskCount == 2)
    }

    // MARK: Start Prefetching

    @Test func startPrefetching() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            prefetcher.didComplete = { @MainActor @Sendable in
                continuation.resume()
            }
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN image saved in both caches
        #expect(pipeline.cache[Test.request] != nil)
        #expect(pipeline.cache.cachedData(for: Test.request) != nil)
    }

    @Test func startPrefetchingWithTwoEquivalentURLs() async {
        dataLoader.isSuspended = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            prefetcher.didComplete = { @MainActor @Sendable in
                continuation.resume()
            }
            prefetcher.startPrefetching(with: [Test.url])
            prefetcher.startPrefetching(with: [Test.url])

            Task { @ImagePipelineActor in
                dataLoader.isSuspended = false
            }
        }

        // THEN only one task is started
        #expect(observer.startedTaskCount == 1)
    }

    @Test func whenImageIsInMemoryCacheNoTaskStarted() async {
        // GIVEN
        pipeline.cache[Test.request] = Test.container

        // WHEN
        await withCheckedContinuation { continuation in
            prefetcher.didComplete = {
                continuation.resume()
            }
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN
        #expect(observer.startedTaskCount == 0)
    }

    // MARK: Stop Prefetching

    @Test func stopPrefetching() async {
        dataLoader.isSuspended = true

        let url = Test.url

        // Wait for start notification
        await notification(ImagePipelineObserver.didStartTask, object: observer) {
            prefetcher.startPrefetching(with: [url])
        }

        // Wait for cancel notification
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            prefetcher.stopPrefetching(with: [url])
        }
    }

    @Test @ImagePipelineActor func stopPrefetchingImmediatelyAfterStart() async {
        // GIVEN
        let url = Test.url
        let finished = TestExpectation()
        prefetcher.queue.onEvent = { event in
            if case .finished = event { finished.fulfill() }
        }

        // WHEN start and immediately stop prefetching in the same run loop tick
        // (the standard collection view prefetching pattern) – the prefetch
        // operation is dequeued, but its body hasn't run yet
        prefetcher.startPrefetching(with: [url])
        prefetcher.stopPrefetching(with: [url])
        await finished.wait()

        // THEN no image task is ever started
        #expect(observer.startedTaskCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test @ImagePipelineActor func stopAllPrefetchingImmediatelyAfterStart() async {
        // GIVEN
        let finished = TestExpectation()
        prefetcher.queue.onEvent = { event in
            if case .finished = event { finished.fulfill() }
        }

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])
        prefetcher.stopPrefetching()
        await finished.wait()

        // THEN no image task is ever started
        #expect(observer.startedTaskCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: Destination

    @Test func startPrefetchingDestinationDisk() async {
        // GIVEN
        let localPipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in
                Issue.record("Expect image not to be decoded")
                return nil
            }
        }
        let localPrefetcher = ImagePrefetcher(pipeline: localPipeline, destination: .diskCache)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            localPrefetcher.didComplete = { @MainActor @Sendable in
                continuation.resume()
            }
            localPrefetcher.startPrefetching(with: [Test.url])
        }

        // THEN image saved in both caches
        #expect(localPipeline.cache[Test.request] == nil)
        #expect(localPipeline.cache.cachedData(for: Test.request) != nil)
    }

    // MARK: Pause

    @Test @ImagePipelineActor func pausingPrefetcher() async {
        // WHEN
        prefetcher.isPaused = true

        _ = await prefetcher.queue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN
        #expect(observer.startedTaskCount == 0)
    }

    // MARK: Priority

    @Test @ImagePipelineActor func defaultPrioritySetToLow() async {
        // WHEN start prefetching with URL
        pipeline.configuration.dataLoadingQueue.isSuspended = true

        let operations = await pipeline.configuration.dataLoadingQueue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN priority is set to .low
        guard let operation = operations.first else {
            Issue.record("Failed to find operation")
            return
        }
        #expect(operation.priority == .low)

        // Cleanup
        prefetcher.stopPrefetching()
    }

    @Test @ImagePipelineActor func defaultPriorityAffectsRequests() async {
        // WHEN start prefetching with ImageRequest
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let request = Test.request
        #expect(request.priority == .normal) // Default is .normal

        let operations = await pipeline.configuration.dataLoadingQueue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [request])
        }

        // THEN priority is set to .low
        guard let operation = operations.first else {
            Issue.record("Failed to find operation")
            return
        }
        #expect(operation.priority == .low)
    }

    @Test @ImagePipelineActor func lowerPriorityThanDefaultNotAffected() async {
        // WHEN start prefetching with ImageRequest with .veryLow priority
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        var request = Test.request
        request.priority = .veryLow

        let operations = await pipeline.configuration.dataLoadingQueue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [request])
        }
        await Task.yield()

        // THEN priority is set to .low (prefetcher priority)
        guard let operation = operations.first else {
            Issue.record("Failed to find operation")
            return
        }
        #expect(operation.priority == .low)
    }

    @Test @ImagePipelineActor func changePriority() async {
        // GIVEN
        prefetcher.priority = .veryHigh

        // WHEN
        pipeline.configuration.dataLoadingQueue.isSuspended = true

        let operations = await pipeline.configuration.dataLoadingQueue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN
        guard let operation = operations.first else {
            Issue.record("Failed to find operation")
            return
        }
        #expect(operation.priority == .veryHigh)
    }

    @Test @ImagePipelineActor func changePriorityOfOutstandingTasks() async {
        // WHEN
        pipeline.configuration.dataLoadingQueue.isSuspended = true

        let operations = await pipeline.configuration.dataLoadingQueue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.url])
        }

        guard let operation = operations.first else {
            Issue.record("Failed to find operation")
            return
        }

        // WHEN/THEN
        #expect(operation.priority == .low)

        await pipeline.configuration.dataLoadingQueue.waitForPriorityChange(of: operation, to: .veryLow) {
            prefetcher.priority = .veryLow
        }
        #expect(operation.priority == .veryLow)
    }

    @Test @ImagePipelineActor func changePriorityBeforeImageTaskIsCreated() async {
        // GIVEN prefetching is paused: the operation is scheduled, but its body
        // (the code that creates the image task) hasn't run yet
        prefetcher.isPaused = true
        dataLoader.isSuspended = true

        let operations = await prefetcher.queue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.url])
        }
        guard let operation = operations.first else {
            Issue.record("Failed to find operation")
            return
        }

        // WHEN the priority changes before the prefetch starts
        await prefetcher.queue.waitForPriorityChange(of: operation, to: .veryHigh) {
            prefetcher.priority = .veryHigh
        }

        // THEN the image task the prefetch creates uses the new priority
        nonisolated(unsafe) var imageTask: ImageTask?
        observer.onTaskCreated = { imageTask = $0 }

        await notification(ImagePipelineObserver.didStartTask, object: observer) {
            prefetcher.isPaused = false
        }
        #expect(imageTask?.priority == .veryHigh)

        // Cleanup
        prefetcher.stopPrefetching()
    }

    @Test @ImagePipelineActor func changePriorityBeforeImageTaskIsCreatedAffectsDataLoading() async {
        // GIVEN prefetching is paused: the operation is scheduled, but its body
        // (the code that creates the image task) hasn't run yet
        prefetcher.isPaused = true
        pipeline.configuration.dataLoadingQueue.isSuspended = true

        let operations = await prefetcher.queue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.url])
        }
        guard let operation = operations.first else {
            Issue.record("Failed to find operation")
            return
        }

        // WHEN the priority changes before the prefetch starts
        await prefetcher.queue.waitForPriorityChange(of: operation, to: .veryHigh) {
            prefetcher.priority = .veryHigh
        }

        // THEN the pipeline performs the work at the new priority
        let dataOperations = await pipeline.configuration.dataLoadingQueue.waitForOperations(count: 1) {
            prefetcher.isPaused = false
        }
        #expect(dataOperations.first?.priority == .veryHigh)

        // Cleanup
        prefetcher.stopPrefetching()
    }

    // MARK: DidComplete

    @Test func didCompleteIsCalled() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            prefetcher.didComplete = { @MainActor @Sendable in
                continuation.resume()
            }
            prefetcher.startPrefetching(with: [Test.url])
        }
    }

    @Test func didCompleteIsCalledWhenImageCached() async {
        imageCache[Test.request] = Test.container

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            prefetcher.didComplete = { @MainActor @Sendable in
                continuation.resume()
            }
            prefetcher.startPrefetching(with: [Test.request])
        }
    }

    @Test func didCompleteIsCalledWithAnEmptyBatch() async {
        // WHEN prefetching is started with nothing to prefetch
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            prefetcher.didComplete = { @MainActor @Sendable in
                continuation.resume()
            }
            prefetcher.startPrefetching(with: [URL]())
        }

        // THEN the closure is still called and no tasks are started
        #expect(observer.startedTaskCount == 0)
    }

    @Test func didCompleteIsCalledOnTheMainThread() async {
        // WHEN the closure is set from a non-main context
        let isMainThread = OSAllocatedUnfairLock(initialState: false)
        await Task.detached { [prefetcher] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                prefetcher.didComplete = { @MainActor @Sendable in
                    isMainThread.withLock { $0 = Thread.isMainThread }
                    continuation.resume()
                }
                prefetcher.startPrefetching(with: [Test.url])
            }
        }.value

        // THEN it is still delivered on the main thread
        #expect(isMainThread.withLock { $0 })
    }

    @Test func didCompleteIsCalledForEveryBatch() async {
        // GIVEN one batch that already completed
        let count = OSAllocatedUnfairLock(initialState: 0)
        let first = TestExpectation()
        prefetcher.didComplete = { @MainActor @Sendable in
            count.withLock { $0 += 1 }
            first.fulfill()
        }
        prefetcher.startPrefetching(with: [Test.url])
        await first.wait()

        // WHEN a second batch is prefetched
        let second = TestExpectation()
        prefetcher.didComplete = { @MainActor @Sendable in
            count.withLock { $0 += 1 }
            second.fulfill()
        }
        prefetcher.startPrefetching(with: [Self.otherURL])
        await second.wait()

        // THEN the closure is called once per batch and the replaced closure
        // is never called again
        #expect(count.withLock { $0 } == 2)
    }

    @Test func didCompleteCanBeCleared() async {
        // GIVEN one batch that already completed
        let count = OSAllocatedUnfairLock(initialState: 0)
        let first = TestExpectation()
        prefetcher.didComplete = { @MainActor @Sendable in
            count.withLock { $0 += 1 }
            first.fulfill()
        }
        prefetcher.startPrefetching(with: [Test.url])
        await first.wait()

        // WHEN the closure is removed and another batch is prefetched
        prefetcher.didComplete = nil
        #expect(prefetcher.didComplete == nil)
        prefetcher.startPrefetching(with: [Self.otherURL])

        // THEN the removed closure is never called again. A later batch with a
        // fresh closure gives us a point in time to check by.
        let second = TestExpectation()
        prefetcher.didComplete = { @MainActor @Sendable in second.fulfill() }
        prefetcher.startPrefetching(with: [Self.thirdURL])
        await second.wait()
        #expect(count.withLock { $0 } == 1)
    }

    // MARK: Events

    @Test func eventsAreSentForASuccessfulPrefetch() async {
        // WHEN
        let events = await recordEvents {
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN the request is reported as started, then finished, and the
        // prefetcher reports itself complete
        #expect(events.count == 3)
        guard case .didStartPrefetching(let started) = events.first else {
            Issue.record("Unexpected events: \(events)")
            return
        }
        #expect(started.url == Test.url)
        guard case .didFinishPrefetching(let finished, let result) = events[1] else {
            Issue.record("Unexpected events: \(events)")
            return
        }
        #expect(finished.url == Test.url)
        #expect((try? result.get()) != nil)
        guard case .didComplete = events[2] else {
            Issue.record("Unexpected events: \(events)")
            return
        }
    }

    @Test func didFinishPrefetchingReportsTheFailure() async {
        // GIVEN a request that fails
        dataLoader.results[Test.url] = .failure(NSError(domain: "t", code: 42))

        // WHEN
        let events = await recordEvents {
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN
        guard case .didFinishPrefetching(_, .failure(let error))? = events.first(where: \.isDidFinishPrefetching) else {
            Issue.record("Unexpected events: \(events)")
            return
        }
        guard case .dataLoadingFailed = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }

    @Test func didFinishPrefetchingReportsCancellation() async {
        // GIVEN a request that stays outstanding
        dataLoader.isSuspended = true

        // WHEN it is cancelled
        let events = await recordEvents {
            prefetcher.startPrefetching(with: [Test.url])
            prefetcher.stopPrefetching(with: [Test.url])
        }

        // THEN the cancelled request still finishes, with `.cancelled`, and the
        // prefetcher reports itself complete
        guard case .didFinishPrefetching(_, .failure(let error))? = events.first(where: \.isDidFinishPrefetching) else {
            Issue.record("Unexpected events: \(events)")
            return
        }
        guard case .cancelled = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }

    @Test func noStartEventForAnImageInTheMemoryCache() async {
        // GIVEN an image that is already in the memory cache
        imageCache[Test.request] = Test.container

        // WHEN
        let events = await recordEvents {
            prefetcher.startPrefetching(with: [Test.request])
        }

        // THEN the prefetcher skips it and only reports the completion
        #expect(events.count == 1)
        guard case .didComplete = events.first else {
            Issue.record("Unexpected events: \(events)")
            return
        }
    }

    @Test func noStartEventForADuplicateRequest() async {
        // WHEN the same URL is scheduled twice
        let events = await recordEvents {
            dataLoader.isSuspended = true
            prefetcher.startPrefetching(with: [Test.url])
            prefetcher.startPrefetching(with: [Test.url])
            dataLoader.isSuspended = false
        }

        // THEN it is only prefetched once
        #expect(events.count { $0.isDidStartPrefetching } == 1)
        #expect(events.count { $0.isDidFinishPrefetching } == 1)
    }

    @Test func everyStreamIsIndependent() async {
        // GIVEN two subscriptions
        let first = prefetcher.events
        let second = prefetcher.events
        await pipelineActorFlush()

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])

        // THEN both receive the same events
        #expect(await collect(first).count == 3)
        #expect(await collect(second).count == 3)
    }

    @Test func unsubscribingReleasesTheContinuation() async {
        // GIVEN a subscription that already received a batch
        _ = await recordEvents {
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN the continuation doesn't outlive the iteration
        await pipelineActorFlush()
        #expect(await prefetcher.subscriptionCount == 0)
    }

    @Test func theStreamFinishesWhenThePrefetcherIsDeallocated() async {
        // GIVEN a subscription to a prefetcher nothing else holds on to
        var localPrefetcher: ImagePrefetcher? = ImagePrefetcher(pipeline: pipeline)
        let events = localPrefetcher!.events
        await pipelineActorFlush()

        // WHEN the prefetcher is deallocated
        autoreleasepool {
            localPrefetcher = nil
        }

        // THEN the stream finishes instead of leaving the iteration suspended
        var recorded: [ImagePrefetcher.Event] = []
        for await event in events {
            recorded.append(event)
        }
        #expect(recorded.isEmpty)
    }

    // MARK: WaitUntilIdle

    @Test func waitUntilIdleReturnsImmediatelyWhenIdle() async {
        // WHEN nothing was ever scheduled
        await prefetcher.waitUntilIdle()

        // THEN it returns without subscribing at all
        #expect(await prefetcher.subscriptionCount == 0)
    }

    @Test func waitUntilIdleWaitsForTheScheduledBatch() async {
        // WHEN waiting right after scheduling, before the batch reaches the
        // pipeline actor
        prefetcher.startPrefetching(with: [Test.url])
        await prefetcher.waitUntilIdle()

        // THEN it waits for the batch instead of returning immediately
        #expect(pipeline.cache[Test.request] != nil)
        #expect(observer.startedTaskCount == 1)
    }

    @Test func waitUntilIdleWaitsForABatchScheduledAtALowerPriority() async {
        // GIVEN a batch scheduled from a background priority context, whose
        // job the pipeline actor runs after the higher priority ones
        await Task.detached(priority: .background) { [prefetcher] in
            prefetcher.startPrefetching(with: [Test.url])
        }.value

        // WHEN waiting from a high priority context
        await Task.detached(priority: .high) { [prefetcher] in
            await prefetcher.waitUntilIdle()
        }.value

        // THEN it still waits for the batch
        #expect(pipeline.cache[Test.request] != nil)
        #expect(observer.startedTaskCount == 1)
    }

    @Test func waitUntilIdleReturnsWhenEverythingIsCancelled() async {
        // GIVEN an outstanding request
        dataLoader.isSuspended = true
        prefetcher.startPrefetching(with: [Test.url])
        await pipelineActorFlush()

        // WHEN all of the prefetching is stopped
        prefetcher.stopPrefetching()

        // THEN the prefetcher reports itself idle rather than waiting forever
        await prefetcher.waitUntilIdle()
        #expect(pipeline.cache[Test.request] == nil)
    }

    @Test func waitUntilIdleReleasesItsSubscription() async {
        // WHEN
        dataLoader.isSuspended = true
        prefetcher.startPrefetching(with: [Test.url])
        Task { @ImagePipelineActor in self.dataLoader.isSuspended = false }
        await prefetcher.waitUntilIdle()

        // THEN the internal stream is torn down
        await pipelineActorFlush()
        #expect(await prefetcher.subscriptionCount == 0)
    }

    @Test func waitUntilIdleCanBeCalledConcurrently() async {
        // WHEN multiple callers wait at the same time
        prefetcher.startPrefetching(with: [Test.url, Self.otherURL])
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { [prefetcher] in await prefetcher.waitUntilIdle() }
            }
        }

        // THEN they all return and clean up after themselves
        #expect(pipeline.cache[Test.request] != nil)
        await pipelineActorFlush()
        #expect(await prefetcher.subscriptionCount == 0)
    }

    @Test func waitUntilIdleIsCancellable() async {
        // GIVEN a prefetcher that never becomes idle
        dataLoader.isSuspended = true
        prefetcher.startPrefetching(with: [Test.url])
        await pipelineActorFlush()

        // WHEN the waiting task is cancelled
        let task = Task { [prefetcher] in await prefetcher.waitUntilIdle() }
        while await prefetcher.subscriptionCount == 0 {
            await Task.yield()
        }
        task.cancel()
        await task.value

        // THEN it returns and releases the subscription
        await pipelineActorFlush()
        #expect(await prefetcher.subscriptionCount == 0)

        // Cleanup
        prefetcher.stopPrefetching()
    }

    // MARK: Helpers

    /// Subscribes to the prefetcher events, runs `work`, and returns everything
    /// the prefetcher sent up to and including ``ImagePrefetcher/Event/didComplete``.
    private func recordEvents(_ work: () -> Void) async -> [ImagePrefetcher.Event] {
        let events = prefetcher.events
        // Subscribing reaches the pipeline actor asynchronously – let it land
        // before scheduling any work, or the events race the subscription.
        await pipelineActorFlush()
        work()
        return await collect(events)
    }

    /// Collects the events up to and including the first `.didComplete`. The
    /// stream never finishes on its own.
    private func collect(_ events: AsyncStream<ImagePrefetcher.Event>) async -> [ImagePrefetcher.Event] {
        var recorded: [ImagePrefetcher.Event] = []
        for await event in events {
            recorded.append(event)
            if case .didComplete = event {
                break
            }
        }
        return recorded
    }

    /// Waits for a round trip through the pipeline actor, which is where the
    /// prefetcher does all of its work.
    private func pipelineActorFlush() async {
        await Task { @ImagePipelineActor in }.value
    }

    @Test func didCompleteIsCalledWhenPrefetchingIsStopped() async {
        // GIVEN an outstanding request
        dataLoader.isSuspended = true
        let expectation = TestExpectation()
        prefetcher.didComplete = { @MainActor @Sendable in expectation.fulfill() }
        let events = prefetcher.events
        await pipelineActorFlush()
        prefetcher.startPrefetching(with: [Test.url])
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next() // .didStartPrefetching

        // WHEN the outstanding request is cancelled
        prefetcher.stopPrefetching()

        // THEN the prefetcher still reports itself complete – it has no
        // outstanding requests left
        await expectation.wait()
    }

    @Test func didCompleteIsNotSentWhileAnotherBatchIsScheduled() async {
        // GIVEN two batches that complete without starting a task, followed by
        // one that starts a task
        imageCache[Test.request] = Test.container
        imageCache[ImageRequest(url: Self.otherURL)] = Test.container
        let events = prefetcher.events
        await pipelineActorFlush()

        // WHEN they are scheduled back to back
        prefetcher.startPrefetching(with: [Test.url])
        prefetcher.startPrefetching(with: [Self.otherURL])
        prefetcher.startPrefetching(with: [Self.thirdURL])

        // THEN the prefetcher doesn't report itself complete while the batches
        // that follow are still on their way to the pipeline actor
        var completions = 0
        for await event in events {
            if case .didComplete = event {
                completions += 1
            }
            if case .didFinishPrefetching = event {
                break
            }
        }
        #expect(completions == 0)
    }

    private static let otherURL = URL(string: "http://test.com/example-2.jpeg")!
    private static let thirdURL = URL(string: "http://test.com/example-3.jpeg")!

    // MARK: Misc

    @ImagePipelineActor
    @Test func allPrefetchingRequestsAreStoppedWhenPrefetcherIsDeallocated() async {
        pipeline.configuration.dataLoadingQueue.isSuspended = true

        var localPrefetcher: ImagePrefetcher? = ImagePrefetcher(pipeline: pipeline)
        let request = Test.request

        // Wait for start notification
        await notification(ImagePipelineObserver.didStartTask, object: observer) {
            localPrefetcher?.startPrefetching(with: [request])
        }

        // Wait for cancel notification when prefetcher is deallocated
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            autoreleasepool {
                localPrefetcher = nil
            }
        }
    }
}

private extension ImagePrefetcher.Event {
    var isDidStartPrefetching: Bool {
        if case .didStartPrefetching = self { return true }
        return false
    }

    var isDidFinishPrefetching: Bool {
        if case .didFinishPrefetching = self { return true }
        return false
    }
}
