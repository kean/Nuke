// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Tasks joining and leaving the work they share.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineCoalescingLifecycleTests {
    private let dataLoader: MockDataLoader
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Data and Image Requests

    @Test func dataAndImageRequestsShareOneDownload() async throws {
        // Given
        let pipeline = self.pipeline
        let (imageTask, dataTask) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), Task { try await pipeline.data(for: Test.request) })
        }

        // When
        let response = try await imageTask.response
        let (data, _) = try await dataTask.value

        // Then
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(data == Test.data)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func cancellingTheImageTaskKeepsTheSharedDownloadForTheDataRequest() async throws {
        // Given
        let pipeline = self.pipeline
        let (imageTask, dataTask) = await startSuspended(for: pipeline, count: 2) {
            (pipeline.imageTask(with: Test.request), Task { try await pipeline.data(for: Test.request) })
        }

        // When
        imageTask.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await imageTask.response
        }
        dataLoader.isSuspended = false

        // Then
        let (data, _) = try await dataTask.value
        #expect(data == Test.data)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Processing

    /// Both requests share the work of the first processor, which one of them
    /// requested directly. It has to keep going for the other one when that
    /// request is gone.
    @Test func cancellingTheRequestThatStartedSharedProcessingKeepsItForTheOthers() async throws {
        // Given
        let processors = MockProcessorFactory()
        let first = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let second = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])
        let (task1, task2) = await startSuspended(for: pipeline, count: 2) {
            (pipeline.imageTask(with: first), pipeline.imageTask(with: second))
        }

        // When
        task1.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task1.response
        }
        dataLoader.isSuspended = false

        // Then
        let response = try await task2.response
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(processors.numberOfProcessorsApplied == 2)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Joining

    /// The work of the cancelled tasks is disposed of and must not be picked
    /// up by a new request, which would otherwise never finish.
    @Test func requestAfterEveryTaskWasCancelledStartsNewWork() async throws {
        // Given two tasks sharing a download that are both cancelled
        let didStartLoading = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let (task1, task2) = await startSuspended(for: pipeline, count: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }
        await didStartLoading.wait()
        task1.cancel()
        task2.cancel()
        for task in [task1, task2] {
            await #expect(throws: ImagePipeline.Error.cancelled) {
                try await task.response
            }
        }

        // When
        dataLoader.isSuspended = false
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func taskJoiningInTheMiddleOfTheDownloadGetsTheSameImage() async throws {
        // Given a download that already delivered its first chunk
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let first = pipeline.imageTask(with: Test.request)
        while first.status.progress.completed == 0 {
            await Task.yield()
        }

        // When another task for the same image joins it
        let didStart = TestExpectation()
        pipeline.onTaskStarted = { _ in didStart.fulfill() }
        let second = pipeline.imageTask(with: Test.request)
        await didStart.wait()
        pipeline.onTaskStarted = nil
        // The chunks reach the pipeline actor after the task subscribes: the
        // pipeline starts the task and subscribes it in one go.
        dataLoader.resumeServingChunks(dataLoader.chunks.count)

        // Then both get the one image the download produced
        let response1 = try await first.response
        let response2 = try await second.response
        #expect(response1.image === response2.image)
        #expect(second.status.progress == first.status.progress)
    }
}
