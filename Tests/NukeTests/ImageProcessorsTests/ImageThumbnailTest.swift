// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

@Suite struct ImageThumbnailTest {

    @Test func thatImageIsResized() throws {
        // When
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let output = try #require(options.makeThumbnail(with: Test.data))

        // Then
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
        // Input: 640 × 360
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
        // Input: 640 × 360
        let output = try #require(options.makeThumbnail(with: Test.data(name: "fixture", extension: "png")))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 160, height: 90))
    }

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    @Test func resizeImageWithOrientationRight() throws {
        // Given an image with `right` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px.
        let input = try #require(Test.data(name: "right-orientation", extension: "jpeg"))
        #expect(PlatformImage(data: input)?.imageOrientation == .right)

        // When we resize the image to fit 320x480px frame, we expect the processor
        // to take image orientation into the account and produce a 320x240px.
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 320, height: 1000), unit: .pixels, contentMode: .aspectFit)
        let output = try #require(options.makeThumbnail(with: input))

        // Then the output has orientation of the original image
        #expect(output.imageOrientation == .right)

        //verify size of the image in points and pixels (using scale)
        #expect(output.sizeInPixels == CGSize(width: 320, height: 240))
    }

    @Test func resizeImageWithOrientationUp() throws {
        let input = try #require(Test.data(name: "baseline", extension: "jpeg"))
        #expect(PlatformImage(data: input)?.imageOrientation == .up)

        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 300)
        let output = try #require(options.makeThumbnail(with: input))

        // Then the output has orientation of the original image
        #expect(output.imageOrientation == .up)

        //verify size of the image in points and pixels (using scale)
        #expect(output.sizeInPixels == CGSize(width: 300, height: 200))
    }
#endif
}
