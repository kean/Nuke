// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if !os(macOS)
import UIKit
#endif

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

    // MARK: - Flag

    @Test(arguments: [true, false])
    func decompressionFlagIsStoredOnTheImage(isNeeded: Bool) {
        // GIVEN
        let image = Test.rgbImage(width: 4, height: 4)

        // WHEN
        ImageDecompression.setDecompressionNeeded(isNeeded, for: image)

        // THEN
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == isNeeded)
        #expect(ImageDecompression.isDecompressionNeeded(for: ImageResponse(container: ImageContainer(image: image), request: Test.request)) == isNeeded)
    }

    @Test func responseWithUntaggedImageDoesNotNeedDecompression() {
        // GIVEN
        let response = ImageResponse(container: ImageContainer(image: Test.rgbImage(width: 4, height: 4)), request: Test.request)

        // THEN
        #expect(!ImageDecompression.isDecompressionNeeded(for: response))
    }

    @Test func flagIsSetPerImage() {
        // GIVEN
        let tagged = Test.rgbImage(width: 4, height: 4)
        let other = Test.rgbImage(width: 4, height: 4)

        // WHEN
        ImageDecompression.setDecompressionNeeded(true, for: tagged)

        // THEN
        #expect(ImageDecompression.isDecompressionNeeded(for: other) == nil)
    }

    // MARK: - Output

    @Test func decompressionReturnsTheInputWhenItCannotBeDrawn() {
        // GIVEN an image with no bitmap
        let input = PlatformImage()

        // WHEN
        let output = ImageDecompression.decompress(image: input)

        // THEN the original is displayed rather than nothing
        #expect(output === input)
    }

    @Test func decompressionPreservesSizeAndOpacity() throws {
        // GIVEN an opaque image
        let input = Test.image

        // WHEN
        let output = ImageDecompression.decompress(image: input)

        // THEN it keeps its size, and it isn't given an alpha channel that
        // would make `ImageEncoders.Default` store it as a PNG
        #expect(output !== input)
        #expect(output.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(output.cgImage?.isOpaque == true)
    }

    @Test func decompressionPreservesTransparency() throws {
        // GIVEN an image with an alpha channel
        let input = Test.image(named: "swift", extension: "png")
        #expect(input.cgImage?.isOpaque == false)

        // WHEN
        let output = ImageDecompression.decompress(image: input)

        // THEN
        #expect(output.sizeInPixels == input.sizeInPixels)
        #expect(output.cgImage?.isOpaque == false)
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test(arguments: [false, true])
    func decompressionPreservesScaleAndOrientation(isUsingPrepareForDisplay: Bool) throws {
        // GIVEN a @3x image rotated by the orientation
        let input = UIImage(cgImage: try #require(Test.image.cgImage), scale: 3, orientation: .right)

        // WHEN
        let output = ImageDecompression.decompress(image: input, isUsingPrepareForDisplay: isUsingPrepareForDisplay)

        // THEN
        #expect(output.scale == 3)
        #expect(output.imageOrientation == .right)
        #expect(output.size == input.size)
    }

    @Test func prepareForDisplayFallsBackToTheInput() {
        // GIVEN an image `preparingForDisplay()` can't prepare
        let input = UIImage()

        // WHEN
        let output = ImageDecompression.decompress(image: input, isUsingPrepareForDisplay: true)

        // THEN
        #expect(output === input)
    }
#endif
}
