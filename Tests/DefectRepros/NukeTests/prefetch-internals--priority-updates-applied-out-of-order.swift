// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: `ImagePrefetcher.priority` updates can reach the outstanding
// prefetches out of order, leaving them at a stale priority.
//
// Sources/Nuke/Prefetching/ImagePrefetcher.swift:39
//
//     Task { @ImagePipelineActor in self.didUpdatePriority(to: newValue) }
//
// Each update schedules its own hop to the pipeline actor and applies the
// value it captured. The hops carry no ordering guarantee: the actor runs
// queued jobs by priority, and an unstructured `Task` inherits the priority
// of the thread that sets the property. So when the property is set from a
// background thread and then from a user-initiated one, the second hop runs
// first and the first one lands last with the stale value.
//
// This is the same defect that was fixed for `ImageTask.priority` in
// https://github.com/kean/Nuke/pull/918 ("Fix `ImageTask/priority` updates
// being applied out of order, leaving the running task at a stale priority"),
// where the hop now reads `self.priority` instead of capturing `newValue`.
// The prefetcher's copy of the pattern wasn't updated.
//
// Expected: `prefetcher.priority == .veryLow` and the outstanding prefetch
//           runs at `.veryLow`.
// Actual:   `prefetcher.priority == .veryLow`, but the outstanding prefetch is
//           left at `.veryHigh` – the doc says "Changing the priority also
//           changes the priority of all of the outstanding tasks".
@Suite(.timeLimit(.minutes(5)))
struct ImagePrefetcherPriorityOrderBugRepro {
    @Test @ImagePipelineActor func priorityUpdatesNeverApplyAStaleValue() async throws {
        // GIVEN a prefetch that is scheduled, but not started
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        let prefetcher = ImagePrefetcher(pipeline: pipeline)
        prefetcher.isPaused = true
        let operations = await prefetcher.queue.waitForOperations(count: 1) {
            prefetcher.startPrefetching(with: [Test.url])
        }
        let operation = try #require(operations.first)

        // WHEN the priority is raised from a background thread and then
        // lowered from a user-initiated one while the actor is busy, so both
        // hops are queued before either runs
        let applied = TestExpectation()
        setPriorityFromThreadsWithDifferentQoS(prefetcher, then: applied)
        await applied.wait()

        // THEN the outstanding prefetch ends up at the latest priority
        #expect(prefetcher.priority == .veryLow)
        #expect(operation.priority == .veryLow)
    }
}

/// Runs synchronously on the pipeline actor so that none of the hops can run
/// before all of them are queued. `applied` is fulfilled by a hop at the
/// lowest priority queued last, so it runs after both updates.
private func setPriorityFromThreadsWithDifferentQoS(_ prefetcher: ImagePrefetcher, then applied: TestExpectation) {
    let group = DispatchGroup()
    DispatchQueue.global(qos: .background).async(group: group) {
        prefetcher.priority = .veryHigh
    }
    group.wait()
    DispatchQueue.global(qos: .userInitiated).async(group: group) {
        prefetcher.priority = .veryLow
    }
    group.wait()
    DispatchQueue.global(qos: .background).async(group: group) {
        Task { @ImagePipelineActor in applied.fulfill() }
    }
    group.wait()
}
