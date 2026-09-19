// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

// BUG (macOS): a thumbnail of an EXIF-rotated image, requested with a target
// size and content mode (`ThumbnailOptions(size:unit:contentMode:)`), is sized
// against the stored pixels rather than the image as displayed, and comes out
// too large.
//
// `getMaxPixelSize(for:options:)` works out `kCGImageSourceThumbnailMaxPixelSize`
// from the stored `PixelWidth`/`PixelHeight` and turns the target for the
// orientation only under `#if canImport(UIKit)`. With
// `createThumbnailWithTransform`, which is on by default, Image I/O turns the
// thumbnail upright on every platform, including macOS. So on macOS the fit or
// fill is worked out against a portrait 480x640 frame, while the thumbnail it
// returns is the landscape 640x480 image.
//
// Expected (and what iOS returns): a 640x480 image, stored as 480x640 with
// `.right`, fitted into 320x1000 is 320x240, and filled into 400x100 is
// 400x300.
// Actual on macOS: 427x320 (wider than the 320 px asked for) and 533x400.
//
// Sources/Nuke/Internal/Graphics.swift:541-543
@Suite(.timeLimit(.minutes(5)))
struct ThumbnailOrientationBugRepro {
    @Test func fitThumbnailOfRotatedImage() throws {
        // GIVEN a JPEG stored as 480x640 px with an EXIF orientation of
        // `.right`, i.e. a 640x480 image when displayed
        let data = Test.data(name: "right-orientation", extension: "jpeg")
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 320, height: 1000), unit: .pixels, contentMode: .aspectFit)

        // WHEN
        let output = try #require(options.makeThumbnail(with: data))

        // THEN the upright thumbnail fits into the 320 px wide target
        let cgImage = try #require(output.cgImage)
        #expect(cgImage.width == 320) // Actual on macOS: 427
        #expect(cgImage.height == 240) // Actual on macOS: 320
    }

    @Test func fillThumbnailOfRotatedImage() throws {
        // GIVEN
        let data = Test.data(name: "right-orientation", extension: "jpeg")
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 100), unit: .pixels, contentMode: .aspectFill)

        // WHEN
        let output = try #require(options.makeThumbnail(with: data))

        // THEN the upright thumbnail just fills the 400x100 target
        let cgImage = try #require(output.cgImage)
        #expect(cgImage.width == 400) // Actual on macOS: 533
        #expect(cgImage.height == 300) // Actual on macOS: 400
    }
}
