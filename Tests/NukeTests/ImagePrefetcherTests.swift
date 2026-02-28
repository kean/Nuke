// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImagePrefetcherTests {
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
    @Test func basicScenario() async {
        dataLoader.isSuspended = true

        let queueObserver = OperationQueueObserver(queue: prefetcher.queue)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queueObserver.didAddOperation = { _ in
                if queueObserver.operations.count == 1 {
                    queueObserver.didAddOperation = nil
                    continuation.resume()
                }
            }
            prefetcher.startPrefetching(with: [Test.request])
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadImage(with: Test.request, progress: nil) { _ in
                continuation.resume()
            }
            pipeline.queue.async {
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

            pipeline.queue.async {
                dataLoader.isSuspended = false
            }
        }

        // THEN only one task is started
        #expect(observer.startedTaskCount == 1)
    }

    @Test func whenImageIsInMemoryCacheNoTaskStarted() {
        dataLoader.isSuspended = true

        // GIVEN
        pipeline.cache[Test.request] = Test.container

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])
        pipeline.queue.sync {}

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

    @Test func pausingPrefetcher() async {
        // WHEN
        prefetcher.isPaused = true
        prefetcher.startPrefetching(with: [Test.url])

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.queue.asyncAfter(deadline: .now() + .milliseconds(10)) {
                continuation.resume()
            }
        }

        // THEN
        #expect(observer.startedTaskCount == 0)
    }

    // MARK: Priority

    @Test func defaultPrioritySetToLow() async {
        // WHEN start prefetching with URL
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let queueObserver = OperationQueueObserver(queue: pipeline.configuration.dataLoadingQueue)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queueObserver.didAddOperation = { _ in
                if queueObserver.operations.count == 1 {
                    queueObserver.didAddOperation = nil
                    continuation.resume()
                }
            }
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN priority is set to .low
        guard let operation = queueObserver.operations.first else {
            Issue.record("Failed to find operation")
            return
        }
        #expect(operation.queuePriority == .low)

        // Cleanup
        prefetcher.stopPrefetching()
    }

    @Test func defaultPriorityAffectsRequests() async {
        // WHEN start prefetching with ImageRequest
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let queueObserver = OperationQueueObserver(queue: pipeline.configuration.dataLoadingQueue)
        let request = Test.request
        #expect(request.priority == .normal) // Default is .normal

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queueObserver.didAddOperation = { _ in
                if queueObserver.operations.count == 1 {
                    queueObserver.didAddOperation = nil
                    continuation.resume()
                }
            }
            prefetcher.startPrefetching(with: [request])
        }

        // THEN priority is set to .low
        guard let operation = queueObserver.operations.first else {
            Issue.record("Failed to find operation")
            return
        }
        #expect(operation.queuePriority == .low)
    }

    @Test func lowerPriorityThanDefaultNotAffected() async {
        // WHEN start prefetching with ImageRequest with .veryLow priority
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let queueObserver = OperationQueueObserver(queue: pipeline.configuration.dataLoadingQueue)
        var request = Test.request
        request.priority = .veryLow

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queueObserver.didAddOperation = { _ in
                if queueObserver.operations.count == 1 {
                    queueObserver.didAddOperation = nil
                    continuation.resume()
                }
            }
            prefetcher.startPrefetching(with: [request])
        }

        // THEN priority is set to .low (prefetcher priority)
        guard let operation = queueObserver.operations.first else {
            Issue.record("Failed to find operation")
            return
        }
        #expect(operation.queuePriority == .low)
    }

    @Test func changePriority() async {
        // GIVEN
        prefetcher.priority = .veryHigh

        // WHEN
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let queueObserver = OperationQueueObserver(queue: pipeline.configuration.dataLoadingQueue)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queueObserver.didAddOperation = { _ in
                if queueObserver.operations.count == 1 {
                    queueObserver.didAddOperation = nil
                    continuation.resume()
                }
            }
            prefetcher.startPrefetching(with: [Test.url])
        }

        // THEN
        guard let operation = queueObserver.operations.first else {
            Issue.record("Failed to find operation")
            return
        }
        #expect(operation.queuePriority == .veryHigh)
    }

    @Test func changePriorityOfOutstandingTasks() async {
        // WHEN
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let queueObserver = OperationQueueObserver(queue: pipeline.configuration.dataLoadingQueue)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queueObserver.didAddOperation = { _ in
                if queueObserver.operations.count == 1 {
                    queueObserver.didAddOperation = nil
                    continuation.resume()
                }
            }
            prefetcher.startPrefetching(with: [Test.url])
        }

        guard let operation = queueObserver.operations.first else {
            Issue.record("Failed to find operation")
            return
        }

        // WHEN/THEN
        #expect(operation.queuePriority == .low)

        var kvoObservation: NSKeyValueObservation?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            kvoObservation = operation.observe(\.queuePriority, options: [.new]) { op, _ in
                #expect(op.queuePriority == .veryLow)
                continuation.resume()
            }
            prefetcher.priority = .veryLow
        }
        _ = kvoObservation
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

    // MARK: Misc

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
