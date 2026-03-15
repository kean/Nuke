// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeExtensions

@Suite struct ImagePipelineProgressiveDecodingTests {
    let dataLoader: MockProgressiveDataLoader
    let pipeline: ImagePipeline
    let cache: MockImageCache

    init() async {
        let dataLoader = MockProgressiveDataLoader()
        let cache = MockImageCache()
        self.dataLoader = dataLoader
        self.cache = cache

        await ResumableDataStorage.shared.removeAllResponses()

        // We make two important assumptions with this setup:
        //
        // 1. Image processing is serial which means that all partial images are
        // going to be processed and sent to the client before the final image is
        // processed. So there's never going to be a situation where the final
        // image is processed before one of the partial images.
        //
        // 2. Each data chunk produced by a data loader always results in a new
        // scan. The way we split the data guarantees that.

        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.isStoringPreviewsInMemoryCache = true
            $0.imageProcessingQueue.maxConcurrentOperationCount = 1
        }
    }

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

    @Test @MainActor func paritalImagesAreDisplayed() async {
        // Given
        let imageView = _ImageView()

        var options = ImageLoadingOptions()
        options.pipeline = pipeline

        let expectPartialImageProduced = TestExpectation()
        nonisolated(unsafe) var partialCount = 0

        let expectedFinalLoaded = TestExpectation()

        // When/Then
        NukeExtensions.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            progress: { response, _, _ in
                if let image = response?.image {
                    #expect(imageView.image === image)
                    partialCount += 1
                    // We expect two partial images (at 5 scans, and 9 scans marks).
                    if partialCount == 2 {
                        expectPartialImageProduced.fulfill()
                    }
                    self.dataLoader.resume()
                }
            },
            completion: { result in
                #expect(imageView.image === result.value?.image)
                expectedFinalLoaded.fulfill()
            }
        )
        await expectPartialImageProduced.wait()
        await expectedFinalLoaded.wait()
    }

    @Test @MainActor func disablingProgressiveRendering() async {
        // Given
        let imageView = _ImageView()

        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        options.isProgressiveRenderingEnabled = false

        let expectPartialImageProduced = TestExpectation()
        nonisolated(unsafe) var partialCount = 0

        let expectedFinalLoaded = TestExpectation()

        // When/Then
        NukeExtensions.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            progress: { response, _, _ in
                if response?.image != nil {
                    #expect(imageView.image == nil)
                    partialCount += 1
                    // We expect two partial images (at 5 scans, and 9 scans marks).
                    if partialCount == 2 {
                        expectPartialImageProduced.fulfill()
                    }
                    self.dataLoader.resume()
                }
            },
            completion: { result in
                #expect(imageView.image === result.value?.image)
                expectedFinalLoaded.fulfill()
            }
        )
        await expectPartialImageProduced.wait()
        await expectedFinalLoaded.wait()
    }
#endif
}
