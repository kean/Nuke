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
/// showing it. ``AnimatedImageFrameDecoder``, which draws them with Image I/O,
/// is the one that ships.
///
/// Implement it to produce frames some other way – a codec Image I/O doesn't
/// have, or frames drawn rather than decoded – and register the implementation
/// with ``AnimatedImageFrameDecoderRegistry``:
///
/// ```swift
/// AnimatedImageFrameDecoderRegistry.shared.register { context in
///     WebPFrameDecoder(data: context.source.data) // `nil` to pass
/// }
/// ```
///
/// The player asks for one frame at a time, in playback order, and stops
/// asking when its window of frames is full – see <doc:AnimatedImages>.
///
/// - important: The container is still parsed by Image I/O:
/// ``Nuke/AnimatedImageSource`` is what tells the player how many frames there
/// are and how long each one is shown, and there is no animation to play at all
/// for data Image I/O can't read. A decoder of your own answers "what does
/// frame *n* look like", not "what is in this file".
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
    func decode(at index: Int) async -> AnimatedImageFrame?
}

/// A decoded frame of an animation, and what it cost to produce.
public struct AnimatedImageFrame: @unchecked Sendable {
    /// The bitmap to display.
    ///
    /// - note: `CGImage` is immutable but predates `Sendable`, hence the
    /// unchecked conformance.
    public let image: CGImage

    /// The memory the bitmap occupies, in bytes: what the frame costs against
    /// ``AnimatedImageFramePool``.
    public let byteCount: Int

    /// How long the frame took to produce, in seconds. Reported by
    /// ``AnimatedImagePlayer/Diagnostics/lastDecodeDuration`` and the averages
    /// beside it.
    public let decodeDuration: TimeInterval

    /// Creates a frame.
    ///
    /// - parameter byteCount: The memory the bitmap occupies. Computed from
    /// the image by default.
    /// - parameter decodeDuration: How long the frame took to produce, in
    /// seconds. `0` – not measured – by default.
    public init(image: CGImage, byteCount: Int? = nil, decodeDuration: TimeInterval = 0) {
        self.image = image
        self.byteCount = byteCount ?? image.bytesPerRow * image.height
        self.decodeDuration = decodeDuration
    }
}

/// Decodes the frames of an animated image with Image I/O, one at a time, off
/// the main thread.
///
/// The decoder every player uses unless ``AnimatedImageFrameDecoderRegistry``
/// answers with another one. Wrap it to post-process what Image I/O produces
/// without giving up its disposal and blend handling.
///
/// An actor because `CGImageSource` is not safe to use concurrently, and
/// because decoding in playback order is what the buffer wants anyway.
public actor AnimatedImageFrameDecoder: AnimatedImageFrameDecoding {
    private let animation: AnimatedImageSource
    private let maxPixelSize: CGFloat?

    /// Created on the first decode: indexing the container is not work for the
    /// main actor, which is where the decoder itself is made.
    private lazy var source: CGImageSource? = animation.makeImageSource()

    /// - parameter maxPixelSize: The longest side, in pixels, the decoded
    /// frames may have. Larger frames are scaled down. `nil` – the size the
    /// animation is stored at – by default.
    public init(source: AnimatedImageSource, maxPixelSize: CGFloat? = nil) {
        self.animation = source
        self.maxPixelSize = maxPixelSize
    }

    /// Decodes and draws the frame at the given index.
    public func decode(at index: Int) -> AnimatedImageFrame? {
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
        return AnimatedImageFrame(image: prepared, decodeDuration: monotonicTime() - start)
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
