// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

/// Produces the frames of an animated image.
///
/// ``AnimatedImageFrameDecoder`` is the one implementation that ships; the
/// tests substitute one that releases a frame at a time.
protocol AnimatedImageFrameDecoding: Sendable {
    func decode(at index: Int) async -> AnimatedImageFrameDecoder.Frame?
}

/// Decodes the frames of an animated image, one at a time, off the main thread.
///
/// An actor because `CGImageSource` is not safe to use concurrently, and
/// because decoding in playback order is what the buffer wants anyway.
actor AnimatedImageFrameDecoder: AnimatedImageFrameDecoding {
    private let animation: AnimatedImageSource
    private let maxPixelSize: CGFloat?

    /// Created on the first decode: indexing the container is not work for the
    /// main actor, which is where the decoder itself is made.
    private lazy var source: CGImageSource? = animation.makeImageSource()

    /// A decoded frame and what it cost to produce.
    struct Frame: @unchecked Sendable {
        /// `CGImage` is immutable but predates `Sendable`, hence the unchecked
        /// conformance.
        let image: CGImage
        /// How long the decode took, in seconds.
        let duration: TimeInterval
        /// The size of the bitmap in bytes.
        let byteCount: Int
    }

    /// - parameter maxPixelSize: The longest side, in pixels, the decoded
    /// frames may have. Larger frames are scaled down.
    init(source: AnimatedImageSource, maxPixelSize: CGFloat?) {
        self.animation = source
        self.maxPixelSize = maxPixelSize
    }

    /// Decodes and draws the frame at the given index.
    func decode(at index: Int) -> Frame? {
        guard let source, !Task.isCancelled else {
            return nil
        }
        let start = monotonicTime()
        // Image I/O composes the frame onto the canvas, applying the disposal
        // and blend modes of GIF and APNG.
        guard let image = CGImageSourceCreateImageAtIndex(source, index, AnimatedImageSource.imageSourceOptions) else {
            return nil
        }
        // The image is lazy: it decompresses the first time something draws
        // it, which would otherwise be the main thread. Drawing it here also
        // produces a bitmap in the format the compositor wants.
        let prepared = draw(image) ?? image
        return Frame(
            image: prepared,
            duration: monotonicTime() - start,
            byteCount: prepared.bytesPerRow * prepared.height
        )
    }

    private func draw(_ image: CGImage) -> CGImage? {
        let size = targetSize(for: image)
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        guard let context = makeContext(size: size, isOpaque: image.isOpaque, colorSpace: image.colorSpace) else {
            return nil
        }
        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height)))
        return context.makeImage()
    }

    private func targetSize(for image: CGImage) -> (width: Int, height: Int) {
        guard let maxPixelSize, maxPixelSize > 0 else {
            return (image.width, image.height)
        }
        let longestSide = CGFloat(max(image.width, image.height))
        guard longestSide > maxPixelSize else {
            return (image.width, image.height)
        }
        let scale = maxPixelSize / longestSide
        return (max(1, Int((CGFloat(image.width) * scale).rounded())),
                max(1, Int((CGFloat(image.height) * scale).rounded())))
    }

    private func makeContext(size: (width: Int, height: Int), isOpaque: Bool, colorSpace: CGColorSpace?) -> CGContext? {
        // BGRA, the layout Core Animation uploads without converting.
        let alphaInfo: CGImageAlphaInfo = isOpaque ? .noneSkipFirst : .premultipliedFirst
        let bitmapInfo = alphaInfo.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        func makeContext(_ colorSpace: CGColorSpace) -> CGContext? {
            CGContext(
                data: nil,
                width: size.width,
                height: size.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        }
        // Keep a wide-gamut image wide when the context accepts its color
        // space; fall back to sRGB rather than failing to draw.
        if let colorSpace, colorSpace.model == .rgb, let context = makeContext(colorSpace) {
            return context
        }
        return makeContext(CGColorSpaceCreateDeviceRGB())
    }
}

extension CGImage {
    var isOpaque: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: true
        default: false
        }
    }
}
