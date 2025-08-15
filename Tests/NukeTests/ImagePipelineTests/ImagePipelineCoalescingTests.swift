// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@ImagePipelineActor
@Suite struct ImagePipelineCoalescingTests {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var observations = [NSKeyValueObservation]()

    init() {
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Coalescing

    @Test func coalescingGivenSameURLDifferentSameProcessors() async throws {
        // Given requests with the same URLs and same processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])

        // When loading images for those requests
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then the correct proessors are applied.
        #expect(image1.nk_test_processorIDs == ["1"])
        #expect(image2.nk_test_processorIDs == ["1"])

        // Then the original image is loaded once
        #expect(dataLoader.createdTaskCount == 1)

        // Then  the image is processed once
        #expect(processors.numberOfProcessorsApplied == 1)
    }

    @Test func coalescingGivenSameURLDifferentProcessors() async throws {
        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])

        // When loading images for those requests
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then the correct proessors are applied.
        // Then the correct proessors are applied.
        #expect(image1.nk_test_processorIDs == ["1"])
        #expect(image2.nk_test_processorIDs == ["2"])

        // Then the original image is loaded once
        #expect(dataLoader.createdTaskCount == 1)

        // Then the image is processed twice
        #expect(processors.numberOfProcessorsApplied == 2)
    }

    @Test func coalescingGivenSameURLDifferentProcessorsOneEmpty() async throws {
        // Given requests with the same URLs but different processors where one
        // processor is empty
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])

        var request2 = Test.request
        request2.processors = []

        // When loading images for those requests
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then the correct proessors are applied.
        #expect(image1.nk_test_processorIDs == ["1"])
        #expect(image2.nk_test_processorIDs == [])

        // Then the original image is loaded once
        #expect(dataLoader.createdTaskCount == 1)

        // Then the image is processed once
        #expect(processors.numberOfProcessorsApplied == 1)
    }

    @Test func noCoalescingGivenNonEquivalentRequests() async throws {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))

        // When loading images for those requests
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        _ = try await (task1, task2)

        // Then no coalescing happens
        #expect(dataLoader.createdTaskCount == 2)
    }

    // MARK: - Caching

    @Test func memoryCacheLookupPerformedBeforeCoalescing() async throws {
        // Given
        let cache = MockImageCache()
        let pipeline = pipeline.reconfigured {
            $0.imageCache = cache
        }

        dataLoader.isSuspended = true

        // When one request is pending
        let exepctation = pipeline.configuration.dataLoadingQueue.expectJobAdded()
        pipeline.imageTask(with: Test.request).resume()
        await exepctation.wait()

        // When image is added to memory cache
        cache[Test.request] = Test.container

        // Then when second request is started the image is returned immediatelly
        _ = try await pipeline.image(for: Test.request)
    }

    // MARK: - Scale

#if !os(macOS)
    @Test func overridingImageScale() async throws {
        // Given requests with the same URLs but one accesses thumbnail
        let request1 = ImageRequest(url: Test.url, userInfo: [.scaleKey: 2])
        let request2 = ImageRequest(url: Test.url, userInfo: [.scaleKey: 3])

        // When loading images for those requests
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then correct scale values are applied (despite coalescing)
        #expect(image1.scale == 2)
        #expect(image2.scale == 3)

        // Then images is loaded once
        #expect(dataLoader.createdTaskCount == 1)
    }
#endif

    // MARK: - Thumbnail

    @Test func coalescingGivenSameURLButDifferentThumbnailOptions() async throws {
        // Given requests with the same URLs but one accesses thumbnail
        let request1 = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: ImageRequest.ThumbnailOptions(maxPixelSize: 400)])
        let request2 = ImageRequest(url: Test.url)

        // When loading images for those requests
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then the correct thumbnails are generated (despite coalescing)
        #expect(image1.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(image2.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func coelascingGivenSameURLButDifferentThumbnailOptionsReversed() async throws {
        // Given requests with the same URLs but one accesses thumbnail
        // (in this test, order is reversed)
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: ImageRequest.ThumbnailOptions(maxPixelSize: 400)])

        // When loading images for those requests
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then the correct thumbnails are generated (despite coalescing)
        #expect(image1.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(image2.sizeInPixels == CGSize(width: 400, height: 300))

        // Then the image data is fetched once
        #expect(self.dataLoader.createdTaskCount == 1)
    }

    // MARK: - Processing

    @Test func processorsAreDeduplicated() async throws {
        // Given
        let processors = MockProcessorFactory()

        // When
        let expectation = pipeline.configuration.imageProcessingQueue.expectJobsAdded(count: 2)

        async let task1 = pipeline.image(for: ImageRequest(url: Test.url, processors: [processors.make(id: "1")]))
        async let task2 = pipeline.image(for: ImageRequest(url: Test.url, processors: [processors.make(id: "2")]))
        async let task3 = pipeline.image(for: ImageRequest(url: Test.url, processors: [processors.make(id: "1")]))

        _ = try await [task1, task2, task3]

        // Then
        await expectation.wait()
        #expect(processors.numberOfProcessorsApplied == 2)
    }

    @Test func subscribingToExisingTaskWhenProcessingAlreadyStarted() async throws {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])

        // When first task is stated and processing operation is registered
        let expectation = queue.expectJobAdded()
        let task = Task {
            try await pipeline.image(for: request1)
        }
        await expectation.wait()
        queue.isSuspended = false

        let image2 = try await pipeline.image(for: request2)
        let image1 = try await task.value

        // Then the images is still loaded and processors is applied
        #expect(image1.nk_test_processorIDs == ["1"])
        #expect(image2.nk_test_processorIDs == ["1"])

        // Then the original image is loaded only once, but processors are
        // applied twice
        #expect(dataLoader.createdTaskCount == 1)
        #expect(processors.numberOfProcessorsApplied == 1)
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
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then the correct processors are applied.
        #expect(image1.nk_test_processorIDs == ["1"])
        #expect(image2.nk_test_processorIDs == ["2"])

        // Then the images are stored in memory cache
        #expect(imageCache[request1] != nil)
        #expect(imageCache[request1]?.image.nk_test_processorIDs == ["1"])
        #expect(imageCache[request2] != nil)
        #expect(imageCache[request2]?.image.nk_test_processorIDs == ["2"])
    }

    // MARK: - Cancellation

    @Test func cancellation() async {
        dataLoader.queue.isSuspended = true

        // Given two equivalent requests
        // When both tasks are cancelled
        let expectation1 = AsyncExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task1 = pipeline.imageTask(with: Test.request).resume()
        let task2 = pipeline.imageTask(with: Test.request).resume()
        _ = await expectation1.wait() // wait until the tasks is started or we might be cancelling non-existing task

        // Then the image task is cancelled
        let expectation2 = AsyncExpectation(notification: MockDataLoader.DidCancelTask, object: dataLoader)
        task1.cancel()
        task2.cancel()
        _ = await expectation2.wait()
    }

    @Test func cancellationCancelOnlyOneTask() async throws {
        dataLoader.queue.isSuspended = true

        let task1 = pipeline.loadImage(with: Test.request) { _ in
            Issue.record()
        }

        let task2 = pipeline.imageTask(with: Test.request).resume()

        // When cancelling only only only one of the tasks
        task1.cancel()

        // Then the image for task2 is still loaded
        dataLoader.queue.isSuspended = false

        _ = try await task2.image
    }

    @Test func processingOperationsAreCancelledSeparately() async {
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        // Given two requests with different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])

        // When
        let expectation1 = queue.expectJobAdded()
        pipeline.imageTask(with: request1).resume()
        _ = await expectation1.wait()

        let expectation2 = queue.expectJobAdded()
        let task2 = pipeline.imageTask(with: request2).resume()
        let item2 = await expectation2.wait()

        // When
        let expectation3 = queue.expectJobCancelled(item2)
        task2.cancel()
        await expectation3.wait()
    }

    // MARK: - Priority

    @Test func processingOperationPriorityUpdated() async {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        // When
        let expectation1 = queue.expectJobAdded()
        var request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], priority: .low)
        pipeline.imageTask(with: request).resume()

        // Then the item is created with a low priority
        let job = await expectation1.wait()
        #expect(job.priority == .low)

        // When new operation is added with a higher priority
        let expectation2 = queue.expectPriorityUpdated(for: job)
        request.priority = .high
        let task = pipeline.imageTask(with: request).resume()
        let newPriority1 = await expectation2.wait()

        // Then priority is raised
        #expect(newPriority1 == .high)

        // When
        let expectation3 = queue.expectPriorityUpdated(for: job)
        task.priority = .low

        // Then priority is lowered again
        let newPriority2 = await expectation3.wait()
        #expect(newPriority2 == .low)
    }

    @Test func processingOperationPriorityUpdatedWhenCancellingTask() async {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        // When
        let expectation1 = queue.expectJobAdded()
        var request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], priority: .low)
        pipeline.imageTask(with: request).resume()

        // Then the item is created with a low priority
        let job = await expectation1.wait()
        #expect(job.priority == .low)

        // When new operation is added with a higher priority
        let expectation2 = queue.expectPriorityUpdated(for: job)
        request.priority = .high
        let task = pipeline.imageTask(with: request).resume()
        let newPriority1 = await expectation2.wait()

        // Then priority is raised
        #expect(newPriority1 == .high)

        // When high-priority task is cancelled
        let expectation3 = queue.expectPriorityUpdated(for: job)
        task.cancel()

        // Then priority is lowered again
        let newPriority2 = await expectation3.wait()
        #expect(newPriority2 == .low)
    }

    // MARK: - Loading Data

    @Test func thatLoadsDataOnceWhenLoadingDataAndLoadingImage() async throws {
        // When
        async let image = pipeline.image(for: Test.request)
        async let data = pipeline.data(for: Test.request)
        _ = try await (image, data)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Misc

    @Test func progressIsReported() async {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                let request = Test.request
                group.addTask {
                    let task = pipeline.imageTask(with: request)
                    // Then
                    var expected: [ImageTask.Progress] = [.init(completed: 10, total: 20), .init(completed: 20, total: 20)].reversed()
                    for await progress in task.progress {
                        if let value = expected.popLast() {
                            #expect(value == progress)
                        } else {
                            Issue.record()
                        }
                    }
                }
            }
        }
    }

    @Test func disablingDeduplication() async throws {
        // Given
        let pipeline = ImagePipeline {
            $0.imageCache = nil
            $0.dataLoader = dataLoader
            $0.isTaskCoalescingEnabled = false
        }

        // When loading images for those requests
        async let task1 = pipeline.image(for: Test.url)
        async let task2 = pipeline.image(for: Test.url)
        _ = try await (task1, task2)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }
}
