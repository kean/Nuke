// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation
import os

// MARK: - TaskQueue

@Suite(.timeLimit(.minutes(5)))
struct TaskQueueContentionTests {
    /// Work is added, re-prioritized, and cancelled on the actor while other
    /// threads suspend and resume the queue and move its limit between one
    /// and three. The limit is never exceeded, and every operation either
    /// runs exactly once or was cancelled before it started – in which case
    /// it never runs – and the queue ends up idle.
    @Test @ImagePipelineActor func everyOperationRunsOnceOrIsCancelledBeforeItStarts() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 3)
        let tracker = OperationTracker()
        let isDone = OSAllocatedUnfairLock(initialState: false)
        let togglers = Task.detached {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    while !isDone.withLock({ $0 }) {
                        queue.isSuspended.toggle()
                        await Task.yield()
                    }
                    queue.isSuspended = false
                }
                group.addTask {
                    var isLow = true
                    while !isDone.withLock({ $0 }) {
                        queue.maxConcurrentTaskCount = isLow ? 1 : 3
                        isLow.toggle()
                        await Task.yield()
                    }
                    queue.maxConcurrentTaskCount = 3
                }
            }
        }

        // When
        var operations: [TaskQueue.Operation] = []
        for index in 0..<1000 {
            let operation = queue.add {
                tracker.begin(index)
                await Task.yield()
                tracker.end()
            }
            operation.priority = TaskPriority.allCases.randomElement()!
            operations.append(operation)

            let otherIndex = Int.random(in: 0..<operations.count)
            let other = operations[otherIndex]
            switch Int.random(in: 0..<10) {
            case 0:
                tracker.cancel(otherIndex, isCancelled: other.isCancelled)
                other.cancel()
            case 1, 2:
                other.priority = TaskPriority.allCases.randomElement()!
            default:
                break
            }
            if index % 8 == 0 {
                await Task.yield() // Let the queue make progress
            }
        }
        isDone.withLock { $0 = true }
        await togglers.value
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(tracker.maxInFlight <= 3)
        #expect(tracker.maxInFlight >= 1)
        for index in operations.indices {
            let runs = tracker.runs[index, default: 0]
            if tracker.cancelledBeforeStart.contains(index) {
                #expect(runs == 0, "operation \(index) ran after it was cancelled")
            } else {
                #expect(runs == 1, "operation \(index) ran \(runs) times")
            }
        }
        #expect(queue.runningCount == 0)
        #expect(queue.pendingCount == 0)
    }
}

@ImagePipelineActor
private final class OperationTracker {
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var runs: [Int: Int] = [:]
    private(set) var cancelledBeforeStart: Set<Int> = []
    private var started: Set<Int> = []

    func begin(_ index: Int) {
        started.insert(index)
        runs[index, default: 0] += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
    }

    func end() {
        inFlight -= 1
    }

    /// Records a cancellation that comes before the operation started, which
    /// is when the queue promises the work never runs.
    func cancel(_ index: Int, isCancelled: Bool) {
        if !isCancelled && !started.contains(index) {
            cancelledBeforeStart.insert(index)
        }
    }
}

// MARK: - ImagePrefetcher

@Suite(.timeLimit(.minutes(5)))
struct ImagePrefetcherContentionTests {
    /// Starts, stops, pauses, and priority changes from many threads never
    /// wedge the prefetcher: after the storm, a new batch is prefetched into
    /// the memory cache, and stopping everything leaves no work behind.
    @Test func prefetcherRecoversFromAStartStopStorm() async {
        // Given
        let dataLoader = MockDataLoader()
        let imageCache = ImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.isRateLimiterEnabled = false
        }
        let prefetcher = ImagePrefetcher(pipeline: pipeline, maxConcurrentRequestCount: 3)
        let stormURLs = (0..<30).map { URL(string: "https://example.com/storm/\($0).jpeg")! }

        // When
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for iteration in 0..<150 {
                let urls = Array(stormURLs.shuffled().prefix(Int.random(in: 0..<6)))
                switch Int.random(in: 0..<10) {
                case 0..<5: prefetcher.startPrefetching(with: urls)
                case 5..<8: prefetcher.stopPrefetching(with: urls)
                case 8: prefetcher.isPaused = Bool.random()
                default: prefetcher.priority = iteration % 2 == 0 ? .high : .low
                }
                if iteration % 50 == 0 {
                    imageCache.removeAll()
                }
            }
            prefetcher.isPaused = false
        }
        #expect(!prefetcher.isPaused)
        #expect([.high, .low].contains(prefetcher.priority))

        // Then a new batch still loads
        let freshURLs = (0..<10).map { URL(string: "https://example.com/fresh/\($0).jpeg")! }
        let freshKeys = freshURLs.map { ImageCacheKey(request: ImageRequest(url: $0)) }
        let loaded = TestExpectation()
        prefetcher.didComplete = {
            // Also runs when the storm's leftovers finish; wait for the batch.
            if freshKeys.allSatisfy({ imageCache[$0] != nil }) {
                loaded.fulfill()
            }
        }
        prefetcher.startPrefetching(with: freshURLs)
        await loaded.wait()

        // And stopping everything leaves no work behind
        prefetcher.stopPrefetching()
        await prefetcher.queue.waitUntilAllOperationsAreFinished()
        #expect(await pipeline.taskCount == 0)
    }
}
