// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

// BUG (regression): `ImageProcessors.GaussianBlur` converts wide-gamut images
// to device RGB, clipping Display P3 colors to sRGB.
//
// The fix for the grayscale crash (9e3af8e6, "Fix GaussianBlur crash on
// grayscale images", #880) forces `CGColorSpaceCreateDeviceRGB()` for both
// scratch contexts of every image. It only had to replace the color spaces
// vImage's ARGB8888 layout can't take (grayscale, CMYK, indexed): an RGB color
// space such as Display P3 has the same 32-bit layout and could be kept.
// Before that commit, `CGContext.make(self, size:alphaInfo:)` used the image's
// own color space and a P3 image stayed P3.
//
// Expected: the blurred image keeps its wide-gamut color space, as the output
// of `Resize`, `Circle`, `RoundedCorners`, and decompression does – each of
// them has an `extendedColorSpaceSupport` test ("Add support for extended color
// spaces", "Decompression and resizing now preserve image color space").
// Actual: `kCGColorSpaceDeviceRGB`, on both macOS and iOS.
//
// Sources/Nuke/Processing/ImageProcessors+GaussianBlur.swift:65
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
@Suite(.timeLimit(.minutes(5)))
struct GaussianBlurWideGamutBugRepro {
    @Test func blurPreservesWideGamutColorSpace() throws {
        // GIVEN a Display P3 image
        let input = Test.image(named: "image-p3", extension: "jpg")
        #expect(try #require(input.cgImage?.colorSpace).isWideGamutRGB)

        // WHEN
        let output = try #require(ImageProcessors.GaussianBlur(radius: 4).process(input))

        // THEN
        let colorSpace = try #require(output.cgImage?.colorSpace)
        #expect(colorSpace.isWideGamutRGB) // Actual: false (kCGColorSpaceDeviceRGB)
    }
}
#endif
