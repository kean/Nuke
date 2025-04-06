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
    @Test func deduplicationGivenSameURLDifferentSameProcessors() async throws {
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

        // Then  the image is processed once
        #expect(processors.numberOfProcessorsApplied == 1)

        // Then the original image is loaded once
        #expect(dataLoader.createdTaskCount == 1)
    }

//    @Test func deduplicationGivenSameURLDifferentProcessors() {
//        // Given requests with the same URLs but different processors
//        let processors = MockProcessorFactory()
//        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])
//
//        // When loading images for those requests
//        // Then the correct proessors are applied.
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: request1) { result in
//                let image = result.value?.image
//                #expect(image?.nk_test_processorIDs ?? [] == ["1"])
//            }
//            expect(pipeline).toLoadImage(with: request2) { result in
//                let image = result.value?.image
//                #expect(image?.nk_test_processorIDs ?? [] == ["2"])
//            }
//        }
//
//        wait { _ in
//            // Then the original image is loaded once, but both processors are applied
//            #expect(processors.numberOfProcessorsApplied == 2)
//            #expect(self.dataLoader.createdTaskCount == 1)
//        }
//    }
//
//    @Test func deduplicationGivenSameURLDifferentProcessorsOneEmpty() {
//        // Given requests with the same URLs but different processors where one
//        // processor is empty
//        let processors = MockProcessorFactory()
//        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//
//        var request2 = Test.request
//        request2.processors = []
//
//        // When loading images for those requests
//        // Then the correct proessors are applied.
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: request1) { result in
//                let image = result.value?.image
//                #expect(image?.nk_test_processorIDs ?? [] == ["1"])
//            }
//            expect(pipeline).toLoadImage(with: request2) { result in
//                let image = result.value?.image
//                #expect(image?.nk_test_processorIDs ?? [] == [])
//            }
//        }
//
//        wait { _ in
//            // Then
//            // The original image is loaded once, the first processor is applied
//            #expect(processors.numberOfProcessorsApplied == 1)
//            #expect(self.dataLoader.createdTaskCount == 1)
//        }
//    }
//
//    @Test func noDeduplicationGivenNonEquivalentRequests() {
//
//        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
//        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))
//
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: request1)
//            expect(pipeline).toLoadImage(with: request2)
//        }
//
//        wait { _ in
//            #expect(self.dataLoader.createdTaskCount == 2)
//        }
//    }
//
//    // MARK: - Scale
//
//#if !os(macOS)
//    @Test func overridingImageScale() throws {
//        // GIVEN requests with the same URLs but one accesses thumbnail
//        let request1 = ImageRequest(url: Test.url, userInfo: [.scaleKey: 2])
//        let request2 = ImageRequest(url: Test.url, userInfo: [.scaleKey: 3])
//
//        // WHEN loading images for those requests
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: request1) { result in
//                // THEN
//                guard let image = result.value?.image else { return Issue.record() }
//                #expect(image.scale == 2)
//            }
//            expect(pipeline).toLoadImage(with: request2) { result in
//                // THEN
//                guard let image = result.value?.image else { return Issue.record() }
//                #expect(image.scale == 3)
//            }
//        }
//
//        wait()
//
//        #expect(self.dataLoader.createdTaskCount == 1)
//    }
//#endif
//
//    // MARK: - Thumbnail
//
//    @Test func deduplicationGivenSameURLButDifferentThumbnailOptions() {
//        // GIVEN requests with the same URLs but one accesses thumbnail
//        let request1 = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: ImageRequest.ThumbnailOptions(maxPixelSize: 400)])
//        let request2 = ImageRequest(url: Test.url)
//
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//
//            // WHEN loading images for those requests
//            expect(pipeline).toLoadImage(with: request1) { result in
//                // THEN
//                guard let image = result.value?.image else { return Issue.record() }
//                #expect(image.sizeInPixels == CGSize(width: 400, height: 300))
//            }
//            expect(pipeline).toLoadImage(with: request2) { result in
//                // THEN
//                guard let image = result.value?.image else { return Issue.record() }
//                #expect(image.sizeInPixels == CGSize(width: 640.0, height: 480.0))
//            }
//
//        }
//
//        wait { _ in
//            // THEN the image data is fetched once
//            #expect(self.dataLoader.createdTaskCount == 1)
//        }
//    }
//
//    @Test func deduplicationGivenSameURLButDifferentThumbnailOptionsReversed() {
//        // GIVEN requests with the same URLs but one accesses thumbnail
//        // (in this test, order is reversed)
//        let request1 = ImageRequest(url: Test.url)
//        let request2 = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: ImageRequest.ThumbnailOptions(maxPixelSize: 400)])
//
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            // WHEN loading images for those requests
//            expect(pipeline).toLoadImage(with: request1) { result in
//                // THEN
//                guard let image = result.value?.image else { return Issue.record() }
//                #expect(image.sizeInPixels == CGSize(width: 640.0, height: 480.0))
//            }
//            expect(pipeline).toLoadImage(with: request2) { result in
//                // THEN
//                guard let image = result.value?.image else { return Issue.record() }
//                #expect(image.sizeInPixels == CGSize(width: 400, height: 300))
//            }
//        }
//
//        wait { _ in
//            // THEN the image data is fetched once
//            #expect(self.dataLoader.createdTaskCount == 1)
//        }
//    }
//
//    // MARK: - Processing
//
//    @Test func processorsAreDeduplicated() {
//        // Given
//        // Make sure we don't start processing when some requests haven't
//        // started yet.
//        let processors = MockProcessorFactory()
//        let queueObserver = OperationQueueObserver(queue: pipeline.configuration.imageProcessingQueue)
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 3) {
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [processors.make(id: "1")]))
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [processors.make(id: "2")]))
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [processors.make(id: "1")]))
//        }
//
//        // When/Then
//        wait { _ in
//            #expect(queueObserver.operations.count == 2)
//            #expect(processors.numberOfProcessorsApplied == 2)
//        }
//    }
//
//    @Test func subscribingToExisingSessionWhenProcessingAlreadyStarted() {
//        // Given
//        let queue = pipeline.configuration.imageProcessingQueue
//        queue.isSuspended = true
//
//        let processors = MockProcessorFactory()
//        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//
//        let queueObserver = OperationQueueObserver(queue: queue)
//
//        let expectation = self.expectation(description: "Second request completed")
//
//        queueObserver.didAddOperation = { _ in
//            queueObserver.didAddOperation = nil
//
//            // When loading image with the same request and processing for
//            // the first request has already started
//            self.pipeline.loadImage(with: request2) { result in
//                let image = result.value?.image
//                // Then the image is still loaded and processors is applied
//                #expect(image?.nk_test_processorIDs ?? [] == ["1"])
//                expectation.fulfill()
//            }
//            queue.isSuspended = false
//        }
//
//        expect(pipeline).toLoadImage(with: request1) { result in
//            let image = result.value?.image
//            #expect(image?.nk_test_processorIDs ?? [] == ["1"])
//        }
//
//        wait { _ in
//            // Then the original image is loaded only once, but processors are
//            // applied twice
//            #expect(self.dataLoader.createdTaskCount == 1)
//            #expect(processors.numberOfProcessorsApplied == 1)
//            #expect(queueObserver.operations.count == 1)
//        }
//    }
//
//    @Test func correctImageIsStoredInMemoryCache() {
//        let imageCache = MockImageCache()
//        let pipeline = ImagePipeline {
//            $0.dataLoader = dataLoader
//            $0.imageCache = imageCache
//        }
//
//        // Given requests with the same URLs but different processors
//        let processors = MockProcessorFactory()
//        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])
//
//        // When loading images for those requests
//        // Then the correct proessors are applied.
//        expect(pipeline).toLoadImage(with: request1) { result in
//            let image = result.value?.image
//            #expect(image?.nk_test_processorIDs ?? [] == ["1"])
//        }
//        expect(pipeline).toLoadImage(with: request2) { result in
//            let image = result.value?.image
//            #expect(image?.nk_test_processorIDs ?? [] == ["2"])
//        }
//        wait()
//
//        // Then
//        #expect(imageCache[request1] != nil)
//        #expect(imageCache[request1]?.image.nk_test_processorIDs ?? [] == ["1"])
//        #expect(imageCache[request2] != nil)
//        #expect(imageCache[request2]?.image.nk_test_processorIDs ?? [] == ["2"])
//    }
//
//    // MARK: - Cancellation
//
//    @Test func cancellation() {
//        dataLoader.queue.isSuspended = true
//
//        // Given two equivalent requests
//
//        // When both tasks are cancelled the image loading session is cancelled
//
//        _ = expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
//        let task1 = pipeline.loadImage(with: Test.request) { _ in }
//        let task2 = pipeline.loadImage(with: Test.request) { _ in }
//        wait() // wait until the tasks is started or we might be cancelling non-existing task
//
//        _ = expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
//        task1.cancel()
//        task2.cancel()
//        wait()
//    }
//
//    @Test func cancellatioOnlyCancelOneTask() {
//        dataLoader.queue.isSuspended = true
//
//        let task1 = pipeline.loadImage(with: Test.request) { _ in
//            Issue.record()
//        }
//
//        expect(pipeline).toLoadImage(with: Test.request)
//
//        // When cancelling only only only one of the tasks
//        task1.cancel()
//
//        // Then the image is still loaded
//
//        dataLoader.queue.isSuspended = false
//
//        wait()
//    }
//
//    @Test func processingOperationsAreCancelledSeparately() {
//        dataLoader.queue.isSuspended = true
//
//        // Given
//        let queue = pipeline.configuration.imageProcessingQueue
//        queue.isSuspended = true
//
//        // When/Then
//        let operations = expect(queue).toEnqueueOperationsWithCount(2)
//
//        let processors = MockProcessorFactory()
//        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])
//
//        _ = pipeline.loadImage(with: request1) { _ in }
//        let task2 = pipeline.loadImage(with: request2) { _ in }
//
//        dataLoader.queue.isSuspended = false
//
//        wait()
//
//        // When/Then
//        let expectation = self.expectation(description: "One operation got cancelled")
//        for operation in operations.operations {
//            // Pass the same expectation into both operations, only
//            // one should get cancelled.
//            expect(operation).toCancel(with: expectation)
//        }
//
//        task2.cancel()
//        wait()
//    }
//
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
