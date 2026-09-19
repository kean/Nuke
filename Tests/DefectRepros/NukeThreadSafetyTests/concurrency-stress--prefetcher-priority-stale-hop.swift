// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation

// SUSPECTED BUG: `ImagePrefetcher.priority` can leave the outstanding
// prefetches at a stale priority.
//
// The setter stores the new value under a lock synchronously and then
// propagates it with `Task { @ImagePipelineActor in
// self.didUpdatePriority(to: newValue) }`, capturing `newValue`. Those hops are
// not ordered: the actor runs its queued jobs by priority, so a hop made from a
// higher-QoS thread overtakes one made earlier from a lower-QoS thread. The
// stale hop lands last and re-applies the *older* value to every outstanding
// task, while `prefetcher.priority` keeps reporting the newer one – forever.
//
// `ImageTask.priority` had exactly this problem and fixed it by reading the
// current value inside the hop ("Read the priority instead of capturing
// `newValue`: the hops are unordered, so a stale value could land last",
// Sources/Nuke/ImageTask.swift:307-309). The prefetcher didn't get the fix.
//
// Expected: once both hops ran, the pending prefetch operation has the priority
// the prefetcher reports (`.veryLow`, set last). The docs promise "Changing the
// priority also changes the priority of all of the outstanding tasks managed by
// the prefetcher" and "All ImagePrefetcher methods are thread-safe".
// Actual: `prefetcher.priority == .veryLow`, but the outstanding operation (and
// the request it will start the image task with) ends up at `.veryHigh`.
//
// The test holds the pipeline actor for a moment – standing in for an actor that
// is busy, which it routinely is while images load – so that both hops are
// queued before either runs; that is what makes the reordering deterministic.
//
// Location: Sources/Nuke/Prefetching/ImagePrefetcher.swift:39
@Suite(.timeLimit(.minutes(5)))
struct ImagePrefetcherPriorityStaleHopRepro {
    @Test func lastPrioritySetWinsForOutstandingTasks() async throws {
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let prefetcher = ImagePrefetcher(pipeline: pipeline)
        prefetcher.isPaused = true // Keep the prefetch pending in the queue

        let operations = await prefetcher.queue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.url])
        }
        let operation = try #require(operations.first)

        // Set `.veryHigh` from a background thread, then `.veryLow` from a
        // user-initiated one, while the actor is busy.
        let barrier = TestExpectation()
        setPriorityFromTwoQoSClasses(prefetcher: prefetcher, barrier: barrier)
        await barrier.wait() // Queued behind both hops

        let operationPriority = await Task { @ImagePipelineActor in operation.priority }.value
        #expect(prefetcher.priority == .veryLow)
        #expect(operationPriority == .veryLow) // Fails: .veryHigh

        prefetcher.stopPrefetching()
    }
}

private func blockOnSemaphore(_ semaphore: DispatchSemaphore) { semaphore.wait() }

private func setPriorityFromTwoQoSClasses(prefetcher: ImagePrefetcher, barrier: TestExpectation) {
    let entered = DispatchSemaphore(value: 0)
    let gate = DispatchSemaphore(value: 0)
    Task.detached { @ImagePipelineActor in
        entered.signal()
        blockOnSemaphore(gate)
    }
    entered.wait()

    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .background).async {
        prefetcher.priority = .veryHigh
        done.signal()
    }
    done.wait()
    DispatchQueue.global(qos: .userInitiated).async {
        prefetcher.priority = .veryLow
        done.signal()
    }
    done.wait()
    // Same priority as the first hop and enqueued after it, so it runs after it.
    DispatchQueue.global(qos: .background).async {
        Task { @ImagePipelineActor in barrier.fulfill() }
        done.signal()
    }
    done.wait()
    gate.signal()
}
