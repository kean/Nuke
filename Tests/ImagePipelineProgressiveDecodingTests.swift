// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineProgressiveDecodingTests: XCTestCase {
    private var dataLoader: MockProgressiveDataLoader!
    private var pipeline: ImagePipeline!
    private var delegate: MockImageTaskDelegate!

    override func setUp() {
        dataLoader = MockProgressiveDataLoader()
        delegate = MockImageTaskDelegate()
        ResumableData.cache.removeAll()

        // We make two important assumptions with this setup:
        //
        // 1. Image processing is serial which means that all partial images are
        // going to be processed and sent to the client before the final image is
        // processed. So there's never going to be a situation where the final
        // image is processed before one of the partial images.
        //
        // 2. Each data chunck produced by a data loader always results in a new
        // scan. The way we split the data guarantees that.

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.imageProcessingQueue.maxConcurrentOperationCount = 1
        }
    }

    // MARK: - Basics

    // Very basic test, just make sure that partial images get produced and
    // that the completion handler is called at the end.
    func testProgressiveDecoding() {
        expect(pipeline, dataLoader).toProducePartialImages()
        wait()
    }

    func testThatFailedPartialImagesAreIgnored() {
        // Given
        class FailingPartialsDecoder: ImageDecoding {
            func decode(data: Data, isFinal: Bool) -> Image? {
                if isFinal {
                    return ImageDecoder().decode(data: data, isFinal: isFinal)
                }
                return nil // Fail every partial
            }
        }

        ImageDecoderRegistry.shared.register { _ in
            FailingPartialsDecoder()
        }

        // When/Then
        let finalLoaded = self.expectation(description: "Final image loaded")

        delegate.progressHandler = { [unowned self] _, _ in
            self.dataLoader.resume()
        }

        delegate.progressiveResponseHandler = { _ in
            XCTFail("Expected partial images to never be produced")
        }

        delegate.completion = { response, _ in
            XCTAssertNotNil(response, "Expected the final image to be produced")
            finalLoaded.fulfill()
        }

        pipeline.imageTask(with: Test.request, delegate: delegate).start()

        wait()

        ImageDecoderRegistry.shared.clear()
    }

    // MARK: - Image Processing

    #if !os(macOS)
    func testThatPartialImagesAreResized() {
        // Given
        let image = Image(data: dataLoader.data)
        XCTAssertEqual(image?.cgImage?.width, 450)
        XCTAssertEqual(image?.cgImage?.height, 300)

        let request = ImageRequest(
            url: Test.url,
            targetSize: CGSize(width: 45, height: 30),
            contentMode: .aspectFill
        )

        // When/Then
        delegate.progressiveResponseHandler = { response in
            let image = response.image
            XCTAssertEqual(image.cgImage?.width, 45, "Expected progressive image to be resized")
            XCTAssertEqual(image.cgImage?.height, 30, "Expected progressive image to be resized")
        }

        delegate.completion = { response, _ in
            XCTAssertNotNil(response, "Expected the final image to be produced")
            let image = response?.image
            XCTAssertEqual(image?.cgImage?.width, 45, "Expected the final image to be resized")
            XCTAssertEqual(image?.cgImage?.height, 30, "Expected the final image to be resized")
        }

        expect(pipeline, dataLoader).toProducePartialImages(for: request, delegate: delegate)

        wait()
    }
    #endif

    func testThatPartialImagesAreProcessed() {
        // Given
        let request = Test.request.processed(with: MockImageProcessor(id: "_image_processor"))

        // When/Then
        delegate.progressiveResponseHandler = { response in
            let image = response.image
            XCTAssertEqual(image.nk_test_processorIDs.count, 1)
            XCTAssertEqual(image.nk_test_processorIDs.first, "_image_processor")
        }
        delegate.completion = { response, _ in
            let image = response?.image
            XCTAssertEqual(image?.nk_test_processorIDs.count, 1)
            XCTAssertEqual(image?.nk_test_processorIDs.first, "_image_processor")
        }
        expect(pipeline, dataLoader).toProducePartialImages(for: request, delegate: delegate)
        wait()
    }

    func testProgressiveDecodingDisabled() {
        // Given
        var configuration = pipeline.configuration
        configuration.isProgressiveDecodingEnabled = false
        pipeline = ImagePipeline(configuration: configuration)

        // When/Then
        let expectFinalImageProduced = self.expectation(description: "Final Image Is Produced")
        delegate.progressHandler = { [unowned self] _, _ in
            self.dataLoader.resume()
        }
        delegate.progressiveResponseHandler = { _ in
            XCTFail("Expected partial images to never be produced")
        }
        delegate.completion = { response, _ in
            XCTAssertNotNil(response)
            expectFinalImageProduced.fulfill()
        }
        pipeline.imageTask(with: Test.request, delegate: delegate).start()

        wait()
    }

    // MARK: Back Pressure

    func testRedundantPartialsArentProducedWhenDataIsProcudedAtHighRate() {
        let queue = pipeline.configuration.imageDecodingQueue

        // When we receive progressive image data at a higher rate that we can
        // process (we suspended the queue in test) we don't try to process
        // new scans until we finished processing the first one.

        queue.isSuspended = true
        expect(queue).toFinishWithEnqueuedOperationCount(2) // 1 partial, 1 final

        let finalLoaded = self.expectation(description: "Final image produced")

        delegate.progressHandler = { [unowned self] _, _ in
            self.dataLoader.resume()
        }
        delegate.progressiveResponseHandler = { _ in
            XCTFail("Expected partial images to never be produced")
        }
        delegate.completion = { response, _ in
            XCTAssertNotNil(response)
            finalLoaded.fulfill()
        }

        pipeline.imageTask(with: Test.request.processed(key: "1") { $0 }, delegate: delegate).start()

        wait()
    }
}

private extension XCTestCase {
    func expect(_ pipeline: ImagePipeline, _ dataLoader: MockProgressiveDataLoader) -> TestExpectationProgressivePipeline {
        return TestExpectationProgressivePipeline(test: self, pipeline: pipeline, dataLoader: dataLoader)
    }
}

private struct TestExpectationProgressivePipeline {
    let test: XCTestCase
    let pipeline: ImagePipeline
    let dataLoader: MockProgressiveDataLoader
    let delegate = MockImageTaskDelegate()

    // We expect two partial images (at 5 scans, and 9 scans marks).
    func toProducePartialImages(for request: ImageRequest = Test.request, withCount count: Int = 2, delegate: MockImageTaskDelegate? = nil) {
        let expectPartialImageProduced = test.expectation(description: "Partial Image Is Produced")
        expectPartialImageProduced.expectedFulfillmentCount = count

        let expectFinalImageProduced = test.expectation(description: "Final Image Is Produced")

        self.delegate.next = delegate

        self.delegate.progressiveResponseHandler = { response in
            expectPartialImageProduced.fulfill()
            self.dataLoader.resume()
        }

        self.delegate.completion = { response, error in
            XCTAssertNotNil(response)
            expectFinalImageProduced.fulfill()
        }

        pipeline.imageTask(with: request, delegate: self.delegate).start()
    }
}
