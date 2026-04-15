// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImageDecompressionTests {

    @Test func decompressionNotNeededFlagSet() throws {
        // Given
        let input = Test.image
        ImageDecompression.setDecompressionNeeded(true, for: input)

        // When
        let output = ImageDecompression.decompress(image: input)

        // Then
        #expect(ImageDecompression.isDecompressionNeeded(for: output) != true)
    }

    @Test func grayscalePreserved() throws {
        // Given
        let input = Test.image(named: "grayscale", extension: "jpeg")
        #expect(input.cgImage?.bitsPerComponent == 8)
        #expect(input.cgImage?.bitsPerPixel == 8)

        // When
        let output = ImageDecompression.decompress(image: input, isUsingPrepareForDisplay: true)

        // Then
        #expect(output.cgImage?.bitsPerPixel == 8)
        #expect(output.cgImage?.bitsPerComponent == 8)
    }

    @Test func isDecompressionNeededReturnsFalseForUntaggedImage() {
        // GIVEN a freshly created image with no decompression tag
        let image = Test.image

        // THEN flag is unset (nil), treated as not needing decompression
        #expect(ImageDecompression.isDecompressionNeeded(for: image) != true)
    }

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    @Test func wideGamutColorSpaceIsPreservedAfterDecompression() throws {
        // GIVEN a wide-gamut (P3) image
        let input = Test.image(named: "image-p3", extension: "jpg")
        let inputColorSpace = try #require(input.cgImage?.colorSpace)
        #expect(inputColorSpace.isWideGamutRGB)

        // WHEN decompressed
        let output = ImageDecompression.decompress(image: input)

        // THEN the wide-gamut color space is preserved
        let outputColorSpace = try #require(output.cgImage?.colorSpace)
        #expect(outputColorSpace.isWideGamutRGB)
    }
#endif
}
