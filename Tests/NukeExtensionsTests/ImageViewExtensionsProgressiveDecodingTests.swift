// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke
@testable import NukeExtensions

class ImagePipelineProgressiveDecodingTests: XCTestCase {
    private var dataLoader: MockProgressiveDataLoader!
    private var pipeline: ImagePipeline!
    private var cache: MockImageCache!
    private var processorsFactory: MockProcessorFactory!

    override func setUp() {
        super.setUp()

        dataLoader = MockProgressiveDataLoader()
        ResumableDataStorage.shared.removeAllResponses()

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
        NukeExtensions.loadImage(
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
        NukeExtensions.loadImage(
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
