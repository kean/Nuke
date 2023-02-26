// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageProcessingPerformanceTests: XCTestCase {
    func testCreatingProcessorIdentifiers() {
        let decompressor = ImageProcessors.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)

        measure {
            for _ in 0..<25_000 {
                _ = decompressor.identifier
            }
        }
    }

    func testComparingTwoProcessorCompositions() {
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

    func testImageDecoding() {
        let decoder = ImageDecoders.Default()

        let data = Test.data
        measure {
            for _ in 0..<1_000 {
                _ = try? decoder.decode(data)
            }
        }
    }

    // MARK: Creating Thumbnails

    func testResizeImage() throws {
        let image = try XCTUnwrap(makeHighResolutionImage())
        let processor = ImageProcessors.Resize(size: CGSize(width: 64, height: 64), unit: .pixels)

        measure {
            for _ in 0..<10 {
                _ = processor.process(image)
            }
        }
    }

    func testCreateThumbnail() throws {
        let image = try XCTUnwrap(makeHighResolutionImage())
        let data = try XCTUnwrap(ImageEncoders.ImageIO(type: .jpeg).encode(image))
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 64, height: 64), unit: .pixels)

        measure {
            for _ in 0..<10 {
                _ = options.makeThumbnail(with: data)
            }
        }
    }

    // Should be roughly identical to the flexible target size.
    func testCreateThumbnailStaticSize() throws {
        let image = try XCTUnwrap(makeHighResolutionImage())
        let data = try XCTUnwrap(ImageEncoders.ImageIO(type: .jpeg).encode(image))
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
