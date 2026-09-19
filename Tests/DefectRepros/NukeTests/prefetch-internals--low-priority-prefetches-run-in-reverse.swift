// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

// SUSPECTED BUG: at its default priority (`.low`), and at `.veryLow`, the
// prefetcher starts the queued requests in reverse order.
//
// Sources/Nuke/Prefetching/ImagePrefetcher.swift:149-157
//
//     let operation = queue.add { ... }                   // enqueued at .normal
//     operation.priority = request.priority.taskPriority  // then lowered
//
// `TaskQueue.add` always enqueues at `.normal`. When the priority is lowered
// right after, `TaskQueue.operationPriorityChanged` treats the operation as one
// that "was once higher priority" and *prepends* it to the lower bucket
// (Sources/Nuke/Pipeline/TaskQueue.swift:150-152). Every request that can't
// start right away is therefore put in front of the ones queued before it, so
// the queue is LIFO instead of the FIFO that `TaskQueue` documents for work of
// the same priority. At `.normal` and above the order is preserved, which is
// what shows the reversal is an artifact of add-then-lower rather than a
// design choice.
//
// Impact: `UICollectionViewDataSourcePrefetching` hands the index paths
// nearest to the viewport first. With the default prefetcher, a batch of
// [32...55] loads 32, 33, then 55, 54, ... 34 – the farthest images first.
//
// Expected: the image tasks are created in the order the URLs were passed:
//           [0, 1, 2, 3, 4, 5]
// Actual (.low / .veryLow): [0, 1, 5, 4, 3, 2] (the first two run right away,
//           the rest are reversed). `.normal` and `.high` pass.
@Suite(.timeLimit(.minutes(5)))
struct ImagePrefetcherRequestOrderBugRepro {
    @Test(arguments: [ImageRequest.Priority.low, .veryLow, .normal, .high])
    @ImagePipelineActor func prefetchesStartInTheOrderTheyWereRequested(priority: ImageRequest.Priority) async {
        // GIVEN a prefetcher with the default configuration
        let dataLoader = MockDataLoader()
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let prefetcher = ImagePrefetcher(pipeline: pipeline)
        prefetcher.priority = priority
        let order = OSAllocatedUnfairLock<[Int]>(initialState: [])
        observer.onTaskCreated = { task in
            let index = Int(task.request.url!.deletingPathExtension().lastPathComponent)!
            order.withLock { $0.append(index) }
        }
        let urls = (0..<6).map { URL(string: "http://test.com/\($0).jpeg")! }

        // WHEN
        let done = TestExpectation()
        prefetcher.didComplete = { done.fulfill() }
        prefetcher.startPrefetching(with: urls)
        await done.wait()

        // THEN
        #expect(order.withLock { $0 } == [0, 1, 2, 3, 4, 5], "priority: \(priority)")
    }
}
