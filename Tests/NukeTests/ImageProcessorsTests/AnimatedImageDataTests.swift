// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke

/// Covers what happens to ``ImageContainer/data`` and ``ImageContainer/animation``
/// – the encoded animation the pipeline attaches to animated images, and the
/// metadata it parses out of it – when a processor runs.
@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsAnimatedImageDataTests {
    @Test func processingDropsTheAttachedData() throws {
        // GIVEN an animated image, whose data describes the animation the
        // processor is about to replace with a single processed still
        let container = animatedContainer()
        let processor = ImageProcessors.Resize(size: CGSize(width: 40, height: 40), unit: .pixels)

        let output = try processor.process(container, context: .mock)

        // THEN both are gone: a renderer handed either would play the original
        // animation on top of the processed still.
        #expect(output.data == nil)
        #expect(output.animation == nil)
        #expect(output.type == .gif)
        #expect(output.image.sizeInPixels != container.image.sizeInPixels)
    }

    @Test func coreImageFilterDropsTheAttachedData() throws {
        // GIVEN a processor that implements the container method itself and so
        // does not go through the default implementation
        let container = animatedContainer()
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")

        let output = try processor.process(container, context: .mock)

        #expect(output.data == nil)
        #expect(output.animation == nil)
        #expect(output.type == .gif)
    }

    @Test func processorCanKeepTheDataByImplementingTheContainerMethod() async throws {
        // GIVEN a processor that knows the data still matches the image it
        // returns, the way one that processes every frame does
        let processor = MockDataPreservingProcessor(id: "test.keeps-data")
        let data = Test.animatedGIF(frameCount: 3)
        let dataLoader = MockDataLoader()
        dataLoader.results[Test.url] = .success(
            (data, URLResponse(url: Test.url, mimeType: "gif", expectedContentLength: 0, textEncodingName: nil))
        )
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        // WHEN
        let request = ImageRequest(url: Test.url, processors: [processor])
        let response = try await pipeline.imageTask(with: request).response

        // THEN the pipeline calls the container method and delivers what it
        // returns: the processed still, with the data and the animation intact
        #expect(response.image.nk_test_processorIDs == ["test.keeps-data"])
        #expect(response.container.data == data)
        #expect(response.container.animation?.frameCount == 3)
    }

    /// A container shaped the way the pipeline hands one over: the encoded
    /// animation, and the metadata parsed out of it.
    private func animatedContainer() -> ImageContainer {
        let source = Test.animatedGIFSource()
        return ImageContainer(image: Test.image, type: .gif, data: source.data, animation: source)
    }
}
