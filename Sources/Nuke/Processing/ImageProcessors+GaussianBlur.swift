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
        /// - parameter radius: `8` by default.
        public init(radius: Int = 8) {
            self.radius = radius
        }

        /// Applies a Gaussian blur to the image.
        public func process(_ image: PlatformImage) -> PlatformImage? {
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
    func blurred(radius: Int) -> CGImage? {
        let inputRadius = max(Double(radius), 2.0)
        let pi2 = 2.0 * Double.pi
        var kernelSize = UInt32(floor(inputRadius * 3.0 * sqrt(pi2) / 4.0 + 0.5))
        if kernelSize % 2 == 0 { kernelSize += 1 }

        let size = self.size
        guard let inputCtx = CGContext.make(self, size: size, alphaInfo: .premultipliedLast),
              let outputCtx = CGContext.make(self, size: size, alphaInfo: .premultipliedLast) else {
            return nil
        }
        inputCtx.draw(self, in: CGRect(origin: .zero, size: size))

        var inBuffer = vImage_Buffer(data: inputCtx.data, height: vImagePixelCount(inputCtx.height), width: vImagePixelCount(inputCtx.width), rowBytes: inputCtx.bytesPerRow)
        var outBuffer = vImage_Buffer(data: outputCtx.data, height: vImagePixelCount(outputCtx.height), width: vImagePixelCount(outputCtx.width), rowBytes: outputCtx.bytesPerRow)

        // Three box-blur passes approximate a Gaussian blur. kvImageEdgeExtend
        // extends edge pixels to prevent border artifacts (see #308).
        let flags = vImage_Flags(kvImageEdgeExtend)
        vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, nil, 0, 0, kernelSize, kernelSize, nil, flags)
        vImageBoxConvolve_ARGB8888(&outBuffer, &inBuffer, nil, 0, 0, kernelSize, kernelSize, nil, flags)
        vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, nil, 0, 0, kernelSize, kernelSize, nil, flags)

        return outputCtx.makeImage()
    }
}

#endif
