// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: the default `ImageEncoding.encode(_:context:)` decides whether to pass
// the original data through by `container.type == .gif` instead of by whether
// the container still carries the data that describes its image.
//
// Since #958, `ImageDecoders.Default` attaches `ImageContainer.data` (and
// `animation`) to every animation it recognizes – GIF, APNG, animated WebP,
// HEIC and AVIF sequences – and processing or a thumbnail request drops them.
// The encoder wasn't updated, which breaks both directions:
//
// 1. An animated APNG/WebP/HEICS/AVIF container is re-encoded from its first
//    frame. With `DataCachePolicy.storeEncodedImages` (or
//    `ImagePipeline.Cache.storeCachedImage(_:for:caches: [.disk])`), the disk
//    cache ends up with a still: the animation plays from the memory cache and
//    becomes a still after a relaunch. "Animated Images" in NukeUI.docc lists
//    exactly two cases where an animation deliberately becomes a still (a
//    processed image and a thumbnail request); this is a third, undocumented
//    one – the same bug the changelog records as fixed for GIF ("Fix an issue
//    with `.gif` being encoded as `.jpeg` when `.storeEncodedImages` policy is
//    used").
//    Expected: the original data is returned. Actual: a JPEG/PNG of frame 0.
//
// 2. A GIF container *without* data – any processed GIF, and every GIF
//    thumbnail – encodes to `nil`, so it is never stored in the disk cache.
//    Expected: the still image is encoded. Actual: `nil`.
//    (The processed-GIF flavor of this was also reported from the pipeline
//    side as image-decode-process-tasks--processed-gif-never-stored-in-disk-cache;
//    the thumbnail flavor below has no processors at all. The existing test
//    `ImageEncodingProtocolTests.gifContainerWithoutDataReturnsNil` pins the
//    current behavior and would need updating with a fix.)
//
// Sources/Nuke/Encoding/ImageEncoding.swift:28
@Suite(.timeLimit(.minutes(5)))
struct AnimatedContainerEncodingBugRepro {
    private var context: ImageEncodingContext {
        ImageEncodingContext(request: Test.request, image: Test.image, urlResponse: nil)
    }

    @Test func animatedWebPIsPassedThrough() throws {
        // GIVEN an animated WebP decoded by the default decoder
        let data = Test.data(name: "animated", extension: "webp")
        let container = try ImageDecoders.Default().decode(data)
        #expect(container.type == .webp)
        #expect(container.animation != nil)

        // WHEN
        let encoded = try #require(ImageEncoders.Default().encode(container, context: context))

        // THEN the animation survives the disk cache
        #expect(encoded == data) // Actual: a JPEG of the first frame
        #expect(try ImageDecoders.Default().decode(encoded).animation != nil)
    }

    @Test func animatedPNGIsPassedThrough() throws {
        // GIVEN an APNG decoded by the default decoder
        let data = try #require(Test.animatedPNG(frameCount: 3, size: CGSize(width: 16, height: 16)))
        let container = try ImageDecoders.Default().decode(data)
        #expect(container.animation != nil)

        // WHEN
        let encoded = try #require(ImageEncoders.Default().encode(container, context: context))

        // THEN
        #expect(encoded == data) // Actual: a single-frame PNG
        #expect(try ImageDecoders.Default().decode(encoded).animation != nil)
    }

    @Test func animatedWebPStoredWithStoreEncodedImagesStaysAnimated() async throws {
        // GIVEN a pipeline that stores encoded images
        let data = Test.data(name: "animated", extension: "webp")
        let dataLoader = MockDataLoader()
        dataLoader.results[Test.url] = .success((data, URLResponse(url: Test.url, mimeType: "image/webp", expectedContentLength: data.count, textEncodingName: nil)))
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = .storeEncodedImages
        }

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        #expect(response.container.animation != nil)

        // THEN what a relaunch reads back from the disk cache is still animated
        let stored = try #require(dataCache.store[pipeline.cache.makeDataCacheKey(for: Test.request)])
        #expect(try ImageDecoders.Default().decode(stored).animation != nil) // Actual: nil
    }

    @Test func gifThumbnailIsEncoded() throws {
        // GIVEN a thumbnail of a GIF, which the decoder gives no data
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 4)
        let decoder = try #require(ImageDecoders.Default(context: ImageDecodingContext(request: request, data: Test.animatedGIF(), previewPolicy: .disabled)))
        let container = try decoder.decode(Test.animatedGIF())
        #expect(container.type == .gif)
        #expect(container.data == nil)

        // WHEN
        let encoded = ImageEncoders.Default().encode(container, context: context)

        // THEN the thumbnail can be stored in the disk cache
        #expect(encoded != nil) // Actual: nil
    }
}
