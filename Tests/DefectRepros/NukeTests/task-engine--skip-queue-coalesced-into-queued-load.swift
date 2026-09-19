// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// Suspected bug: `ImageRequest.Options.skipDataLoadingQueue` has no effect when
// a request for the same resource without the option is waiting in
// `dataLoadingQueue`.
//
// The option is documented as (Sources/Nuke/ImageRequest.swift:339-344):
//
//     Perform data loading immediately, ignoring `dataLoadingQueue`. It can be
//     used to elevate priority of certain tasks.
//
//     - important: If there is an outstanding task for loading the same
//     resource but without this option, a new task will be created.
//
// The options are part of `TaskLoadImageKey`, so a new `TaskLoadImage` is
// indeed created, but it immediately subscribes to
// `pipeline.makeTaskFetchOriginalImage(for:)`, whose key
// (`TaskFetchOriginalImageKey` -> `TaskFetchOriginalDataKey`,
// Sources/Nuke/Internal/ImageRequestKeys.swift:86-141) ignores the options.
// The request joins the outstanding `TaskFetchOriginalData`, which was
// created for the first request and waits for a slot in `dataLoadingQueue`.
// The option is never looked at again – `TaskFetchOriginalData.loadData`
// reads it from the *first* request.
//
// This is exactly the case the option exists for: a prefetcher (or any
// low-priority request) queued behind a saturated `dataLoadingQueue`, then
// the image is needed on screen right away.
//
// Expected: the request with `.skipDataLoadingQueue` starts loading
// immediately and completes while the queue is still busy.
// Actual: it waits in the queue with the first request – the data loader
// isn't even called – and only completes once the queue gets to it.
@Suite(.timeLimit(.minutes(2)))
struct TaskEngineReproSkipDataLoadingQueueCoalescingTests {
    @Test @ImagePipelineActor func skipDataLoadingQueueIsHonoredWhenTheSameResourceIsQueued() async throws {
        // Given a request for the image waiting for a slot in the data loading queue
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true // Stands in for a queue saturated with other downloads
        let queued = await queue.waitForOperations(count: 1) {
            _ = pipeline.imageTask(with: Test.request)
        }
        #expect(queued.count == 1)

        // When the same image is requested with `.skipDataLoadingQueue`
        let request = ImageRequest(url: Test.url, options: [.skipDataLoadingQueue])
        let task = pipeline.imageTask(with: request)
        let didFinish = TestExpectation()
        Task.detached {
            _ = try? await task.response
            didFinish.fulfill()
        }
        await didFinish.wait(timeout: .seconds(10)) // Fails: times out

        // Then it loads the data right away, bypassing the queue
        #expect(dataLoader.createdTaskCount == 1) // Fails: 0
        #expect(task.status.result?.isSuccess == true) // Fails: nil

        queue.isSuspended = false
    }
}
