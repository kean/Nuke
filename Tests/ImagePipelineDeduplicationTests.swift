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

        // GIVEN requests with the same URLs and same processors
        let processors = ProcessorFactory()
        let request1 = ImageRequest(url: Test.url).processed(with: processors.make(id: "1"))
        let request2 = ImageRequest(url: Test.url).processed(with: processors.make(id: "1"))

        // WHEN loading images for those requests
        // THEN the correct proessors are applied.
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, ["1"])
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            // THEN the original image is loaded once, and the image is processed
            // also only once
            XCTAssertEqual(processors.numberOfProcessorsApplied, 1)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testDeduplicationGivenSameURLDifferentProcessors() {
        dataLoader.queue.isSuspended = true

        // GIVEN requests with the same URLs but different processors
        let processors = ProcessorFactory()
        let request1 = ImageRequest(url: Test.url).processed(with: processors.make(id: "1"))
        let request2 = ImageRequest(url: Test.url).processed(with: processors.make(id: "2"))

        // WHEN loading images for those requests
        // THEN the correct proessors are applied.
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, ["2"])
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            // THEN the original image is loaded once, but both processors are applied
            XCTAssertEqual(processors.numberOfProcessorsApplied, 2)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testDeduplicationGivenSameURLDifferentProcessorsOneEmpty() {
        dataLoader.queue.isSuspended = true

        // GIVEN requests with the same URLs but different processors where one
        // processor is empty
        let processors = ProcessorFactory()
        let request1 = ImageRequest(url: Test.url).processed(with: processors.make(id: "1"))
        var request2 = ImageRequest(url: Test.url)
        request2.processor = nil

        // WHEN loading images for those requests
        // THEN the correct proessors are applied.
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, [])
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            // THEN the original image is loaded once, the first processor is applied
            XCTAssertEqual(processors.numberOfProcessorsApplied, 1)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testNoDeduplicationGivenNonEquivalentRequests() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))

        expect(pipeline).toLoadImage(with: request1)
        expect(pipeline).toLoadImage(with: request2)

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 2)
        }
    }

    // MARK: - Deduplication (Custom Load Keys)

    func testDduplicationWhenUsingCustomLoadKeys() {
        dataLoader.queue.isSuspended = true

        // GIVEN custom load keys (e.g. you'd like to trim tokens from the URL)
        var request1 = ImageRequest(url: Test.url.appendingPathComponent("token=123"))
        request1.loadKey = Test.url
        var request2 = ImageRequest(url: Test.url.appendingPathComponent("token=456"))
        request2.loadKey = Test.url

        // THEN both image are loaded
        expect(pipeline).toLoadImage(with: request1)
        expect(pipeline).toLoadImage(with: request2)

        dataLoader.queue.isSuspended = false

        wait { _ in
            // THEN the original image is loaded once
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testUsingLoadKeysWithLegacyBehaviour() {
        dataLoader.queue.isSuspended = true

        // WHEN using custom load keys with legacy semantics (those keys were
        // comparing processors

        var request1 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "1"))
        // WARNING This is legacy behaviour, don't use it
        request1.loadKey = Test.url.absoluteString + "processor=1"

        var request2 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "2"))
        // WARNING This is legacy behaviour, don't use it
        request2.loadKey = Test.url.absoluteString + "processor=2"

        // THEN both images are loaded and processors are applied
        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, ["1"])
        }
        expect(pipeline).toLoadImage(with: request2) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, ["2"])
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            // THEN original image is loaded twice - this is how it would work
            // if you were using ImagePipeline form version 7.0 with a legacy
            // `loadKey` semantics which were taking processors into account
            // when comparing load keys.
            XCTAssertEqual(self.dataLoader.createdTaskCount, 2)
        }
    }

    // MARK: - Cancellation

    func testCancellation() {
        dataLoader.queue.isSuspended = true

        // GIVEN two equivalent requests

        // WHEN both tasks are cancelled the image loading session is cancelled

        _ = expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        let task1 = pipeline.loadImage(with: Test.request)
        let task2 = pipeline.loadImage(with: Test.request)
        wait() // wait until the tasks is started or we might be cancelling non-exisitng task

        _ = expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        task1.cancel()
        task2.cancel()
        wait()
    }

    func testCancellationOnlyCancelOneTask() {
        dataLoader.queue.isSuspended = true

        // GIVEN two equivalent requests

        let task1 = pipeline.loadImage(with: Test.request) { _,_ in
            XCTFail()
        }

        expect(pipeline).toLoadImage(with: Test.request)

        // WHEN cancelling only only only one of the tasks
        task1.cancel()

        // THEN the image is still loaded

        self.dataLoader.queue.isSuspended = false

        wait()
    }

    // MARK: - Misc

    func testSubscribingToExisingSessionWhenProcessingAlreadyStarted() {
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let processors = ProcessorFactory()
        let request1 = ImageRequest(url: Test.url).processed(with: processors.make(id: "1"))
        let request2 = ImageRequest(url: Test.url).processed(with: processors.make(id: "1"))

        let expectation2 = self.expectation(description: "Second request completed")

        let observation = queue.observe(\.operations) { (_, _) in
            XCTAssertEqual(queue.operations.count, 1)
            DispatchQueue.main.async {
                // WHEN loading image with the same request and processing for
                // the first request has already started
                self.pipeline.loadImage(with: request2) { response, _ in
                    // THEN the image is still loaded and processors is applied
                    XCTAssertEqual(response?.image.nk_test_processorIDs, ["1"])
                    XCTAssertNotNil(response)
                    expectation2.fulfill()
                }
                queue.isSuspended = false
            }
            self.observations[0].invalidate()
        }
        self.observations.append(observation)

        expect(pipeline).toLoadImage(with: request1) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs, ["1"])
        }

        wait { _ in
            // THEN the original image is loaded only once, but processors are
            // applied twice
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
            XCTAssertEqual(processors.numberOfProcessorsApplied, 2)
        }
    }

    func testThatProgressIsReported() {
        dataLoader.results[defaultURL] = .success(
            (Data(count: 20), URLResponse(url: defaultURL, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )
        dataLoader.queue.isSuspended = true

        for _ in 0..<3 {
            let request = ImageRequest(url: defaultURL)

            let expectTaskFinished = self.expectation(description: "Task finished")
            let expectProgressFinished = self.expectation(description: "Progress finished")

            var expected: [(Int64, Int64)] = [(10, 20), (20, 20)]
            pipeline.loadImage(
                with: request,
                progress: { _, completed, total in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertTrue(expected.first?.0 == completed)
                    XCTAssertTrue(expected.first?.1 == total)
                    expected.remove(at: 0)
                    if expected.isEmpty {
                        expectProgressFinished.fulfill()
                    }
            },
                completion: { _,_ in
                    expectTaskFinished.fulfill()
            })
        }
        dataLoader.queue.isSuspended = false

        wait()
    }

    func testDisablingDeduplication() {
        let imagePipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isDeduplicationEnabled = false
        }

        dataLoader.queue.isSuspended = true

        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)
        XCTAssertEqual(request1.loadKey, request2.loadKey)

        expect(imagePipeline).toLoadImage(with: request1)
        expect(imagePipeline).toLoadImage(with: request2)

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
