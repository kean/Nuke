// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

#if !os(macOS)
import UIKit
#endif

@Suite(.timeLimit(.minutes(5)))
struct ImageEncoderTests {
    @Test func encodeImage() throws {
        // Given
        let image = Test.image
        let encoder = ImageEncoders.Default()

        // When
        let data = try #require(encoder.encode(image))

        // Then
        #expect(AssetType(data) == .jpeg)
    }

    @Test func encodeImagePNGOpaque() throws {
        // Given
        let image = Test.image(named: "fixture", extension: "png")
        let encoder = ImageEncoders.Default()

        // When
        let data = try #require(encoder.encode(image))

        // Then
#if os(macOS)
        // It seems that on macOS, NSImage created from png has an alpha
        // component regardless of whether the input image has it.
        #expect(AssetType(data) == .png)
#else
        #expect(AssetType(data) == .jpeg)
#endif
    }

    @Test func encodeImagePNGTransparent() throws {
        // Given
        let image = Test.image(named: "swift", extension: "png")
        let encoder = ImageEncoders.Default()

        // When
        let data = try #require(encoder.encode(image))

        // Then
        #expect(AssetType(data) == .png)

        // Then the PNG preserves every pixel, the transparent ones included
        let decoded = try ImageDecoders.Default().decode(data)
        #expect(decoded.image.cgImage?.isOpaque == false)
        #expect(isEqualImages(decoded.image, image))
    }

    @Test func prefersHEIF() throws {
        // Given
        let image = Test.image
        var encoder = ImageEncoders.Default()
        encoder.isHEIFPreferred = true

        // When
        let data = try #require(encoder.encode(image))

        // Then
        #expect(AssetType(data) == AssetType.heic)
        let decoded = try ImageDecoders.Default().decode(data)
        #expect(decoded.image.sizeInPixels == CGSize(width: 640, height: 480))
    }

#if os(iOS) || os(tvOS) || os(visionOS)

    @Test func encodeBlurredImage() throws {
        // Given
        let image = try ImageProcessors.GaussianBlur().processThrowing(Test.image)
        let encoder = ImageEncoders.Default()

        // When
        let data = try #require(encoder.encode(image))

        // Then encoded as JPEG because GaussianBlur preserves the opacity
        // of the input image
        #expect(AssetType(data) == .jpeg)
    }

#endif

    // MARK: - Compression Quality

    @Test func higherCompressionQualityProducesLargerJPEG() throws {
        // GIVEN
        let lowQualityEncoder = ImageEncoders.Default(compressionQuality: 0.1)
        let highQualityEncoder = ImageEncoders.Default(compressionQuality: 0.9)

        // WHEN
        let lowData = try #require(lowQualityEncoder.encode(Test.image))
        let highData = try #require(highQualityEncoder.encode(Test.image))

        // THEN - higher quality produces more bytes
        #expect(highData.count > lowData.count)
    }

    @Test func encodeDecodedRoundTrip() throws {
        // GIVEN - encode an image to JPEG
        let encoder = ImageEncoders.Default(compressionQuality: 0.8)
        let encoded = try #require(encoder.encode(Test.image))
        #expect(AssetType(encoded) == .jpeg)

        // WHEN - decode it back
        let decoder = ImageDecoders.Default()
        let container = try decoder.decode(encoded)

        // THEN - decoded image is valid
        #expect(container.type == .jpeg)
    }

    // MARK: - Misc

    @Test func isOpaqueWithOpaquePNG() {
        let image = Test.image(named: "fixture", extension: "png")
#if os(macOS)
        #expect(!image.cgImage!.isOpaque)
#else
        #expect(image.cgImage!.isOpaque)
#endif
    }

    @Test func isOpaqueWithTransparentPNG() {
        let image = Test.image(named: "swift", extension: "png")
        #expect(!image.cgImage!.isOpaque)
    }

    // MARK: - Defaults

    @Test func defaultEncoderDefaults() {
        let encoder = ImageEncoders.Default()
        #expect(encoder.compressionQuality == 0.8)
        #expect(!encoder.isHEIFPreferred)

        let factory: ImageEncoders.Default = .default()
        #expect(factory.compressionQuality == 0.8)
        #expect(!factory.isHEIFPreferred)
    }

    @Test func defaultEncoderReturnsNilForImageWithoutCGImage() {
        #expect(ImageEncoders.Default().encode(PlatformImage()) == nil)
    }

    // MARK: - Format Choice

    /// HEIF is only preferred over JPEG: an image with an alpha channel is
    /// still encoded as a PNG.
    @Test func heifPreferenceDoesNotApplyToTransparentImages() throws {
        // Given
        var encoder = ImageEncoders.Default()
        encoder.isHEIFPreferred = true

        // When
        let data = try #require(encoder.encode(Test.image(named: "swift", extension: "png")))

        // Then
        #expect(AssetType(data) == .png)
    }

    @Test func opaqueGrayscaleImageIsEncodedAsJPEG() throws {
        // When
        let data = try #require(ImageEncoders.Default().encode(Test.image(named: "grayscale", extension: "jpeg")))

        // Then
        #expect(AssetType(data) == .jpeg)
    }

    // MARK: - Round Trip

    @Test func jpegRoundTripPreservesSizeAndColors() throws {
        // Given a solid color image
        let image = Test.rgbImage(width: 64, height: 48, color: CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))

        // When
        let data = try #require(ImageEncoders.Default(compressionQuality: 1).encode(image))
        let decoded = try ImageDecoders.Default().decode(data)

        // Then
        #expect(decoded.type == .jpeg)
        #expect(decoded.image.sizeInPixels == CGSize(width: 64, height: 48))
        #expect(decoded.image.cgImage?.isOpaque == true)
        let expected = try pixelComponents(of: image, x: 32, y: 24)
        let actual = try pixelComponents(of: decoded.image, x: 32, y: 24)
        #expect(zip(expected, actual).allSatisfy { abs(Int($0) - Int($1)) <= 4 }, "\(actual) vs \(expected)")
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    // MARK: - Orientation

    /// The encoder writes the orientation instead of the pixels turned by it:
    /// an image read back from the disk cache has to face the same way.
    ///
    /// - seealso: https://github.com/kean/Nuke/pull/643
    @Test(arguments: [AssetType.jpeg, .png, .heic])
    func encodingPreservesOrientation(type: AssetType) throws {
        // Given an image with a `.right` orientation: 480x640 pixels displayed
        // as 640x480
        let image = Test.image(named: "right-orientation.jpeg")
        #expect(image.imageOrientation == .right)

        // When
        let data = try #require(ImageEncoders.ImageIO(type: type).encode(image))
        let decoded = try ImageDecoders.Default().decode(data)

        // Then
        #expect(decoded.image.imageOrientation == .right)
        #expect(decoded.image.size == image.size)
        #expect(decoded.image.sizeInPixels == image.sizeInPixels)
    }
#endif
}
