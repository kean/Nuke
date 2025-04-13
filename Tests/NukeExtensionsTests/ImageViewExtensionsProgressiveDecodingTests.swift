// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke
@testable import NukeExtensions

@ImagePipelineActor
@Suite struct ImagePipelineProgressiveDecodingTests {
    private var dataLoader: MockProgressiveDataLoader!
    private var pipeline: ImagePipeline!
    private var cache: MockImageCache!
    private var processorsFactory: MockProcessorFactory!

    init() {
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

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

    @MainActor
    @Test func paritalImagesAreDisplayed() async {
        // Given
        ImagePipeline.pushShared(pipeline)

        let imageView = _ImageView()
        var previewCount = 0

        // When
        await withUnsafeContinuation { continuation in
            NukeExtensions.loadImage(
                with: Test.request,
                into: imageView,
                progress: { response, _, _ in
                    if let image = response?.image {
                        previewCount += 1
                        #expect(imageView.image === image)
                        self.dataLoader.resume()
                    }
                },
                completion: { result in
                    #expect(imageView.image === result.value?.image)
                    continuation.resume()
                }
            )
        }

        // Then we expect two partial images (at 5 scans, and 9 scans marks).
        #expect(previewCount == 2)

        ImagePipeline.popShared()
    }

    @MainActor
    @Test func disablingProgressiveRendering() async {
        // Given
        ImagePipeline.pushShared(pipeline)

        let imageView = _ImageView()
        var previewCount = 0

        var options = ImageLoadingOptions()
        options.isProgressiveRenderingEnabled = false

        // When
        await withUnsafeContinuation { continuation in
            NukeExtensions.loadImage(
                with: Test.request,
                options: options,
                into: imageView,
                progress: { response, _, _ in
                    if response?.image != nil {
                        #expect(imageView.image == nil)
                        previewCount += 1
                        self.dataLoader.resume()
                    }
                },
                completion: { result in
                    #expect(imageView.image === result.value?.image)
                    continuation.resume()
                }
            )
        }

        // Then we expect two partial images (at 5 scans, and 9 scans marks).
        #expect(previewCount == 2)

        ImagePipeline.popShared()
    }
#endif
}
