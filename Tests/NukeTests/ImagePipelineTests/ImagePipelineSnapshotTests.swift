// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineSnapshotTests {
    private let dataLoader = MockDataLoader()

    private func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataCache = nil
            configure(&$0)
        }
    }

    /// Waits for the tasks to reach the pipeline: they start asynchronously.
    private func snapshot(of pipeline: ImagePipeline, untilTaskCount count: Int) async -> ImagePipeline.Diagnostics.Snapshot {
        var snapshot = await pipeline.diagnostics.snapshot()
        while snapshot.tasks.count != count {
            await Task.yield()
            snapshot = await pipeline.diagnostics.snapshot()
        }
        return snapshot
    }

    @Test func idlePipeline() async {
        let snapshot = await makePipeline().diagnostics.snapshot()

        #expect(snapshot.tasks.isEmpty)
        #expect(!snapshot.isInvalidated)
        #expect(snapshot.queues.map(\.name) == ["dataLoadingQueue", "imageDecodingQueue", "imageEncodingQueue", "imageProcessingQueue", "imageDecompressingQueue"])
        #expect(snapshot.queues.allSatisfy { $0.runningCount == 0 && $0.pendingCount == 0 && !$0.isSuspended })
        #expect(snapshot.memoryCache == nil)
        #expect(!snapshot.hasDataCache)
        #expect(snapshot.description.contains(" · 0 tasks"))
    }

    @Test func tasksInFlight() async throws {
        // GIVEN a download that doesn't finish
        dataLoader.isSuspended = true
        let pipeline = makePipeline()
        var request = ImageRequest(url: URL(string: "https://example.com/image.jpeg?token=secret"))
        request.priority = .high

        // WHEN
        let task = pipeline.imageTask(with: request)
        let snapshot = await snapshot(of: pipeline, untilTaskCount: 1)

        // THEN
        let active = try #require(snapshot.tasks.first)
        #expect(active.taskID == task.taskID)
        #expect(active.kind == .image)
        #expect(active.resource == "https://example.com/image.jpeg?…")
        #expect(active.priority == .high)
        #expect(active.age == nil) // Diagnostics are off
        #expect(snapshot.description.contains("#\(task.taskID) · high · https://example.com/image.jpeg?…"))
        #expect(!snapshot.description.contains("secret"))

        task.cancel()
    }

    @Test func tasksAreOldestFirst() async {
        dataLoader.isSuspended = true
        let pipeline = makePipeline()

        let tasks = (0..<3).map { pipeline.imageTask(with: URL(string: "https://example.com/\($0).jpeg")!) }
        let snapshot = await snapshot(of: pipeline, untilTaskCount: 3)

        #expect(snapshot.tasks.map(\.taskID).sorted() == tasks.map(\.taskID))
        #expect(snapshot.tasks.map(\.taskID) == snapshot.tasks.map(\.taskID).sorted())

        tasks.forEach { $0.cancel() }
    }

    @Test func taskAgeWithDiagnosticsOn() async {
        dataLoader.isSuspended = true
        let pipeline = makePipeline { $0.isDiagnosticsEnabled = true }

        let task = pipeline.imageTask(with: Test.request)
        let snapshot = await snapshot(of: pipeline, untilTaskCount: 1)

        #expect((snapshot.tasks.first?.age ?? -1) >= 0)

        task.cancel()
    }

    @Test func queuesReportWhatIsWaiting() async throws {
        // GIVEN a queue that takes one download at a time
        dataLoader.isSuspended = true
        let pipeline = makePipeline {
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }

        // WHEN
        let tasks = (0..<3).map { pipeline.imageTask(with: URL(string: "https://example.com/\($0).jpeg")!) }
        var queue = await snapshot(of: pipeline, untilTaskCount: 3).queues[0]
        while queue.pendingCount != 2 {
            await Task.yield()
            queue = await pipeline.diagnostics.snapshot().queues[0]
        }

        // THEN
        #expect(queue.name == "dataLoadingQueue")
        #expect(queue.runningCount == 1)
        #expect(queue.limit == 1)

        let description = await pipeline.diagnostics.snapshot().description
        #expect(description.contains("dataLoadingQueue         1/1 running · 2 pending"))

        tasks.forEach { $0.cancel() }
    }

    @Test func suspendedQueueIsReported() async {
        let pipeline = makePipeline()
        pipeline.configuration.dataLoadingQueue.isSuspended = true

        let snapshot = await pipeline.diagnostics.snapshot()

        #expect(snapshot.queues[0].isSuspended)
        #expect(snapshot.description.contains("0/6 running · suspended"))
    }

    @Test func memoryCache() async {
        let cache = ImageCache()
        let pipeline = makePipeline { $0.imageCache = cache }
        cache[ImageCacheKey(key: "a")] = Test.container

        let snapshot = await pipeline.diagnostics.snapshot()

        #expect(snapshot.memoryCache?.count == 1)
        #expect(snapshot.memoryCache?.cost == cache.totalCost)
        #expect(snapshot.memoryCache?.costLimit == cache.costLimit)
        #expect(snapshot.description.contains("memory cache: 1 image · "))
    }

    @Test func invalidatedPipeline() async {
        let pipeline = makePipeline()

        pipeline.invalidate()
        var snapshot = await pipeline.diagnostics.snapshot()
        while !snapshot.isInvalidated {
            await Task.yield()
            snapshot = await pipeline.diagnostics.snapshot()
        }

        #expect(snapshot.description.contains(" · invalidated"))
    }

    /// `po` can't `await`, and that's where the report is needed most.
    @Test func debugDescriptionIsTheSnapshot() async {
        dataLoader.isSuspended = true
        let pipeline = makePipeline()

        let task = pipeline.imageTask(with: Test.request)
        let snapshot = await snapshot(of: pipeline, untilTaskCount: 1)
        let diagnostics = pipeline.diagnostics
        let description = await Task.detached { diagnostics.debugDescription }.value

        #expect(description == snapshot.description)

        task.cancel()
    }

    @Test func descriptionCutsTheListOfTasksOff() async {
        dataLoader.isSuspended = true
        let pipeline = makePipeline()

        let tasks = (0..<53).map { pipeline.imageTask(with: URL(string: "https://example.com/\($0).jpeg")!) }
        let snapshot = await snapshot(of: pipeline, untilTaskCount: 53)

        #expect(snapshot.description.contains("… and 3 more"))

        tasks.forEach { $0.cancel() }
    }
}
