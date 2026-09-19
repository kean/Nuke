// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

// BUG: `ImageProcessors.GaussianBlur` with a radius of ~1544 or more returns a
// corrupted, nearly black image and makes vImage allocate hundreds of
// megabytes to gigabytes of scratch memory.
//
// The three `vImageBoxConvolve_ARGB8888` passes use a kernel of
// `radius * 3 * sqrt(2π) / 4` pixels a side. Once `kernel² × 255` no longer
// fits in an `Int32` – a kernel of 2903 or more, i.e. a radius of ~1544 – the
// sum over a window overflows: the call still returns `kvImageNoError`, but
// the output is garbage (a solid blue 40x40 image comes back as (4, 7, 15)
// instead of (4, 51, 255)), and the scratch buffer vImage asks for jumps from
// ~16 MB to 2.5 GB for a 1000x1000 image (7 GB at radius 10 000, even for a
// 40x40 image). None of the vImage error codes are checked, so the corrupted
// image is returned as a successful result and cached.
//
// Expected: a blur of any radius leaves a solid color unchanged – there is
// nothing to average – and never allocates more than the image needs. A fix
// could clamp the kernel (anything beyond twice the image size is equivalent
// with `kvImageEdgeExtend`) and check the returned `vImage_Error`.
// Actual: the pixels collapse to near-black.
//
// Sources/Nuke/Processing/ImageProcessors+GaussianBlur.swift:55
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
@Suite(.timeLimit(.minutes(5)))
struct GaussianBlurLargeRadiusBugRepro {
    @Test(arguments: [1_600, 2_000])
    func blurringASolidColorWithLargeRadiusLeavesItUnchanged(radius: Int) throws {
        // GIVEN a 40x40 solid blue image
        let image = Test.rgbImage(width: 40, height: 40, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))

        // WHEN
        let output = try #require(ImageProcessors.GaussianBlur(radius: radius).process(image))

        // THEN every pixel keeps its color
        let expected = try rgba(of: image)
        let actual = try rgba(of: output)
        let maxDifference = zip(actual, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(maxDifference <= 1) // Actual for 1600 and 2000: ~240
    }

    private func rgba(of image: PlatformImage) throws -> [UInt8] {
        let cgImage = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let isDrawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return true
        }
        #expect(isDrawn)
        return bytes
    }
}
#endif
