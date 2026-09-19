// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: `.skipDataLoadingQueue` is ignored for requests created with
// `ImageRequest(id:image:)`.
//
// Expected: "Perform data loading immediately, ignoring
// `dataLoadingQueue`. It can be used to elevate priority of certain tasks."
// URL requests (`TaskFetchOriginalData.loadData(urlRequest:)`) and
// `ImageRequest(id:data:)` (`TaskFetchOriginalData.loadAsyncData`) both run
// the load outside of the queue when the option is set.
//
// Actual: `TaskFetchOriginalImage.loadAsyncImage` always adds the closure to
// `dataLoadingQueue`, so with the option set the closure still waits for a
// free slot – here, forever, since the queue is suspended.
//
// Sources/Nuke/Tasks/TaskFetchOriginalImage.swift:138
@Suite(.timeLimit(.minutes(5)))
struct ImageClosureSkipDataLoadingQueueBugRepro {
    @Test func imageClosureSkipsTheDataLoadingQueue() async throws {
        // GIVEN a data loading queue that runs nothing
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let didCallClosure = TestExpectation()
        let request = ImageRequest(
            id: "closure-image",
            image: {
                didCallClosure.fulfill()
                return Test.container
            },
            options: [.skipDataLoadingQueue]
        )

        // WHEN
        let task = pipeline.imageTask(with: request)

        // THEN the closure runs anyway
        await didCallClosure.wait(timeout: .seconds(10)) // Actual: times out
        task.cancel()
    }

    /// The same request with `ImageRequest(id:data:)` works.
    @Test func dataClosureSkipsTheDataLoadingQueue() async throws {
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let request = ImageRequest(id: "closure-data", data: { Test.data }, options: [.skipDataLoadingQueue])
        _ = try await pipeline.imageTask(with: request).response // Passes
    }
}
