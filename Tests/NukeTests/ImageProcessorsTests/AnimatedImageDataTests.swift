// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke

/// Covers what happens to ``ImageContainer/data`` – the encoded animation the
/// pipeline attaches to animated images – when a processor runs.
@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsAnimatedImageDataTests {
    @Test func processingDropsTheAttachedData() throws {
        // GIVEN an animated image, whose data describes the animation the
        // processor is about to replace with a single processed still
        let container = ImageContainer(image: Test.image, type: .gif, data: Test.animatedGIF())
        let processor = ImageProcessors.Resize(size: CGSize(width: 40, height: 40), unit: .pixels)

        let output = try processor.process(container, context: .mock)

        // THEN the data is gone: a renderer handed both would play the original
        // animation on top of the processed still.
        #expect(output.data == nil)
        #expect(output.type == .gif)
        #expect(output.image.sizeInPixels != container.image.sizeInPixels)
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
        let container = ImageContainer(image: Test.image, type: .gif, data: Test.animatedGIF())

        let output = try KeepsData().process(container, context: .mock)

        #expect(output.data != nil)
    }
}
