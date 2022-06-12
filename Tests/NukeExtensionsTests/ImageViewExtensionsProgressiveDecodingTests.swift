// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

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
        // 2. Each data chunk produced by a data loader always results in a new
        // scan. The way we split the data guarantees that.

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isProgressiveDecodingEnabled = true
            $0.isStoringPreviewsInMemoryCache = true
            $0.imageProcessingQueue.maxConcurrentOperationCount = 1
        }
    }

#if os(iOS) || os(tvOS) || os(macOS)

    @MainActor
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

    @MainActor
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
#endif
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
