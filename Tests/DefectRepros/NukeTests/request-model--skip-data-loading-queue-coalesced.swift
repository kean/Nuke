// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: `ImageRequest.Options.skipDataLoadingQueue` waits in the data
// loading queue when a request for the same resource without the option is
// already queued. (Found independently of data-loading-tasks--skip-data-
// loading-queue-joins-queued-fetch.swift and task-engine--skip-queue-
// coalesced-into-queued-load.swift; same root cause.)
//
// Docs (Sources/Nuke/ImageRequest.swift:339): "Perform data loading
// immediately, ignoring `dataLoadingQueue`. [...] If there is an outstanding
// task for loading the same resource but without this option, a new task will
// be created."
//
// Expected: the request with the option loads right away.
// Actual: `TaskLoadImageKey` includes the options, so a new `TaskLoadImage` is
// created, but `TaskFetchOriginalImageKey` and `TaskFetchOriginalDataKey`
// (Sources/Nuke/Internal/ImageRequestKeys.swift) don't, so it subscribes to
// the outstanding `TaskFetchOriginalData`, which sits in the queue. The data
// loader is never called; the request finishes only when the queue gets to
// the other one. Typical case: `ImagePrefetcher` queued the URL at `.low`
// and the screen then asks for it with `.skipDataLoadingQueue`.
@Suite(.timeLimit(.minutes(1)))
struct RequestModelBugSkipDataLoadingQueueTests {
    @Test @ImagePipelineActor func skipsQueueWhenSameResourceIsQueued() async throws {
        // Given a request for the URL waiting in the suspended queue
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        let expectation = TestExpectation(queue: queue, count: 1)
        let queuedTask = pipeline.imageTask(with: ImageRequest(url: Test.url))
        await expectation.wait()

        // When the same URL is requested with `.skipDataLoadingQueue`
        let request = ImageRequest(url: Test.url, options: [.skipDataLoadingQueue])
        let isLoaded = await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await pipeline.image(for: request)) != nil }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        // Then it's loaded without waiting for the queue
        #expect(isLoaded)
        #expect(dataLoader.createdTaskCount == 1)

        queue.isSuspended = false
        _ = try? await queuedTask.response
    }
}
