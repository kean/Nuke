// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

import Foundation
import Accelerate

#if !os(macOS)
import UIKit
#else
import AppKit
#endif

extension ImageProcessors {
    /// Blurs an image using a simulated Gaussian blur.
    ///
    /// Uses the Accelerate framework (`vImageBoxConvolve`) with edge extension
    /// to avoid gray border artifacts.
    public struct GaussianBlur: ImageProcessing, Hashable, CustomStringConvertible {
        private let radius: Int

        /// Initializes the receiver with a blur radius.
        ///
        /// - parameter radius: `8` by default. A radius of `0` – or any negative
        /// value, which is clamped to `0` – makes the processor an identity
        /// transform that returns the image unchanged.
        public init(radius: Int = 8) {
            self.radius = max(0, radius)
        }

        /// Applies a Gaussian blur to the image.
        public func process(_ image: PlatformImage) -> PlatformImage? {
            guard radius > 0 else { return image }
            guard let cgImage = image.cgImage else { return nil }
            guard let output = cgImage.blurred(radius: radius) else { return nil }
            return PlatformImage.make(cgImage: output, source: image)
        }

        public var identifier: String {
            "com.github.kean/nuke/gaussian_blur?radius=\(radius)"
        }

        public var description: String {
            "GaussianBlur(radius: \(radius))"
        }
    }
}

private extension CGImage {
    /// Applies a Gaussian blur approximation using three box-blur passes (SVG spec).
    ///
    /// - parameter radius: Must be greater than `0`.
    func blurred(radius: Int) -> CGImage? {
        let inputRadius = Double(radius)
        let pi2 = 2.0 * Double.pi
        var kernelSize = UInt32(floor(inputRadius * 3.0 * sqrt(pi2) / 4.0 + 0.5))
        // vImage sums the window in an `Int32`: with a kernel of 2903 or more
        // (a radius of ~1544) `kernel² × 255` overflows and it returns garbage
        // as a success, while asking for gigabytes of scratch memory. 2901 is
        // the largest odd kernel that keeps the sum in range.
        kernelSize = min(kernelSize, 2901)
        if kernelSize % 2 == 0 { kernelSize += 1 }

        let size = self.size
        // vImageBoxConvolve_ARGB8888 needs a 32-bit ARGB layout. A grayscale
        // source yields a 16-bit gray+alpha context (half the row stride vImage
        // expects), so switch to RGB for the scratch contexts unless the image
        // is already RGB: that keeps wide-gamut images (Display P3) in their
        // color space instead of clipping them to sRGB. `.noneSkipLast` keeps
        // the same 32-bit layout for opaque images without tagging the output
        // with alpha, which would make `ImageEncoders.Default` pick PNG.
        let alphaInfo: CGImageAlphaInfo = isOpaque ? .noneSkipLast : .premultipliedLast
        func makeContexts(_ colorSpace: CGColorSpace) -> (input: CGContext, output: CGContext)? {
            guard let input = CGContext.make(self, size: size, alphaInfo: alphaInfo, colorSpace: colorSpace),
                  let output = CGContext.make(self, size: size, alphaInfo: alphaInfo, colorSpace: colorSpace) else {
                return nil
            }
            return (input, output)
        }
        let rgbColorSpace = colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        // Core Graphics rejects some RGB spaces at 8 bits per component, e.g.
        // the extended-range ones, so fall back to device RGB for those.
        guard let (inputCtx, outputCtx) = rgbColorSpace.flatMap(makeContexts) ?? makeContexts(CGColorSpaceCreateDeviceRGB()) else {
            return nil
        }
        inputCtx.draw(self, in: CGRect(origin: .zero, size: size))

        var inBuffer = vImage_Buffer(data: inputCtx.data, height: vImagePixelCount(inputCtx.height), width: vImagePixelCount(inputCtx.width), rowBytes: inputCtx.bytesPerRow)
        var outBuffer = vImage_Buffer(data: outputCtx.data, height: vImagePixelCount(outputCtx.height), width: vImagePixelCount(outputCtx.width), rowBytes: outputCtx.bytesPerRow)

        // Three box-blur passes approximate a Gaussian blur. kvImageEdgeExtend
        // extends edge pixels to prevent border artifacts (see #308).
        let flags = vImage_Flags(kvImageEdgeExtend)
        guard vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, nil, 0, 0, kernelSize, kernelSize, nil, flags) == kvImageNoError,
              vImageBoxConvolve_ARGB8888(&outBuffer, &inBuffer, nil, 0, 0, kernelSize, kernelSize, nil, flags) == kvImageNoError,
              vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, nil, 0, 0, kernelSize, kernelSize, nil, flags) == kvImageNoError else {
            return nil
        }

        return outputCtx.makeImage()
    }
}

#endif
