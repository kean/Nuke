// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Equivalent requests share the work – the download, the decoding, and each
/// processing step – and the tasks join and leave the work they share.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineCoalescingTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Deduplication

    @Test func deduplicationGivenSameURLDifferentSameProcessors() async throws {
        // Given requests with the same URLs and same processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])

        // When loading images for those requests
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }

        let response1 = try await task1.response
        #expect(response1.image.nk_test_processorIDs == ["1"])
        _ = try await task2.response

        // Then the original image is loaded once
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func deduplicationGivenSameURLDifferentProcessors() async throws {
        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])

        // When loading images for those requests
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        _ = try await task1.response
        _ = try await task2.response

        // Then the original image is loaded once, but both processors are applied
        #expect(processors.numberOfProcessorsApplied == 2)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func noDeduplicationGivenNonEquivalentRequests() async throws {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))

        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        _ = try await task1.response
        _ = try await task2.response

        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func equivalentRequestsShareOneDownload() async throws {
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }
        _ = try await task1.response
        _ = try await task2.response

        #expect(dataLoader.createdTaskCount == 1)
    }

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

    @Test func dataOnlyLoadedOnceWithDifferentCachePolicyPassingURL() async throws {
        // Given
        let dataCache = MockDataCache()
        let pipeline = pipeline.reconfigured {
            $0.dataCache = dataCache
        }

        // When - One request reloading cache data, another one not
        @Sendable func makeRequest(options: ImageRequest.Options) -> ImageRequest {
            ImageRequest(urlRequest: URLRequest(url: Test.url), options: options)
        }

        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: makeRequest(options: [])),
             pipeline.imageTask(with: makeRequest(options: [.reloadIgnoringCachedData])))
        }
        _ = try await task1.response
        _ = try await task2.response

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func disablingDeduplication() async throws {
        // Given
        let pipeline = ImagePipeline {
            $0.imageCache = nil
            $0.dataLoader = dataLoader
            $0.isTaskCoalescingEnabled = false
        }

        // When/Then
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }
        _ = try await task1.response
        _ = try await task2.response

        #expect(dataLoader.createdTaskCount == 2)
    }

    // MARK: - Scale

#if !os(macOS)
    @Test func overridingImageScale() async throws {
        // GIVEN requests with the same URLs but different scale
        let request1 = ImageRequest(url: Test.url).with { $0.scale = 2 }
        let request2 = ImageRequest(url: Test.url).with { $0.scale = 3 }

        // WHEN loading images for those requests
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        let image1 = try await task1.response.image
        let image2 = try await task2.response.image

        // THEN
        #expect(image1.scale == 2)
        #expect(image2.scale == 3)
        #expect(dataLoader.createdTaskCount == 1)
    }
#endif

    // MARK: - Thumbnail

    @Test func deduplicationGivenSameURLButDifferentThumbnailOptions() async throws {
        // GIVEN requests with the same URLs but one accesses thumbnail
        let request1 = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 400) }
        let request2 = ImageRequest(url: Test.url)

        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        let image1 = try await task1.response.image
        let image2 = try await task2.response.image

        // THEN
        #expect(image1.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(image2.sizeInPixels == CGSize(width: 640.0, height: 480.0))
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func deduplicationGivenSameURLButDifferentThumbnailOptionsReversed() async throws {
        // GIVEN requests with the same URLs but one accesses thumbnail (reversed order)
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url).with {
            $0.thumbnail = .init(maxPixelSize: 400)
        }

        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        let image1 = try await task1.response.image
        let image2 = try await task2.response.image

        // THEN
        #expect(image1.sizeInPixels == CGSize(width: 640.0, height: 480.0))
        #expect(image2.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Processing

    @Test @ImagePipelineActor func processorsAreDeduplicated() async throws {
        // Given
        let processors = MockProcessorFactory()
        let queueObserver = TaskQueueObserver(queue: pipeline.configuration.imageProcessingQueue)

        // When
        let (task1, task2, task3) = await withSuspendedDataLoading(for: pipeline, expectedCount: 3) {
            (pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [processors.make(id: "1")])),
             pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [processors.make(id: "2")])),
             pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [processors.make(id: "1")])))
        }
        _ = try await task1.response
        _ = try await task2.response
        _ = try await task3.response

        // Then
        #expect(queueObserver.operations.count == 2)
        #expect(processors.numberOfProcessorsApplied == 2)
    }

    @Test func eachProcessingStepIsDeduplicated() async throws {
        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])

        // When
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        _ = try await task1.response
        _ = try await task2.response

        // Then the processor "1" is only applied once
        #expect(processors.numberOfProcessorsApplied == 2)
    }

    @Test func processingDeduplicationCanBeDisabled() async throws {
        // Given
        let pipeline = pipeline.reconfigured {
            $0.isTaskCoalescingEnabled = false
        }

        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])

        // When
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        _ = try await task1.response
        _ = try await task2.response

        // Then the processor "1" is applied twice
        #expect(processors.numberOfProcessorsApplied == 3)
    }

    @Test func correctImageIsStoredInMemoryCache() async throws {
        let imageCache = MockImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }

        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])

        // When loading images for those requests
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        let response1 = try await task1.response
        #expect(response1.image.nk_test_processorIDs == ["1"])

        let response2 = try await task2.response
        #expect(response2.image.nk_test_processorIDs == ["2"])

        // Then each image is stored under its own request
        #expect(dataLoader.createdTaskCount == 1)
        #expect(imageCache[request1] != nil)
        #expect(imageCache[request1]?.image.nk_test_processorIDs == ["1"])
        #expect(imageCache[request2] != nil)
        #expect(imageCache[request2]?.image.nk_test_processorIDs == ["2"])
    }

    @Test func eachFinalProcessedImageIsStoredInMemoryCache() async throws {
        let cache = MockImageCache()
        var conf = pipeline.configuration
        conf.imageCache = cache
        let pipeline = ImagePipeline(configuration: conf)

        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2"), processors.make(id: "3")])

        // When
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        _ = try await task1.response
        _ = try await task2.response

        // Then
        #expect(cache[request1] != nil)
        #expect(cache[request2] != nil)
        #expect(cache[ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])] == nil)
    }

    // MARK: - Joining and Leaving

    /// "The work only gets canceled when all the registered requests are."
    @Test func downloadIsCancelledOnlyWhenTheLastTaskLeaves() async throws {
        // Given two tasks that share a download in flight
        let didStartLoading = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let (task1, task2) = await startSuspended(for: pipeline, count: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }
        await didStartLoading.wait()
        let cancelledDownloads = LockedArray<Void>()
        let observation = NotificationCenter.default.addObserver(forName: MockDataLoader.DidCancelTask, object: dataLoader, queue: nil) { _ in
            cancelledDownloads.append(())
        }
        defer { NotificationCenter.default.removeObserver(observation) }

        // When the first one leaves
        task1.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task1.response
        }
        await drainPipeline()

        // Then the download keeps going for the other one
        #expect(cancelledDownloads.count == 0)

        // When the last one leaves
        task2.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task2.response
        }
        await drainPipeline()

        // Then the download is cancelled
        #expect(cancelledDownloads.count == 1)
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

    // MARK: - Errors

    @Test func errorPropagatedToBothCoalescedSubscribers() async {
        // GIVEN - two tasks for the same URL, data loader will fail
        let error = NSError(domain: "test", code: -1)
        dataLoader.results[Test.url] = .failure(error)

        // WHEN - both tasks are started concurrently. Data loading stays
        // suspended until both have registered with the pipeline, otherwise the
        // first one can fail before the second subscribes and there is nothing
        // left to coalesce with.
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }

        var errorCount = 0
        do { _ = try await task1.response } catch { errorCount += 1 }
        do { _ = try await task2.response } catch { errorCount += 1 }

        // THEN - both subscribers receive an error
        #expect(errorCount == 2)
        // Only one network request was made (coalesced)
        #expect(dataLoader.createdTaskCount == 1)
    }
}
