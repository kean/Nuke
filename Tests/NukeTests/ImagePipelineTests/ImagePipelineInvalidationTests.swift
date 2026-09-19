// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

/// `invalidate()` hops to the pipeline actor, so the tests wait for it to
/// take effect – by waiting for an outstanding task to get cancelled – before
/// they make any new requests.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineInvalidationTests {
    private let dataLoader: MockDataLoader
    private let imageCache: MockImageCache
    private let observer: ImagePipelineObserver
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let observer = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.observer = observer
        self.pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
    }

    // MARK: - Outstanding Tasks

    @Test func invalidateCancelsEveryOutstandingTask() async throws {
        // Given three image tasks and a data request, each with its own download
        let urls = (0..<3).map { URL(string: "http://test.com/\($0).jpeg")! }
        let pipeline = self.pipeline
        let (tasks, dataTask) = await startSuspended(count: urls.count + 1) {
            (urls.map { pipeline.imageTask(with: $0) },
             Task { try await pipeline.data(for: ImageRequest(url: URL(string: "http://test.com/data.jpeg"))) })
        }
        #expect(await pipeline.taskCount == 4)

        // When
        pipeline.invalidate()

        // Then they fail with the regular cancellation error
        for task in tasks {
            await #expect(throws: ImagePipeline.Error.cancelled) {
                try await task.response
            }
            #expect(task.status.result?.error == .cancelled)
        }
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await dataTask.value
        }
        #expect(await pipeline.taskCount == 0)
        // The delegate isn't told about the data requests
        #expect(observer.cancelledTaskCount == 3)
    }

    // MARK: - New Requests

    /// "Any new requests will immediately fail" – including the ones the
    /// memory cache could answer without doing any work.
    @Test func memoryCacheHitsFailAfterInvalidation() async throws {
        // Given
        imageCache[Test.request] = Test.container
        await invalidate()

        // When/Then
        await #expect(throws: ImagePipeline.Error.pipelineInvalidated) {
            try await pipeline.image(for: Test.request)
        }
        // The cache itself stays accessible
        #expect(pipeline.cache[Test.request] != nil)
    }

    @Test func dataRequestsFailAfterInvalidation() async throws {
        // Given
        await invalidate()
        let createdTaskCount = dataLoader.createdTaskCount

        // When/Then
        await #expect(throws: ImagePipeline.Error.pipelineInvalidated) {
            try await pipeline.data(for: ImageRequest(url: URL(string: "http://test.com/data.jpeg")))
        }
        #expect(dataLoader.createdTaskCount == createdTaskCount)
    }

    @Test func tasksCreatedAfterInvalidationAreNeverStarted() async throws {
        // Given
        await invalidate()
        let startedTaskCount = observer.startedTaskCount

        // When
        let task = pipeline.imageTask(with: ImageRequest(url: URL(string: "http://test.com/late.jpeg")))
        await #expect(throws: ImagePipeline.Error.pipelineInvalidated) {
            try await task.response
        }

        // Then the delegate learns about the task and how it ended, but it's
        // never reported as started
        #expect(observer.startedTaskCount == startedTaskCount)
        #expect(Array(observer.events.suffix(2)) == [
            .created,
            .completed(result: .failure(.pipelineInvalidated))
        ])
        #expect(!task.isCancelled)
        #expect(await pipeline.taskCount == 0)
    }

    // MARK: - Helpers

    /// Starts the tasks and waits until the pipeline registers all of them,
    /// leaving the downloads suspended.
    private func startSuspended<T>(count: Int, _ body: () -> T) async -> T {
        dataLoader.isSuspended = true
        let didStart = TestExpectation()
        let startedCount = OSAllocatedUnfairLock(initialState: 0)
        pipeline.onTaskStarted = { _ in
            let started = startedCount.withLock {
                $0 += 1
                return $0
            }
            if started == count {
                didStart.fulfill()
            }
        }
        let result = body()
        await didStart.wait()
        pipeline.onTaskStarted = nil
        return result
    }

    /// Invalidates the pipeline and waits until the invalidation takes effect.
    private func invalidate() async {
        let task = await startSuspended(count: 1) {
            pipeline.imageTask(with: ImageRequest(url: URL(string: "http://test.com/outstanding.jpeg")))
        }
        pipeline.invalidate()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
    }
}
