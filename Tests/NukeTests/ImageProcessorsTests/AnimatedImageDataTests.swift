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
        let container = try animatedContainer()
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
        let container = try animatedContainer()
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")

        let output = try processor.process(container, context: .mock)

        #expect(output.data == nil)
        #expect(output.animation == nil)
        #expect(output.type == .gif)
    }

    @Test func processorCanKeepTheDataByImplementingTheContainerMethod() throws {
        // GIVEN a processor that knows the data still matches the image
        struct KeepsData: ImageProcessing {
            func process(_ image: PlatformImage) -> PlatformImage? { image }
            func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
                container
            }
            var identifier: String { "test.keeps-data" }
        }
        let container = try animatedContainer()

        let output = try KeepsData().process(container, context: .mock)

        #expect(output.data != nil)
        #expect(output.animation != nil)
    }

    /// A container shaped the way the pipeline hands one over: the encoded
    /// animation, and the metadata parsed out of it.
    private func animatedContainer() throws -> ImageContainer {
        let data = Test.animatedGIF()
        return ImageContainer(image: Test.image, type: .gif, data: data, animation: try #require(AnimatedImageSource(data: data)))
    }
}
