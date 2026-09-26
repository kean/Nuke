// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite(.serialized)
@MainActor
struct ImageProcessingPerformanceTests {
    @Test
    func creatingProcessorIdentifiers() {
        let decompressor = ImageProcessors.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)

        measure {
            for _ in 0..<25_000 {
                _ = decompressor.identifier
            }
        }
    }

    @Test
    func comparingTwoProcessorCompositions() {
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "123"), ImageProcessors.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "124"), ImageProcessors.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)])

        measure {
            for _ in 0..<25_000 {
                if lhs.hashableIdentifier == rhs.hashableIdentifier {
                    // do nothing
                }
            }
        }
    }

    @Test
    func imageDecoding() {
        let decoder = ImageDecoders.Default()

        let data = Test.data
        measure {
            for _ in 0..<1_000 {
                _ = try? decoder.decode(data)
            }
        }
    }

    // MARK: Decompressing

    /// The pipeline decompresses every image before it hands it over, so that
    /// the main thread doesn't decode the pixels when it first draws it:
    /// `preparingForDisplay()` on UIKit, which PR #990 made the default, and a
    /// Core Graphics draw without it.
    @Test(arguments: [true, false])
    func decompressImagePerformance(isUsingPrepareForDisplay: Bool) throws {
        let pipeline = ImagePipeline { $0.isUsingPrepareForDisplay = isUsingPrepareForDisplay }
        let delegate = DefaultDelegate()
        let decoder = ImageDecoders.Default()
        let data = Test.data
        let request = ImageRequest(url: Test.url)

        // Fresh images for every sample: an image keeps the pixels it was
        // decompressed into, so decompressing the same one again times a
        // cache hit.
        let name = "decompressImagePerformance(isUsingPrepareForDisplay: \(isUsingPrepareForDisplay))"
        try measure(name, iterations: 10, setup: {
            try (0..<20).map { _ in ImageResponse(container: try decoder.decode(data), request: request) }
        }) { responses in
            responses.map { delegate.decompress(response: $0, request: request, pipeline: pipeline) }
        }
    }

    // MARK: Creating Thumbnails

    @Test
    func resizeImage() throws {
        let processor = ImageProcessors.Resize(size: CGSize(width: 64, height: 64), unit: .pixels)

        // A fresh image for every sample: Core Graphics keeps what it drew an
        // image at, so resizing the same one again times a cache hit.
        try measure(iterations: 10, setup: { try #require(makeHighResolutionImage()) }) { image in
            processor.process(image)
        }
    }

    @Test
    func createThumbnail() throws {
        let image = try #require(makeHighResolutionImage())
        let data = try #require(ImageEncoders.ImageIO(type: .jpeg).encode(image))
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 64, height: 64), unit: .pixels)

        measure {
            for _ in 0..<10 {
                _ = options.makeThumbnail(with: data)
            }
        }
    }

    // Should be roughly identical to the flexible target size.
    @Test
    func createThumbnailStaticSize() throws {
        let image = try #require(makeHighResolutionImage())
        let data = try #require(ImageEncoders.ImageIO(type: .jpeg).encode(image))
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 64)

        measure {
            for _ in 0..<10 {
                _ = options.makeThumbnail(with: data)
            }
        }
    }
}

/// The default implementation of every method, which is what a pipeline
/// without a delegate of its own runs.
private final class DefaultDelegate: ImagePipeline.Delegate {}

private func makeHighResolutionImage() -> PlatformImage? {
    ImageProcessors.Resize(width: 4000, unit: .pixels, upscale: true).process(Test.image)
}
