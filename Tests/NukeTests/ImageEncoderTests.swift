// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite struct ImageEncoderTests {
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
    }

    @Test func prefersHEIF() throws {
        // Given
        let image = Test.image
        var encoder = ImageEncoders.Default()
        encoder.isHEIFPreferred = true

        // When
        let data = try #require(encoder.encode(image))

        // Then
        #expect(AssetType(data) == .heic)
    }

#if os(iOS) || os(tvOS) || os(visionOS)

    @Test func encodeCoreImageBackedImage() throws {
        // Given
        let image = try ImageProcessors.GaussianBlur().processThrowing(Test.image)
        let encoder = ImageEncoders.Default()

        // When
        let data = try #require(encoder.encode(image))

        // Then encoded as PNG because GaussianBlur produces
        // images with alpha channel
        #expect(AssetType(data) == .png)
    }

#endif

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
}
