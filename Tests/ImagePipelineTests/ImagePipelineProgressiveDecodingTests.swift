// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineProgressiveDecodingTests: XCTestCase {
    private var dataLoader: MockProgressiveDataLoader!
    private var pipeline: ImagePipeline!
    private var cache: MockImageCache!
    private var processorsFactory: MockProcessorFactory!

    override func setUp() {
        dataLoader = MockProgressiveDataLoader()
        ResumableDataStorage.shared.removeAll()

        cache = MockImageCache()
        processorsFactory = MockProcessorFactory()

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
            $0.imageCache = cache
            $0.isProgressiveDecodingEnabled = true
            $0.isStoringPreviewsInMemoryCache = true
            $0.imageProcessingQueue.maxConcurrentOperationCount = 1
        }
    }

    // MARK: - Basics

    // Very basic test, just make sure that partial images get produced and
    // that the completion handler is called at the end.
    func testProgressiveDecoding() {
        // Given
        // - An image which supports progressive decoding
        // - A pipeline with progressive decoding enabled

        // Then two scans are produced
        let expectPartialImageProduced = self.expectation(description: "Partial Image Is Produced")
        expectPartialImageProduced.expectedFulfillmentCount = 2

        // Then the final image is produced
        let expectFinalImageProduced = self.expectation(description: "Final Image Is Produced")

        // When
        pipeline.loadImage(
            with: Test.request,
            progress: { response, completed, total in
                // This works because each new chunk resulted in a new scan
                if let container = response?.container {
                    // Then image previews are produced
                    XCTAssertTrue(container.isPreview)

                    // Then the preview is stored in memory cache
                    let cached = self.cache[Test.request]
                    XCTAssertNotNil(cached)
                    XCTAssertTrue(cached?.isPreview ?? false)
                    XCTAssertEqual(cached?.image, container.image)

                    expectPartialImageProduced.fulfill()
                    self.dataLoader.resume()
                }
            },
            completion: { result in
                // Then the final image is produced
                switch result {
                case let .success(response):
                    XCTAssertFalse(response.container.isPreview)
                case .failure:
                    XCTFail("Unexpected failure")
                }

                // Then the preview is overwritted with the final image in memory cache
                let cached = self.cache[Test.request]
                XCTAssertNotNil(cached)
                XCTAssertFalse(cached?.isPreview ?? false)
                XCTAssertEqual(cached?.image, result.value?.image)

                expectFinalImageProduced.fulfill()
            }
        )

        wait()
    }

    func testThatFailedPartialImagesAreIgnored() {
        // Given
        class FailingPartialsDecoder: ImageDecoding {
            func decode(_ data: Data) -> ImageContainer? {
                return ImageDecoders.Default().decode(data)
            }
        }

        let registry = ImageDecoderRegistry()

        registry.register { _ in
            FailingPartialsDecoder()
        }

        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = registry.decoder(for:)
        }

        // When/Then
        let finalLoaded = self.expectation(description: "Final image loaded")

        pipeline.loadImage(
            with: Test.url,
            progress: { image, _, _ in
                XCTAssertNil(image, "Expected partial images to never be produced") // Partial images never produced.
                self.dataLoader.resume()
            },
            completion: { result in
                XCTAssertTrue(result.isSuccess, "Expected the final image to be produced")
                finalLoaded.fulfill()
            }
        )

        wait()
    }

    // MARK: - Image Processing

    #if !os(macOS)
    func testThatPartialImagesAreResized() {
        // Given
        let image = PlatformImage(data: dataLoader.data)
        XCTAssertEqual(image?.cgImage?.width, 450)
        XCTAssertEqual(image?.cgImage?.height, 300)

        let request = ImageRequest(
            url: Test.url,
            processors: [ImageProcessors.Resize(size: CGSize(width: 45, height: 30), unit: .pixels)]
        )

        // When/Then
        expect(pipeline, dataLoader).toProducePartialImages(
            for: request,
            progress: { response, _, _ in
                if let image = response?.image {
                    XCTAssertEqual(image.cgImage?.width, 45, "Expected progressive image to be resized")
                    XCTAssertEqual(image.cgImage?.height, 30, "Expected progressive image to be resized")
                }
            },
            completion: { result in
                XCTAssertTrue(result.isSuccess, "Expected the final image to be produced")
                let image = result.value?.image
                XCTAssertEqual(image?.cgImage?.width, 45, "Expected the final image to be resized")
                XCTAssertEqual(image?.cgImage?.height, 30, "Expected the final image to be resized")
            }
        )

        wait()
    }
    #endif

    func testThatPartialImagesAreProcessed() {
        // Given
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "_image_processor")])

        // When/Then
        expect(pipeline, dataLoader).toProducePartialImages(
            for: request,
            progress: { response, _, _ in
                if let image = response?.image {
                    XCTAssertEqual(image.nk_test_processorIDs.count, 1)
                    XCTAssertEqual(image.nk_test_processorIDs.first, "_image_processor")
                }
            },
            completion: { result in
                let image = result.value?.image
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
            completion: { result in
                XCTAssertTrue(imageView.image === result.value?.image)
                expectedFinalLoaded.fulfill()
            }
        )
        wait()

        ImagePipeline.popShared()
    }

    func testDisablingProgressiveRendering() {
        // Given
        ImagePipeline.pushShared(pipeline)

        let imageView = _ImageView()

        var options = ImageLoadingOptions()
        options.isProgressiveRenderingEnabled = false

        let expectPartialImageProduced = self.expectation(description: "Partial Image Produced")
        // We expect two partial images (at 5 scans, and 9 scans marks).
        expectPartialImageProduced.expectedFulfillmentCount = 2

        let expectedFinalLoaded = self.expectation(description: "Final Image Produced")

        // When/Then
        Nuke.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            progress: { response, _, _ in
                if response?.image != nil {
                    XCTAssertNil(imageView.image)
                    expectPartialImageProduced.fulfill()
                    self.dataLoader.resume()
                }
            },
            completion: { result in
                XCTAssertTrue(imageView.image === result.value?.image)
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
                XCTAssertNil(response, "Expected partial images to never be produced")
                self.dataLoader.resume()
            },
            completion: { result in
                XCTAssertTrue(result.isSuccess)
                expectFinalImageProduced.fulfill()
            }
        )
        wait()
    }

    // MARK: Back Pressure

    func testBackpressureImageDecoding() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "a") }
        }

        let queue = pipeline.configuration.imageDecodingQueue

        // When we receive progressive image data at a higher rate that we can
        // process (we suspended the queue in test) we don't try to process
        // new scans until we finished processing the first one.

        queue.isSuspended = true
        expect(queue).toFinishWithEnqueuedOperationCount(2) // 1 partial, 1 final

        let finalLoaded = self.expectation(description: "Final image produced")

        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])
        pipeline.loadImage(
            with: request,
            progress: { image, _, _ in
                if image != nil {
                    // We don't expect partial to finish, because as soon as
                    // we create operation to create final image, partial
                    // operations is going to be finished before even starting
                }
                self.dataLoader.resume()
            },
            completion: { result in
                XCTAssertTrue(result.isSuccess)
                finalLoaded.fulfill()
            }
        )

        wait()
    }

    func testBackpressureProcessingImageProcessingOperationCancelled() throws {
        // Given
        let imageProcessingQueue = pipeline.configuration.imageProcessingQueue
        imageProcessingQueue.isSuspended = true

        // When the first chunk is delivered
        // Then the first processing operation is enqueue
        let observer = expect(imageProcessingQueue).toEnqueueOperationsWithCount(1)

        let imageLoadCompleted = NSNotification.Name(rawValue: "ImageLoadCompleted")

        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])
        pipeline.loadImage(
            with: request,
            progress: { image, _, _ in

            },
            completion: { result in
                XCTAssertTrue(result.isSuccess)
                NotificationCenter.default.post(name: imageLoadCompleted, object: nil)
            }
        )
        wait()

        // When the second chunk is deliverd, the new operation
        // is not created
        dataLoader.serveNextChunk()
        let expectation = self.expectation(description: "NoOperationCreated")
        expectation.isInverted = true
        wait(for: [expectation], timeout: 0.2)

        XCTAssertEqual(imageProcessingQueue.operationCount, 1)

        // When last chunk is delivered, initial processing
        // operation is cancelled
        let operation = try XCTUnwrap(observer.operations.first)
        expect(operation).toCancel()

        dataLoader.serveNextChunk()
        wait()

        // Then final image is loaded
        expectNotification(imageLoadCompleted)
        imageProcessingQueue.isSuspended = false
        wait()
    }

    // MARK: Memory Cache

    func testIntermediateMemoryCachedResultsAreDelivered() {
        // GIVEN intermediate result stored in memory cache
        let request = ImageRequest(url: Test.url, processors: [
            processorsFactory.make(id: "1"),
            processorsFactory.make(id: "2")
        ])
        let intermediateRequest = ImageRequest(url: Test.url, processors: [
            processorsFactory.make(id: "1")
        ])
        cache[intermediateRequest] = ImageContainer(image: Test.image, isPreview: true)

        pipeline.configuration.dataLoadingQueue.isSuspended = true // Make sure no data is loaded

        // WHEN/THEN the pipeline find the first preview in the memory cache,
        // applies the remaining processors and delivers it
        let previewDelivered = self.expectation(description: "previewDelivered")
        pipeline.loadImage(with: request) { response, _, _ in
            guard let response = response else {
                return XCTFail()
            }
            XCTAssertEqual(response.image.nk_test_processorIDs, ["2"])
            XCTAssertTrue(response.container.isPreview)
            previewDelivered.fulfill()
        } completion: { _ in
            // Do nothing
        }
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

    // We expect two partial images (at 5 scans, and 9 scans marks).
    func toProducePartialImages(for request: ImageRequest = Test.request,
                                withCount count: Int = 2,
                                progress: ((_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void)? = nil,
                                completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) {
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
            completion: { result in
                completion?(result)
                XCTAssertTrue(result.isSuccess)
                expectFinalImageProduced.fulfill()
            }
        )
    }
}
