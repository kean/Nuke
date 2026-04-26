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

    // MARK: Creating Thumbnails

    @Test
    func resizeImage() throws {
        let image = try #require(makeHighResolutionImage())
        let processor = ImageProcessors.Resize(size: CGSize(width: 64, height: 64), unit: .pixels)

        measure {
            for _ in 0..<10 {
                _ = processor.process(image)
            }
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

private func makeHighResolutionImage() -> PlatformImage? {
    ImageProcessors.Resize(width: 4000, unit: .pixels, upscale: true).process(Test.image)
}
