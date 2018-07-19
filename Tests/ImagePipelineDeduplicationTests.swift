// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineDeduplicationTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var observations = [NSKeyValueObservation]()

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Deduplication

    func testDeduplicationGivenSameURLDifferentSameProcessors() {
        dataLoader.queue.isSuspended = true

        // Given requests with the same URLs and same processors
        let processors = ProcessorFactory()
        let request1 = Test.request.processed(with: processors.make(id: "1"))
        let request2 = Test.request.processed(with: processors.make(id: "1"))

        // When loading images for those requests
        // Then the correct proessors are applied.
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["1"])
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            // Then the original image is loaded once, and the image is processed
            // also only once
            XCTAssertEqual(processors.numberOfProcessorsApplied, 1)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testDeduplicationGivenSameURLDifferentProcessors() {
        dataLoader.queue.isSuspended = true

        // Given requests with the same URLs but different processors
        let processors = ProcessorFactory()
        let request1 = Test.request.processed(with: processors.make(id: "1"))
        let request2 = Test.request.processed(with: processors.make(id: "2"))

        // When loading images for those requests
        // Then the correct proessors are applied.
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["2"])
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            // Then the original image is loaded once, but both processors are applied
            XCTAssertEqual(processors.numberOfProcessorsApplied, 2)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testDeduplicationGivenSameURLDifferentProcessorsOneEmpty() {
        dataLoader.queue.isSuspended = true

        // Given requests with the same URLs but different processors where one
        // processor is empty
        let processors = ProcessorFactory()
        let request1 = Test.request.processed(with: processors.make(id: "1"))
        var request2 = Test.request
        request2.processor = nil

        // When loading images for those requests
        // Then the correct proessors are applied.
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], [])
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            // Then
            // The original image is loaded once, the first processor is applied
            XCTAssertEqual(processors.numberOfProcessorsApplied, 1)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testNoDeduplicationGivenNonEquivalentRequests() {
        dataLoader.queue.isSuspended = true

        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))

        expect(pipeline).toLoadImage(with: request1)
        expect(pipeline).toLoadImage(with: request2)

        dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 2)
        }
    }

    // MARK: - Deduplication (Custom Load Keys)

    func testDeduplicationWhenUsingCustomLoadKeys() {
        dataLoader.queue.isSuspended = true

        // Given custom load keys (e.g. you'd like to trim tokens from the URL)
        var request1 = ImageRequest(url: Test.url.appendingPathComponent("token=123"))
        request1.loadKey = Test.url
        var request2 = ImageRequest(url: Test.url.appendingPathComponent("token=456"))
        request2.loadKey = Test.url

        // Then both image are loaded
        expect(pipeline).toLoadImage(with: request1)
        expect(pipeline).toLoadImage(with: request2)

        dataLoader.queue.isSuspended = false

        wait { _ in
            // Then the original image is loaded once
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testUsingLoadKeysWithLegacyBehaviour() {
        dataLoader.queue.isSuspended = true

        // When using custom load keys with legacy semantics (those keys were
        // comparing processors

        var request1 = Test.request.processed(with: MockImageProcessor(id: "1"))
        // WARNING This is legacy behaviour, don't use it
        request1.loadKey = Test.url.absoluteString + "processor=1"

        var request2 = Test.request.processed(with: MockImageProcessor(id: "2"))
        // WARNING This is legacy behaviour, don't use it
        request2.loadKey = Test.url.absoluteString + "processor=2"

        // Then both images are loaded and processors are applied
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["2"])
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            // Then original image is loaded twice - this is how it would work
            // if you were using ImagePipeline form version 7.0 with a legacy
            // `loadKey` semantics which were taking processors into account
            // when comparing load keys.
            XCTAssertEqual(self.dataLoader.createdTaskCount, 2)
        }
    }

    // MARK: - Processing

    func testProcessorsAreDeduplicated() {
        dataLoader.queue.isSuspended = true

        // Given
        // Make sure we don't start processing when some requests haven't
        // started yet.
        let processors = ProcessorFactory()
        let queueObserver = OperationQueueObserver(queue: pipeline.configuration.imageProcessingQueue)

        // When
        expect(pipeline).toLoadImage(with: Test.request.processed(with: processors.make(id: "1")))
        expect(pipeline).toLoadImage(with: Test.request.processed(with: processors.make(id: "2")))
        expect(pipeline).toLoadImage(with: Test.request.processed(with: processors.make(id: "1")))

        dataLoader.queue.isSuspended = false

        // When/Then
        wait { _ in
            XCTAssertEqual(queueObserver.operations.count, 2)
            XCTAssertEqual(processors.numberOfProcessorsApplied, 2)
        }
    }

    func testSubscribingToExisingSessionWhenProcessingAlreadyStarted() {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let processors = ProcessorFactory()
        let request1 = Test.request.processed(with: processors.make(id: "1"))
        let request2 = Test.request.processed(with: processors.make(id: "1"))

        let queueObserver = OperationQueueObserver(queue: queue)

        let expectation = self.expectation(description: "Second request completed")

        queueObserver.didAddOperation = { operation in
            queueObserver.didAddOperation = nil

            // When loading image with the same request and processing for
            // the first request has already started
            self.pipeline.loadImage(with: request2) { response, _ in
                // Then the image is still loaded and processors is applied
                XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["1"])
                XCTAssertNotNil(response)
                expectation.fulfill()
            }
            queue.isSuspended = false
        }

        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["1"])
        }

        wait { _ in
            // Then the original image is loaded only once, but processors are
            // applied twice
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
            XCTAssertEqual(processors.numberOfProcessorsApplied, 1)
            XCTAssertEqual(queueObserver.operations.count, 1)
        }
    }

    func testCorrectImageIsStoredInMemoryCache() {
        let imageCache = MockImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }

        // Given requests with the same URLs but different processors
        let processors = ProcessorFactory()
        let request1 = Test.request.processed(with: processors.make(id: "1"))
        let request2 = Test.request.processed(with: processors.make(id: "2"))

        // When loading images for those requests
        // Then the correct proessors are applied.
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["2"])
        }
        wait()

        // Then
        XCTAssertNotNil(imageCache[request1])
        XCTAssertEqual(imageCache[request1
            ]?.nk_test_processorIDs ?? [], ["1"])
        XCTAssertNotNil(imageCache[request2])
        XCTAssertEqual(imageCache[request2]?.nk_test_processorIDs ?? [], ["2"])
    }

    // MARK: - Cancellation

    func testCancellation() {
        dataLoader.queue.isSuspended = true

        // Given two equivalent requests

        // When both tasks are cancelled the image loading session is cancelled

        _ = expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        let task1 = pipeline.loadImage(with: Test.request)
        let task2 = pipeline.loadImage(with: Test.request)
        wait() // wait until the tasks is started or we might be cancelling non-exisitng task

        _ = expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        task1.cancel()
        task2.cancel()
        wait()
    }

    func testCancellatioOnlyCancelOneTask() {
        dataLoader.queue.isSuspended = true

        let task1 = pipeline.loadImage(with: Test.request) { _, _ in
            XCTFail()
        }

        expect(pipeline).toLoadImage(with: Test.request)

        // When cancelling only only only one of the tasks
        task1.cancel()

        // Then the image is still loaded

        dataLoader.queue.isSuspended = false

        wait()
    }

    func testProcessingOperationsAreCancelledSeparately() {
        dataLoader.queue.isSuspended = true

        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        // When/Then
        let operations = expect(queue).toEnqueueOperationsWithCount(2)

        let processors = ProcessorFactory()
        let request1 = Test.request.processed(with: processors.make(id: "1"))
        let request2 = Test.request.processed(with: processors.make(id: "2"))

        let _ = pipeline.loadImage(with: request1)
        let task2 = pipeline.loadImage(with: request2)

        dataLoader.queue.isSuspended = false

        wait()

        // When/Then
        let expectation = self.expectation(description: "One operation got cancelled")
        for operation in operations.operations {
            // Pass the same expectation into both operations, only
            // one should get cancelled.
            expect(operation).toCancel(with: expectation)
        }

        task2.cancel()
        wait()
    }

    // MARK: - Priority

    func testProcessingOperationPriorityUpdated() {
        // Given
        dataLoader.queue.isSuspended = true
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        // Given
        let operations = expect(queue).toEnqueueOperationsWithCount(1)

        pipeline.loadImage(with: Test.request.with(processorId: "1").with(priority: .low))

        dataLoader.queue.isSuspended = false
        wait { _ in
            XCTAssertEqual(operations.operations.first!.queuePriority, .low)
        }

        // When/Then
        expect(operations.operations.first!).toUpdatePriority(from: .low, to: .high)
        let task = pipeline.loadImage(with: Test.request.with(processorId: "1").with(priority: .high))
        wait()

        // When/Then
        expect(operations.operations.first!).toUpdatePriority(from: .high, to: .low)
        task.setPriority(.low)
        wait()
    }

    func testProcessingOperationPriorityUpdatedWhenCancellingTask() {
        // Given
        dataLoader.queue.isSuspended = true
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        // Given
        let operations = expect(queue).toEnqueueOperationsWithCount(1)
        pipeline.loadImage(with: Test.request.with(processorId: "1").with(priority: .low))
        dataLoader.queue.isSuspended = false
        wait()

        // Given
        // Note: adding a second task separately because we should guarantee
        // that both are subscribed by the time we start our test.
        expect(operations.operations.first!).toUpdatePriority(from: .low, to: .high)
        let task = pipeline.loadImage(with: Test.request.with(processorId: "1").with(priority: .high))
        wait()

        // When/Then
        expect(operations.operations.first!).toUpdatePriority(from: .high, to: .low)
        task.cancel()
        wait()
    }

    // MARK: - Misc

    func testProgressIsReported() {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )
        dataLoader.queue.isSuspended = true

        // When/Then
        for _ in 0..<3 {
            let request = Test.request

            let expectedCompleted = self.expect(values: [10, 20] as [Int64])
            let expectedTotal = self.expect(values: [20, 20] as [Int64])

            pipeline.loadImage(
                with: request,
                progress: { _, completed, total in
                    XCTAssertTrue(Thread.isMainThread)
                    expectedCompleted.received(completed)
                    expectedTotal.received(total)
                }
            )
        }
        dataLoader.queue.isSuspended = false

        wait()
    }

    func testDisablingDeduplication() {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isDeduplicationEnabled = false
        }

        dataLoader.queue.isSuspended = true

        // When/Then
        let request1 = Test.request
        let request2 = Test.request
        XCTAssertEqual(request1.loadKey, request2.loadKey)

        expect(pipeline).toLoadImage(with: request1)
        expect(pipeline).toLoadImage(with: request2)

        dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 2)
        }
    }
}

/// Helps with counting processors.
private class ProcessorFactory {
    var numberOfProcessorsApplied: Int = 0

    class Processor: MockImageProcessor {
        var factory: ProcessorFactory!

        override func process(image: Image, context: ImageProcessingContext) -> Image? {
            factory.numberOfProcessorsApplied += 1
            return super.process(image: image, context: context)
        }
    }

    func make(id: String) -> MockImageProcessor {
        let processor = Processor(id: id)
        processor.factory = self
        return processor
    }
}
