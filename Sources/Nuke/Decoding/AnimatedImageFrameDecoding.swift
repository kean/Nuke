// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

/// Produces the frames of an animated image.
///
/// The frames every animation on screen displays come from an implementation
/// of this protocol – one per animation and size, shared by every player
/// showing it. Image I/O provides them for the formats the system reads, and
/// ``AnimatedImageSource/init(data:)`` picks that one.
///
/// Implement it to produce frames some other way – a codec Image I/O doesn't
/// have, or frames drawn rather than decoded – and hand the implementation to
/// ``AnimatedImageSource/init(data:delays:loopCount:size:makeFrameDecoder:)``,
/// which is also where the frame count and the delays your format declares go.
/// A decoder and the metadata that goes with it are one thing, so they are
/// registered in one place: ``ImageDecoderRegistry``. See
/// <doc:image-decoding>.
///
/// The player asks for one frame at a time, in playback order, and stops
/// asking when its window of frames is full.
///
/// - note: The player is on the main actor and awaits the frames from it.
/// Produce them on an actor or a queue of your own; an implementation isolated
/// to the main actor decodes on it.
public protocol AnimatedImageFrameDecoding: Sendable {
    /// Returns the frame at the given index, or `nil` if it can't be produced.
    ///
    /// A `nil` is remembered: a frame the decoder refuses is not asked for
    /// again, so a truncated animation plays the frames it has instead of
    /// retrying the ones it doesn't.
    func decode(at index: Int) async -> CGImage?
}

/// Decodes the frames of an animated image with Image I/O, one at a time, off
/// the main thread.
///
/// The decoder ``AnimatedImageSource/init(data:)`` gives an animation, and the
/// one every player uses unless the animation was created with a decoder of
/// its own.
///
/// An actor because `CGImageSource` is not safe to use concurrently, and
/// because decoding in playback order is what the buffer wants anyway.
actor AnimatedImageFrameDecoder: AnimatedImageFrameDecoding {
    private let animation: AnimatedImageSource
    private let maxPixelSize: CGFloat?

    /// Created on the first decode: indexing the container is not work for the
    /// main actor, which is where the decoder itself is made.
    private lazy var source: CGImageSource? = animation.makeImageSource()

    /// - parameter maxPixelSize: The longest side, in pixels, the decoded
    /// frames may have. Larger frames are scaled down. `nil` – the size the
    /// animation is stored at – by default.
    init(source: AnimatedImageSource, maxPixelSize: CGFloat? = nil) {
        self.animation = source
        self.maxPixelSize = maxPixelSize
    }

    /// Decodes and draws the frame at the given index.
    func decode(at index: Int) -> CGImage? {
        guard let source, !Task.isCancelled else {
            return nil
        }
        // Image I/O composes the frame onto the canvas, applying the disposal
        // and blend modes of GIF and APNG.
        guard let image = CGImageSourceCreateImageAtIndex(source, index, AnimatedImageSource.imageSourceOptions) else {
            return nil
        }
        // The image is lazy: it decompresses the first time something draws
        // it, which would otherwise be the main thread. Drawing it here also
        // produces a bitmap in the format the compositor wants.
        return draw(image) ?? image
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
