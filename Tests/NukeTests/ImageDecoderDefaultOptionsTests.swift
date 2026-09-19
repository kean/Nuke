// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO
@testable import Nuke

#if canImport(UIKit)
import UIKit
#endif

/// The final images ``ImageDecoders/Default`` produces for the options a
/// request carries: thumbnails, orientation, and scale.
@Suite(.timeLimit(.minutes(5)))
struct ImageDecoderDefaultOptionsTests {

    // MARK: Thumbnails

    @Test func thumbnailRequestDecodesAThumbnail() throws {
        // Given
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)
        let context = ImageDecodingContext(request: request, data: Test.data)
        let decoder = try #require(ImageDecoders.Default(context: context))

        // When
        let container = try decoder.decode(Test.data)

        // Then the type is still sniffed from the data
        #expect(container.image.sizeInPixels == CGSize(width: 100, height: 75))
        #expect(container.type == .jpeg)
        #expect(!container.isPreview)
        #expect(container.userInfo.isEmpty)
    }

    @Test func thumbnailRequestForDataThatIsNotAnImageThrows() throws {
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)
        let data = Data(repeating: 0xAB, count: 512)
        let decoder = try #require(ImageDecoders.Default(context: ImageDecodingContext(request: request, data: data)))

        #expect(throws: ImageDecodingError.unknown) {
            try decoder.decode(data)
        }
    }

    @Test func thumbnailOfAnOrientedImageIsUpright() throws {
        // The fixture is stored as 480×640 and displayed as 640×480.
        let data = Test.data(name: "right-orientation", extension: "jpeg")
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 320)
        let decoder = try #require(ImageDecoders.Default(context: ImageDecodingContext(request: request, data: data)))

        let image = try decoder.decode(data).image

        #expect(image.sizeInPixels == CGSize(width: 320, height: 240))
        #expect(image.size == CGSize(width: 320, height: 240))
    }

    @Test func thumbnailRequestKeepsTheScaleOfTheRequest() throws {
        var request = Test.request
        request.scale = 2
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)
        let decoder = try #require(ImageDecoders.Default(context: ImageDecodingContext(request: request, data: Test.data)))

        let image = try decoder.decode(Test.data).image

        #expect(image.sizeInPixels == CGSize(width: 100, height: 75))
#if canImport(UIKit)
        #expect(image.scale == 2)
        #expect(image.size == CGSize(width: 50, height: 37.5))
#endif
    }

    // MARK: Orientation

    @Test func finalImageIsDisplayedWithTheOrientationTheDataDeclares() throws {
        let data = Test.data(name: "right-orientation", extension: "jpeg")

        let image = try ImageDecoders.Default().decode(data).image

        #expect(image.size == CGSize(width: 640, height: 480))
#if canImport(UIKit)
        #expect(image.imageOrientation == .right)
#endif
    }

    // MARK: Scale

#if canImport(UIKit)
    @Test func finalImageHasTheScaleOfTheRequest() throws {
        var request = Test.request
        request.scale = 3
        let decoder = try #require(ImageDecoders.Default(context: ImageDecodingContext(request: request, data: Test.data)))

        let image = try decoder.decode(Test.data).image

        #expect(image.scale == 3)
        #expect(image.size == CGSize(width: 640.0 / 3, height: 160))
    }
#else
    @Test func appKitImagesAreSizedInPixelsWhateverTheScale() throws {
        // `NSImage` has no scale: the request's is ignored, and a 72 DPI image
        // is as many points as it is pixels.
        var request = Test.request
        request.scale = 3
        let decoder = try #require(ImageDecoders.Default(context: ImageDecodingContext(request: request, data: Test.data)))

        let image = try decoder.decode(Test.data).image

        #expect(image.size == CGSize(width: 640, height: 480))
    }
#endif

    // MARK: Concurrency

    @Test func concurrentCallsOnOneDecoderAreSerialized() async throws {
        // The decoder is `@unchecked Sendable` behind a lock. Previews racing
        // on one instance must each get a whole image and a number of their
        // own, and leave the count the final image reports consistent.
        // The same chunk every time: the incremental source expects the data
        // to only ever grow, which is what the pipeline guarantees and what
        // tasks racing each other can't.
        let data = Test.data(name: "progressive", extension: "jpeg")
        let chunk = data[0..<20000]
        let decoder = ImageDecoders.Default()

        let previews = await withTaskGroup(of: ImageContainer?.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    decoder.decodePartiallyDownloadedData(chunk)
                }
            }
            return await group.reduce(into: [ImageContainer]()) { if let preview = $1 { $0.append(preview) } }
        }
        let final = try decoder.decode(data)

        // Every call produced a preview and got a number of its own
        let numbers = previews.compactMap { $0.userInfo[.scanNumberKey] as? Int }.sorted()
        #expect(numbers == Array(1...16))
        #expect(previews.allSatisfy { $0.image.sizeInPixels == CGSize(width: 450, height: 300) })
        #expect(final.userInfo[.scanNumberKey] as? Int == 16)
    }
}
