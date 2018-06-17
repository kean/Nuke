// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineProgressiveDecodingTests: XCTestCase {
    private var dataLoader: _MockProgressiveDataLoader!
    private var pipeline: ImagePipeline!

    override func setUp() {
        dataLoader = _MockProgressiveDataLoader()
        ResumableData._cache.removeAll()

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

        pipeline.loadImage(
            with: Test.url,
            progress: { image, _, _ in
                XCTAssertNil(image) // Partial images never produced.
                self.dataLoader.resume()
            },
            completion: { response, _ in
                XCTAssertNotNil(response)
                finalLoaded.fulfill()
        })

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
        expect(pipeline, dataLoader).toProducePartialImages(
            for: request,
            progress: { response, _, _ in
                if let image = response?.image {
                    XCTAssertEqual(image.cgImage?.width, 45)
                    XCTAssertEqual(image.cgImage?.height, 30)
                }
            },
            completion: { response, _ in
                XCTAssertNotNil(response)
                let image = response?.image
                XCTAssertEqual(image?.cgImage?.width, 45)
                XCTAssertEqual(image?.cgImage?.height, 30)
            }
        )

        wait()
    }
    #endif

    func testThatPartialImagesAreProcessed() {
        // Given
        let request = Test.request.processed(with: MockImageProcessor(id: "_image_processor"))

        // When/Then
        expect(pipeline, dataLoader).toProducePartialImages(
            for: request,
            progress: { response, _, _ in
                if let image = response?.image {
                    XCTAssertEqual(image.nk_test_processorIDs.count, 1)
                    XCTAssertEqual(image.nk_test_processorIDs.first, "_image_processor")
                }
            },
            completion: { response, _ in
                let image = response?.image
                XCTAssertEqual(image?.nk_test_processorIDs.count, 1)
                XCTAssertEqual(image?.nk_test_processorIDs.first, "_image_processor")
            }
        )
        wait()
    }

    func testParitalImagesAreDisplayed() {
        // Given
        ImagePipeline.pushShared(pipeline)

        let imageView = _ImageView()

        let expectPartialImageProduced = self.expectation(description: "Partial Image Produced")
        // We expect two partial images (at 5 scans, and 9 scans marks).
        expectPartialImageProduced.expectedFulfillmentCount = 2

        let expectedFinalLoaded = self.expectation(description: "Final Image Produced")

        // When/Then
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            progress: { response, _, _ in
                if let image = response?.image {
                    XCTAssertTrue(imageView.image === image)
                    expectPartialImageProduced.fulfill()
                    self.dataLoader.resume()
                }
            },
            completion: { response, _ in
                XCTAssertTrue(imageView.image === response?.image)
                expectedFinalLoaded.fulfill()
            }
        )
        wait()

        ImagePipeline.popShared()
    }

    func testProgressiveDecodingDisabled() {
        // Given
        var configuration = pipeline.configuration
        configuration.isProgressiveDecodingEnabled = false
        pipeline = ImagePipeline(configuration: configuration)

        // When/Then
        let expectFinalImageProduced = self.expectation(description: "Final Image Is Produced")
        pipeline.loadImage(
            with: Test.request,
            progress: { response, _, _ in
                XCTAssertNil(response)
                self.dataLoader.resume()
            },
            completion: { response, error in
                expectFinalImageProduced.fulfill()
            }
        )
        wait()
    }

    // MARK: Back Pressure

    func testRedundantParialsArentProducedWhenDataIsProcudedAtHighRate() {
        let queue = pipeline.configuration.imageDecodingQueue

        // When we receive progressive image data at a higher rate that we can
        // process (we suspended the queue in test) we don't try to process
        // new scans until we finished processing the first one.

        queue.isSuspended = true
        expect(queue).toFinishWithEnqueuedOperationCount(2) // 1 partial, 1 final

        let finalLoaded = self.expectation(description: "Final image produced")

        pipeline.loadImage(
            with: Test.request.processed(key: "1") { $0 },
            progress: { image, _, _ in
                if image != nil {
                    // We don't expect partial to finish, because as soon as
                    // we create operation to create final image, partial
                    // operations is going to be finished before even starting
                }
                self.dataLoader.resume()
            },
            completion: { response, _ in
                XCTAssertNotNil(response)
                finalLoaded.fulfill()
        })

        wait()
    }
}

private extension XCTestCase {
    func expect(_ pipeline: ImagePipeline, _ dataLoader: _MockProgressiveDataLoader) -> TestExpectationProgressivePipeline {
        return TestExpectationProgressivePipeline(test: self, pipeline: pipeline, dataLoader: dataLoader)
    }
}

private struct TestExpectationProgressivePipeline {
    let test: XCTestCase
    let pipeline: ImagePipeline
    let dataLoader: _MockProgressiveDataLoader

    // We expect two partial images (at 5 scans, and 9 scans marks).
    func toProducePartialImages(for request: ImageRequest = Test.request, withCount count: Int = 2, progress: ImageTask.ProgressHandler? = nil, completion: ImageTask.Completion? = nil) {
        let expectPartialImageProduced = test.expectation(description: "Partial Image Is Produced")
        expectPartialImageProduced.expectedFulfillmentCount = count

        let expectFinalImageProduced = test.expectation(description: "Final Image Is Produced")

        pipeline.loadImage(
            with: request,
            progress: { image, completed, total in
                progress?(image, completed, total)

                // This works because each new chunk resulted in a new scan
                if image != nil {
                    expectPartialImageProduced.fulfill()
                    self.dataLoader.resume()
                }
            },
            completion: { response, error in
                completion?(response, error)
                XCTAssertNotNil(response)
                expectFinalImageProduced.fulfill()
        })
    }
}

// One-shot data loader that servers data split into chunks, only send one chunk
// per one `resume()` call.
private class _MockProgressiveDataLoader: DataLoading {
    let urlResponse: HTTPURLResponse
    var chunks: [Data]
    let data = Test.data(name: "progressive", extension: "jpeg")

    class _MockTask: Cancellable {
        func cancel() {
            // Do nothing
        }
    }

    private var didReceiveData: (Data, URLResponse) -> Void = { _ ,_ in }
    private var completion: (Error?) -> Void = { _ in }

    init() {
        self.urlResponse = HTTPURLResponse(
            url: Test.url,
            mimeType: "jpeg",
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        self.chunks = Array(_createChunks(for: data, size: data.count / 3))
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        self.didReceiveData = didReceiveData
        self.completion = completion
        self.resume()
        return _MockTask()
    }

    // Serves the next chunk.
    func resume(_ completed: @escaping () -> Void = {}) {
        DispatchQueue.main.async {
            if let chunk = self.chunks.first {
                self.chunks.removeFirst()
                self.didReceiveData(chunk, self.urlResponse)
                if self.chunks.isEmpty {
                    self.completion(nil)
                    completed()
                }
            }
        }
    }
}
