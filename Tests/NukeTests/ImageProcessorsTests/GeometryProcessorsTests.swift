// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Testing
import Foundation
@testable import Nuke

#if canImport(UIKit)
import UIKit
#endif

/// What `Crop`, `Flip`, and `Rotate` have to get right the same way, since each
/// draws the image in a new bitmap.
@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsGeometryTests {
    static let processors: [any ImageProcessing] = [
        ImageProcessors.Crop(rect: CGRect(x: 1, y: 1, width: 3, height: 2), unit: .pixels),
        ImageProcessors.Flip(.horizontal),
        ImageProcessors.Flip(.vertical),
        ImageProcessors.Rotate(degrees: 90),
        ImageProcessors.Rotate(degrees: 180),
        ImageProcessors.Rotate(degrees: 270)
    ]

    @Test(arguments: processors)
    func opaqueImageStaysOpaque(processor: any ImageProcessing) throws {
        let input = Test.rgbImage(width: 6, height: 4)
        #expect(input.cgImage?.isOpaque == true)

        let output = try #require(processor.process(input))

        #expect(output.cgImage?.isOpaque == true)
    }

    @Test(arguments: processors)
    func alphaIsKept(processor: any ImageProcessing) throws {
        let input = Test.rgbImage(width: 6, height: 4, color: CGColor(red: 0, green: 0, blue: 1, alpha: 0.5), alphaInfo: .premultipliedLast)

        let output = try #require(processor.process(input))

        #expect(try pixelComponents(of: output, x: 1, y: 1) == pixelComponents(of: input, x: 1, y: 1))
    }

    @Test(arguments: processors)
    func wideGamutIsKept(processor: any ImageProcessing) throws {
        let input = Test.image(named: "image-p3", extension: "jpg")

        let output = try #require(processor.process(input))

        #expect(output.cgImage?.colorSpace?.isWideGamutRGB == true)
    }

    @Test(arguments: processors)
    func monochromeImageStaysMonochrome(processor: any ImageProcessing) throws {
        let input = Test.grayscaleImage(width: 6, height: 4)

        let output = try #require(processor.process(input))

        #expect(output.cgImage?.colorSpace?.model == .monochrome)
        #expect(try pixelComponents(of: output, x: 1, y: 1) == pixelComponents(of: input, x: 1, y: 1))
    }

    /// Core Graphics has no context for this format, so the fallback to RGB
    /// is what keeps it from failing.
    @Test(arguments: processors)
    func monochromeImageWithAlphaKeepsItsAlpha(processor: any ImageProcessing) throws {
        let input = Test.grayscaleWithAlphaImage(width: 6, height: 4, gray: 100, alpha: 128)

        let output = try #require(processor.process(input))

        #expect(try pixelComponents(of: output, x: 1, y: 1) == pixelComponents(of: input, x: 1, y: 1))
    }

    @Test func anyAngleKeepsAWideGamut() throws {
        let input = Test.image(named: "image-p3", extension: "jpg")

        let output = try #require(ImageProcessors.Rotate(degrees: 30).process(input))

        #expect(output.cgImage?.colorSpace?.isWideGamutRGB == true)
    }

    @Test func anyAngleWorksOnMonochromeImages() throws {
        let input = Test.grayscaleImage(width: 20, height: 20)

        let output = try #require(ImageProcessors.Rotate(degrees: 45).process(input))

        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.alpha(atX: 0, y: 0) == 0)
        #expect(pixels.alpha(atX: pixels.width / 2, y: pixels.height / 2) == 255)
    }

#if canImport(UIKit)
    @Test(arguments: processors)
    func scaleIsKept(processor: any ImageProcessing) throws {
        let input = UIImage(cgImage: PixelGrid(width: 6, height: 4).makeCGImage(), scale: 3, orientation: .up)

        let output = try #require(processor.process(input))

        #expect(output.scale == 3)
    }
#endif

    // MARK: Containers

    /// The rule of the `AnimatedImages` article: a processor applies to the
    /// poster, and what's left isn't animated.
    @Test(arguments: processors + [ImageProcessors.Tint(color: .red)] as [any ImageProcessing])
    func processedAnimationIsAStill(processor: any ImageProcessing) throws {
        let container = Test.container(named: "cat", extension: "gif")
        #expect(container.animation != nil)
        #expect(container.data != nil)
        let context = ImageProcessingContext(request: Test.request, response: ImageResponse(container: container, request: Test.request), isCompleted: true)

        let output = try processor.process(container, context: context)

        #expect(output.animation == nil)
        #expect(output.data == nil)
        #expect(output.type == .gif)
    }

    // MARK: Pipeline

    @Test func pipelineRunsThemInOrder() async throws {
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        let request = ImageRequest(url: Test.url, processors: [
            .crop(rect: CGRect(x: 0, y: 0, width: 100, height: 50), unit: .pixels),
            .rotate(degrees: 90),
            .flip(.horizontal),
            .tint(color: PlatformColor(red: 1, green: 0, blue: 0, alpha: 1))
        ])

        let image = try await pipeline.image(for: request)

        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == 50)
        #expect(cgImage.height == 100)
        #expect(try pixelComponents(of: image, x: 10, y: 10) == [255, 0, 0, 255])
    }

    @Test func cropWithNoPixelsFailsTheRequest() async throws {
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        let request = ImageRequest(url: Test.url, processors: [
            .crop(rect: CGRect(x: 10_000, y: 0, width: 10, height: 10), unit: .pixels)
        ])

        await #expect {
            _ = try await pipeline.image(for: request)
        } throws: { error in
            guard case .processingFailed = error as? ImagePipeline.Error else { return false }
            return true
        }
    }
}
