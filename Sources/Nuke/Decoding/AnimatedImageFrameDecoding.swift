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

    /// The longest side, in pixels, a frame may have: the limit the player
    /// asked for, or the size the animation is stored at.
    ///
    /// Always a number, never "no limit". Image I/O answers a thumbnail
    /// request that carries no `kCGImageSourceThumbnailMaxPixelSize` with a
    /// *lazy* image – it ignores `kCGImageSourceShouldCacheImmediately` – and a
    /// frame that decompresses the first time it is drawn decompresses on the
    /// main thread, which is the one thing this decoder exists to avoid.
    ///
    /// `nil` only when there is no number to ask for: an animation whose
    /// canvas Image I/O reported nothing for, and no limit from the player.
    /// Those frames are decoded whole and drawn.
    private let maxPixelSize: Int?

    /// Created on the first decode: indexing the container is not work for the
    /// main actor, which is where the decoder itself is made.
    private lazy var source: CGImageSource? = animation.makeImageSource()

    /// What every frame is asked for with. Built once, on the first decode:
    /// `CFDictionary` isn't `Sendable`, so it is made where it is used.
    private lazy var options: CFDictionary = {
        var options: [CFString: Any] = [
            // Compose the frame rather than lift whatever preview the
            // container carries.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Decompress it here, on this actor. Left to Image I/O, the bitmap
            // is produced the first time something draws the frame, which is
            // the main thread.
            kCGImageSourceShouldCacheImmediately: true,
            // The frame buffer in the player is the only frame cache there
            // should be – see ``AnimatedImageSource/imageSourceOptions``.
            kCGImageSourceShouldCache: false
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        return options as CFDictionary
    }()

    /// - parameter maxPixelSize: The longest side, in pixels, the decoded
    /// frames may have. Larger frames are scaled down. `nil` – the size the
    /// animation is stored at – by default.
    init(source: AnimatedImageSource, maxPixelSize: CGFloat? = nil) {
        self.animation = source
        // Image I/O never enlarges a frame, so the size the animation is
        // stored at is the limit that means "decode it whole".
        let limit = maxPixelSize ?? max(source.size.width, source.size.height)
        self.maxPixelSize = limit.rounded().pixelDimension
    }

    /// Decodes the frame at the given index.
    func decode(at index: Int) -> CGImage? {
        guard let source, !Task.isCancelled else {
            return nil
        }
        // Image I/O composes the frame onto the canvas, applying the disposal
        // and blend modes of GIF and APNG, scales it to the size the player
        // asked for, and hands back a bitmap that is already decompressed –
        // the call WebKit makes for every frame it decodes off the main
        // thread. Scaling as it decodes is what HEICS and AVIF are faster
        // for; GIF and APNG inflate the whole canvas either way.
        if maxPixelSize != nil, let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options) {
            return frame
        }
        return decodeByDrawing(at: index, in: source)
    }

    /// Decodes the frame the way a renderer that can't scale as it decodes has
    /// to: whole, and then drawn.
    ///
    /// The fallback for a limit no thumbnail can meet – which the codecs
    /// answer differently, HEICS returning nothing where GIF returns a single
    /// pixel – and for the animation that declares no canvas to decode within.
    private func decodeByDrawing(at index: Int, in source: CGImageSource) -> CGImage? {
        guard let image = CGImageSourceCreateImageAtIndex(source, index, AnimatedImageSource.imageSourceOptions) else {
            return nil
        }
        let size = targetSize(for: image)
        // The image is lazy: it decompresses the first time something draws
        // it, which would otherwise be the main thread. The draw is also what
        // applies the limit Image I/O declined to.
        guard let context = CGContext.make(image, size: size) else {
            return image
        }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
    }

    /// The size to draw the frame at: its own, no longer on its longest side
    /// than ``maxPixelSize``.
    private func targetSize(for image: CGImage) -> CGSize {
        guard let maxPixelSize else {
            return image.size
        }
        let limit = CGSize(width: maxPixelSize, height: maxPixelSize)
        // Fitting inside a square scales by the longest side, and a frame is
        // never enlarged to reach the limit.
        let scale = min(1, image.size.getScale(targetSize: limit, contentMode: .aspectFit))
        return image.size.scaled(by: scale).rounded()
    }
}
