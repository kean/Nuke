// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImagePipelineCoalescingTests {
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
        let response1 = try await pipeline.imageTask(with: request1).response
        #expect(response1.image.nk_test_processorIDs == ["1"])

        let response2 = try await pipeline.imageTask(with: request2).response
        #expect(response2.image.nk_test_processorIDs == ["2"])

        // Then
        #expect(imageCache[request1] != nil)
        #expect(imageCache[request1]?.image.nk_test_processorIDs == ["1"])
        #expect(imageCache[request2] != nil)
        #expect(imageCache[request2]?.image.nk_test_processorIDs == ["2"])
    }

    // MARK: - Cancellation

    @Test func cancellation() async {
        dataLoader.queue.isSuspended = true

        // Given two equivalent requests
        let startExpectation = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task1 = pipeline.imageTask(with: Test.request)
        let task2 = pipeline.imageTask(with: Test.request)
        Task.detached { try? await task1.response }
        Task.detached { try? await task2.response }
        await startExpectation.wait()

        // When both tasks are cancelled the image loading session is cancelled
        await notification(MockDataLoader.DidCancelTask, object: dataLoader) {
            task1.cancel()
            task2.cancel()
        }
    }

    @Test func cancellationOnlyCancelOneTask() async throws {
        dataLoader.queue.isSuspended = true

        let task1 = pipeline.imageTask(with: Test.request)
        let task2 = pipeline.imageTask(with: Test.request)

        // Start both tasks
        Task.detached { try? await task1.response }

        // When cancelling only one of the tasks
        task1.cancel()

        // Then the image is still loaded via the second task
        dataLoader.queue.isSuspended = false
        _ = try await task2.response
    }

    // MARK: - Loading Data

    @Test func loadsDataOnceWhenLoadingDataAndLoadingImage() async throws {
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }
        _ = try await task1.response
        _ = try await task2.response

        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Misc

    @Test func progressIsReported() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When/Then
        let task = pipeline.imageTask(with: Test.url)
        var progressValues: [ImageTask.Progress] = []
        for await progress in task.progress {
            progressValues.append(progress)
        }
        _ = try? await task.response

        #expect(progressValues == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
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
}

@Suite struct ImagePipelineProcessingDeduplicationTests {
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

    @Test func intermediateMemoryCachedResultsAreUsed() async throws {
        let cache = MockImageCache()
        var conf = pipeline.configuration
        conf.imageCache = cache
        let pipeline = ImagePipeline(configuration: conf)

        let factory = MockProcessorFactory()

        // Given
        cache[ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2")])] = Test.container

        // When
        let request = ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2"), factory.make(id: "3")])
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["3"])
        #expect(dataLoader.createdTaskCount == 0)
        #expect(factory.numberOfProcessorsApplied == 1)
    }

    @Test func intermediateDataCacheResultsAreUsed() async throws {
        // Given
        let dataCache = MockDataCache()
        dataCache.store[Test.url.absoluteString + "12"] = Test.data

        let pipeline = pipeline.reconfigured {
            $0.dataCache = dataCache
        }

        // When
        let factory = MockProcessorFactory()
        let request = ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2"), factory.make(id: "3")])
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["3"])
        #expect(dataLoader.createdTaskCount == 0)
        #expect(factory.numberOfProcessorsApplied == 1)
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

    // MARK: - Priority Escalation

    @Test @ImagePipelineActor func lowPriorityRequestEscalatesWhenHigherPriorityJoins() async throws {
        // GIVEN - a low-priority request already in flight
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        var lowRequest = Test.request
        lowRequest.priority = .low

        let lowOperations = await queue.waitForOperations(count: 1) {
            _ = pipeline.imageTask(with: lowRequest)
        }
        let operation = try #require(lowOperations.first)
        #expect(operation.priority == .low)

        // WHEN - a normal-priority request for the same URL joins the session
        var highRequest = Test.request
        highRequest.priority = .normal

        // Priority should be escalated to the highest subscriber
        await queue.waitForPriorityChange(of: operation, to: .normal) {
            _ = pipeline.imageTask(with: highRequest)
        }

        // THEN
        #expect(operation.priority == .normal)

        // Cleanup
        queue.isSuspended = false
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
}
