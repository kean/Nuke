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

    // MARK: - Deduplication

    // TODO: it only works because `WorkQueue` introduces a hop
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
        #expect(image1.nk_test_processorIDs ?? [] == ["1"])
        #expect(image2.nk_test_processorIDs ?? [] == ["1"])

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
        #expect(image1.nk_test_processorIDs ?? [] == ["1"])
        #expect(image2.nk_test_processorIDs ?? [] == ["2"])

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
        #expect(image1.nk_test_processorIDs ?? [] == ["1"])
        #expect(image2.nk_test_processorIDs ?? [] == [])

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
        let expectation = pipeline.configuration.imageProcessingQueue.expectItemAdded(count: 2)

        async let task1 = pipeline.image(for: ImageRequest(url: Test.url, processors: [processors.make(id: "1")]))
        async let task2 = pipeline.image(for: ImageRequest(url: Test.url, processors: [processors.make(id: "2")]))
        async let task3 = pipeline.image(for: ImageRequest(url: Test.url, processors: [processors.make(id: "1")]))

        _ = try await [task1, task2, task3]

        // Then
        _ = await expectation.wait()
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
        let expectation = queue.expectItemAdded()
        let task = Task {
            try await pipeline.image(for: request1)
        }
        _ = await expectation.wait()
        queue.isSuspended = false

        let image2 = try await pipeline.image(for: request2)
        let image1 = try await task.value

        // Then the images is still loaded and processors is applied
        #expect(image1.nk_test_processorIDs ?? [] == ["1"])
        #expect(image2.nk_test_processorIDs ?? [] == ["1"])

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
        #expect(image1.nk_test_processorIDs ?? [] == ["1"])
        #expect(image2.nk_test_processorIDs ?? [] == ["2"])

        // Then the images are stored in memory cache
        #expect(imageCache[request1] != nil)
        #expect(imageCache[request1]?.image.nk_test_processorIDs ?? [] == ["1"])
        #expect(imageCache[request2] != nil)
        #expect(imageCache[request2]?.image.nk_test_processorIDs ?? [] == ["2"])
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

    @Test func processingWorkItemsAreCancelledSeparately() async {
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        // Given two requests with different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])

        // When
        let expectation1 = queue.expectItemAdded()
        pipeline.imageTask(with: request1).resume()
        _ = await expectation1.wait()

        let expectation2 = queue.expectItemAdded()
        let task2 = pipeline.imageTask(with: request2).resume()
        let item2 = await expectation2.wait()

        // When
        let expectation3 = queue.expectItemCancelled(item2)
        task2.cancel()
        await expectation3.wait()
    }

//    // MARK: - Priority
//
//    @Test func processingOperationPriorityUpdated() {
//        // Given
//        dataLoader.queue.isSuspended = true
//        let queue = pipeline.configuration.imageProcessingQueue
//        queue.isSuspended = true
//
//        // Given
//        let operations = expect(queue).toEnqueueOperationsWithCount(1)
//
//        pipeline.loadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], priority: .low)) { _ in }
//
//        dataLoader.queue.isSuspended = false
//        wait { _ in
//            #expect(operations.operations.first!.queuePriority == .low)
//        }
//
//        // When/Then
//        expect(operations.operations.first!).toUpdatePriority(from: .low, to: .high)
//        let task = pipeline.loadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], priority: .high)) { _ in }
//        wait()
//
//        // When/Then
//        expect(operations.operations.first!).toUpdatePriority(from: .high, to: .low)
//        task.priority = .low
//        wait()
//    }
//
//    @Test func processingOperationPriorityUpdatedWhenCancellingTask() {
//        // Given
//        dataLoader.queue.isSuspended = true
//        let queue = pipeline.configuration.imageProcessingQueue
//        queue.isSuspended = true
//
//        // Given
//        let operations = expect(queue).toEnqueueOperationsWithCount(1)
//        pipeline.loadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], priority: .low)) { _ in }
//        dataLoader.queue.isSuspended = false
//        wait()
//
//        // Given
//        // Note: adding a second task separately because we should guarantee
//        // that both are subscribed by the time we start our test.
//        expect(operations.operations.first!).toUpdatePriority(from: .low, to: .high)
//        let task = pipeline.loadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], priority: .high)) { _ in }
//        wait()
//
//        // When/Then
//        expect(operations.operations.first!).toUpdatePriority(from: .high, to: .low)
//        task.cancel()
//        wait()
//    }
//
//    // MARK: - Loading Data
//
//    @Test func thatLoadsDataOnceWhenLoadingDataAndLoadingImage() {
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: Test.request)
//            expect(pipeline).toLoadData(with: Test.request)
//        }
//        wait()
//
//        #expect(dataLoader.createdTaskCount == 1)
//    }
//
//    // MARK: - Misc
//
//    @Test func progressIsReported() {
//        // Given
//        dataLoader.results[Test.url] = .success(
//            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
//        )
//
//        // When/Then
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 3) {
//            for _ in 0..<3 {
//                let request = Test.request
//
//                let expectedProgress = expectProgress([(10, 20), (20, 20)])
//
//                pipeline.loadImage(
//                    with: request,
//                    progress: { _, completed, total in
//                        #expect(Thread.isMainThread)
//                        expectedProgress.received((completed, total))
//                    },
//                    completion: { _ in }
//                )
//            }
//        }
//
//        wait()
//    }
//
//    @Test func disablingDeduplication() {
//        // Given
//        let pipeline = ImagePipeline {
//            $0.imageCache = nil
//            $0.dataLoader = dataLoader
//            $0.isTaskCoalescingEnabled = false
//        }
//
//        // When/Then
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: Test.request)
//            expect(pipeline).toLoadImage(with: Test.request)
//        }
//        wait { _ in
//            #expect(self.dataLoader.createdTaskCount == 2)
//        }
//    }
}
