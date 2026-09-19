// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG (docs vs behavior): a request with `.skipDataLoadingQueue` that arrives
// while an equivalent request *without* the option waits in the data loading
// queue joins that queued fetch and waits in the queue too.
//
// Sources/Nuke/ImageRequest.swift, `Options.skipDataLoadingQueue`:
//
//     /// Perform data loading immediately, ignoring dataLoadingQueue. It
//     /// can be used to elevate priority of certain tasks.
//     ///
//     /// - important: If there is an outstanding task for loading the same
//     /// resource but without this option, a new task will be created.
//
// But `TaskFetchOriginalDataKey` and `TaskFetchOriginalImageKey`
// (Sources/Nuke/Internal/ImageRequestKeys.swift) don't include the options,
// so the new `TaskLoadImage`/`TaskLoadData` subscribes to the existing
// `TaskFetchOriginalImage` → `TaskFetchOriginalData`, whose operation is
// sitting in the (here suspended) `dataLoadingQueue`. The option is read from
// the request the fetch was created with, so it's ignored for the joiner.
//
// Expected: the `.skipDataLoadingQueue` request loads immediately, per the docs.
// Actual:   it waits for the queue (here: forever, as the queue is suspended);
//           the test records a timeout.

@Suite(.timeLimit(.minutes(5)))
struct SkipDataLoadingQueueJoinsQueuedFetchBugTests {
    @Test @ImagePipelineActor func requestSkippingTheQueueDoesNotWaitForAQueuedEquivalent() async throws {
        // GIVEN a request waiting in a suspended data loading queue
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        let enqueued = TestExpectation(queue: queue, count: 1)
        let queuedTask = pipeline.imageTask(with: Test.request)
        await enqueued.wait()

        // WHEN the same image is requested with `.skipDataLoadingQueue`
        let finished = TestExpectation()
        let urgentTask = pipeline.imageTask(with: ImageRequest(url: Test.url, options: [.skipDataLoadingQueue]))
        Task {
            _ = try? await urgentTask.response
            finished.fulfill()
        }

        // THEN it loads without waiting for the queue
        await finished.wait(timeout: .seconds(10))
        #expect(urgentTask.status.result != nil)

        queue.isSuspended = false
        _ = try? await queuedTask.response
    }
}
