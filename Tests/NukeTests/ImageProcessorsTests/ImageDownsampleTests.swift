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
struct ImageThumbnailTests {

    @Test func thatImageIsResized() throws {
        // WHEN
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let output = try #require(options.makeThumbnail(with: Test.data))

        // THEN
        #expect(output.sizeInPixels == CGSize(width: 400, height: 300))
    }

    @Test func thatImageIsResizedToFill() throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        let output = try #require(options.makeThumbnail(with: Test.data))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 533, height: 400))
    }

    @Test func thatImageIsResizedToFillPNG() throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 180, height: 180), unit: .pixels, contentMode: .aspectFill)

        // When
        // Input: 640 x 360
        let output = try #require(makeThumbnail(data: Test.data(name: "fixture", extension: "png"), options: options))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 320, height: 180))
    }

    @Test func thatImageIsResizedToFit() throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit)

        // When
        let output = try #require(options.makeThumbnail(with: Test.data))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 400, height: 300))
    }

    @Test func thatImageIsResizedToFitPNG() throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 160, height: 160), unit: .pixels, contentMode: .aspectFit)

        // When
        // Input: 640 x 360
        let output = try #require(options.makeThumbnail(with: Test.data(name: "fixture", extension: "png")))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 160, height: 90))
    }

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    @Test func resizeImageWithOrientationRight() throws {
        // Given an image with `right` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px.
        let input = Test.data(name: "right-orientation", extension: "jpeg")
        #expect(PlatformImage(data: input)?.imageOrientation == .right)

        // When we resize the image to fit 320x480px frame, we expect the processor
        // to take image orientation into the account and produce a 320x240px.
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 320, height: 1000), unit: .pixels, contentMode: .aspectFit)
        let output = try #require(options.makeThumbnail(with: input))

        // Then the output orientation is `.up` because `createThumbnailWithTransform`
        // (enabled by default) already bakes the rotation into the pixel data.
        #expect(output.imageOrientation == .up)

        // Verify the bitmap is landscape — the actual pixel buffer must reflect
        // the displayed orientation, not the raw EXIF-rotated storage.
        let cgImage = try #require(output.cgImage)
        #expect(cgImage.width == 320)
        #expect(cgImage.height == 240)
        #expect(cgImage.width > cgImage.height)
    }

    @Test func resizeImageWithOrientationUp() throws {
        let input = Test.data(name: "baseline", extension: "jpeg")
        #expect(PlatformImage(data: input)?.imageOrientation == .up)

        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 300)
        let output = try #require(options.makeThumbnail(with: input))

        // Then the output has orientation of the original image
        #expect(output.imageOrientation == .up)

        //verify size of the image in points and pixels (using scale)
        #expect(output.sizeInPixels == CGSize(width: 300, height: 200))
    }

    /// Verifies that `createThumbnailWithTransform = true` (the default) does
    /// NOT double-apply EXIF orientation. `CGImageSourceCreateThumbnailAtIndex`
    /// already bakes the orientation into the pixel data when the transform
    /// flag is set, so the resulting `UIImage` must use `.up` — not the
    /// original EXIF orientation — to avoid rotating the image twice.
    @Test func thumbnailWithTransformDoesNotDoubleApplyOrientation() throws {
        // Given an image with EXIF orientation `.right` (raw pixels 480×640,
        // displayed as 640×480).
        let input = Test.data(name: "right-orientation", extension: "jpeg")
        #expect(PlatformImage(data: input)?.imageOrientation == .right)

        // When we create a thumbnail with `createThumbnailWithTransform` enabled
        // (the default).
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 480)
        #expect(options.createThumbnailWithTransform == true)
        let output = try #require(options.makeThumbnail(with: input))

        // Then the UIImage orientation must be `.up` because the transform was
        // already applied to the pixel data by ImageIO.
        #expect(output.imageOrientation == .up)

        // The bitmap dimensions should reflect the *displayed* aspect ratio
        // (landscape), not the raw EXIF-rotated dimensions.
        let cgImage = try #require(output.cgImage)
        #expect(cgImage.width > cgImage.height)
    }

    /// Verifies that when `createThumbnailWithTransform` is disabled, the
    /// original EXIF orientation is preserved on the UIImage so that UIKit
    /// can apply it at display time.
    @Test func thumbnailWithoutTransformPreservesOrientation() throws {
        let input = Test.data(name: "right-orientation", extension: "jpeg")
        #expect(PlatformImage(data: input)?.imageOrientation == .right)

        var options = ImageRequest.ThumbnailOptions(maxPixelSize: 480)
        options.createThumbnailWithTransform = false
        let output = try #require(options.makeThumbnail(with: input))

        // Without the transform, orientation should be preserved from EXIF.
        #expect(output.imageOrientation == .right)

        // The bitmap should still be in raw storage layout (portrait).
        let cgImage = try #require(output.cgImage)
        #expect(cgImage.height > cgImage.width)
    }

    @Test func thumbnailWithTransformPreservesScale() throws {
        let input = Test.data(name: "right-orientation", extension: "jpeg")
        let scale: CGFloat = 3.0

        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 480)
        let output = try #require(makeThumbnail(data: input, options: options, scale: scale))

        #expect(output.scale == scale)
    }


#endif

    // MARK: No-op / small-image edge cases

    @Test func thatImageSmallerThanMaxPixelSizeIsNotUpscaled() throws {
        // GIVEN - test image is 640×480; request a thumbnail larger than that
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 2000)

        // WHEN
        let output = try #require(options.makeThumbnail(with: Test.data))

        // THEN - the image is returned at its native size, not upscaled
        let size = output.sizeInPixels
        #expect(size.width <= 640)
        #expect(size.height <= 480)
    }

    @Test func thatInvalidDataReturnsNil() {
        // GIVEN - completely random bytes that don't form a valid image
        let data = Data(repeating: 0xAB, count: 256)
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)

        // WHEN / THEN
        #expect(options.makeThumbnail(with: data) == nil)
    }

    @Test func thatEmptyDataReturnsNil() {
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        #expect(options.makeThumbnail(with: Data()) == nil)
    }
}
