// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

/// An animated image – a GIF, an APNG, an animated WebP, HEIC, or AVIF –
/// described by the metadata parsed from its encoded data.
///
/// The type holds no decoded frames. Creating it reads the frame count, the
/// per-frame delays, the loop count, and the canvas size, all of which Image I/O
/// answers from the container without decompressing a pixel. The frames are
/// decoded later, on demand, by `AnimatedImagePlayer` in `NukeUI` – or by a
/// renderer of your own, built on ``makeFrameDecoder(maxPixelSize:)``.
///
/// ``init(data:)`` describes the animation with Image I/O and decodes it with
/// Image I/O. For a format Image I/O can't read, describe the animation
/// yourself and pass in what produces its frames – see
/// ``init(data:delays:loopCount:size:makeFrameDecoder:)``. Either way, the
/// place to attach the result is ``ImageContainer/animation``, from a decoder
/// registered with ``ImageDecoderRegistry``.
///
/// The pipeline parses the images it recognizes as animated while it decodes
/// them and attaches the result to ``ImageContainer/animation``, so a non-`nil`
/// value there answers "can this be played?":
///
/// ```swift
/// guard let animation = response.container.animation else {
///     return // Not an animated image – display `container.image` as usual
/// }
/// print(animation.frameCount, animation.duration, animation.loopCount)
/// ```
///
/// - note: The type is a class because parsing isn't free – the frame count of
/// a GIF alone requires a scan of the container – and because the views compare
/// animations by identity to decide whether to restart playback.
public final class AnimatedImageSource: Sendable {
    /// The encoded image data: the same buffer ``ImageContainer/data`` holds,
    /// shared with it rather than copied.
    public let data: Data

    /// The number of frames. Always greater than one.
    public let frameCount: Int

    /// The display duration of every frame, in seconds.
    ///
    /// The values are the ones stored in the container, with two corrections
    /// every browser applies: a missing or non-positive delay becomes
    /// ``defaultDelay``, and so does a delay below ``minimumDelay``, which old
    /// authoring tools wrote to mean "as fast as possible".
    public let delays: [TimeInterval]

    /// The duration of a single loop: the sum of ``delays``.
    public let duration: TimeInterval

    /// The number of times the animation repeats. `0` means "forever", which is
    /// what the vast majority of animated images specify.
    ///
    /// A GIF with no Netscape application extension declares no loop count at
    /// all, and this is `1` for it: the file asks to be played once, which is
    /// how browsers read it.
    public let loopCount: Int

    /// The size of the animation canvas, in pixels.
    public let size: CGSize

    /// What produces the frames, when it isn't Image I/O.
    ///
    /// Not the decoder itself: a decoder holds the container it reads from,
    /// which costs about what a frame does, and an animation sitting in
    /// ``ImageCache`` with nothing playing it must not hold one. The players
    /// make one when the first of them needs a frame and drop it with the
    /// last.
    private let customFrameDecoder: (@Sendable (CGFloat?) -> any AnimatedImageFrameDecoding)?

    /// The average number of frames per second across one loop.
    public var nominalFrameRate: Double {
        duration > 0 ? Double(frameCount) / duration : 0
    }

    /// The number of bytes one decoded frame occupies in memory.
    ///
    /// Frames are decoded into bitmaps with 8 bits per component, so the figure
    /// depends only on the canvas size, not on how well the image compresses.
    public var bytesPerFrame: Int {
        Int(size.width) * Int(size.height) * 4
    }

    /// The delay used for frames that don't declare a usable one: `0.1`.
    public static let defaultDelay: TimeInterval = 0.1

    /// Delays below this value are replaced with ``defaultDelay``: `0.011`.
    ///
    /// The threshold is the one browsers use: a GIF that asks for a 0 ms or a
    /// 10 ms delay was written by a tool that meant "as fast as the renderer
    /// can go", and playing it at 100 fps burns CPU to produce a flicker.
    public static let minimumDelay: TimeInterval = 0.011

    /// Creates a source from the encoded image data.
    ///
    /// The pipeline does this for you on the decoding queue – see
    /// ``ImageContainer/animation``. Reach for this initializer for data that
    /// didn't come from the pipeline, and keep it off the main thread for a
    /// large animation.
    ///
    /// - returns: `nil` if the data isn't an image, or if the image has a
    /// single frame.
    public init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, AnimatedImageSource.imageSourceOptions) else {
            return nil
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            return nil
        }
        // An unrecognized container still animates: only the delays are
        // missing, and the default one is the browser behavior.
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
        let format = AnimatedImageFormat(properties: properties)
        self.data = data
        self.frameCount = frameCount
        self.delays = (0..<frameCount).map {
            format?.delay(in: source, at: $0) ?? AnimatedImageSource.defaultDelay
        }
        self.duration = delays.reduce(0, +)
        self.loopCount = format?.loopCount(in: properties) ?? 0
        self.size = AnimatedImageSource.size(of: source)
        self.customFrameDecoder = nil
    }

    /// Creates a source for an animation described by the caller.
    ///
    /// The way to play a format Image I/O can't read: parse the container in a
    /// decoder of your own, describe what you found here, and hand over what
    /// produces the frames. Everything downstream is unchanged – the frames
    /// are windowed, shared between the views showing the animation, and
    /// counted against the frame pool exactly as Image I/O's are.
    ///
    /// ```swift
    /// let webp = try WebPImage(data: data)
    /// container.animation = AnimatedImageSource(
    ///     data: data,
    ///     delays: webp.delays,
    ///     loopCount: webp.loopCount,
    ///     size: webp.size,
    ///     makeFrameDecoder: { WebPFrameDecoder(webp, maxPixelSize: $0) }
    /// )
    /// ```
    ///
    /// - parameter data: The encoded image. Not read by this initializer – the
    /// decoder is what reads it – and published as ``data`` for whatever else
    /// needs the bytes.
    /// - parameter delays: The display duration of every frame, in seconds,
    /// which is also what says how many frames there are. Corrected the way
    /// ``delays`` describes.
    /// - parameter loopCount: The number of times the animation repeats, `0`
    /// for "forever".
    /// - parameter size: The size of the animation canvas, in pixels.
    /// - parameter makeFrameDecoder: Returns what produces the frames, no
    /// larger than the given size in pixels. Called once per animation and
    /// size, off the main actor's critical path but on the main actor, so make
    /// it cheap and leave the container indexing to the decoder itself.
    ///
    /// - returns: `nil` if the animation has a single frame or an empty
    /// canvas, neither of which is something to play.
    public init?(
        data: Data,
        delays: [TimeInterval],
        loopCount: Int = 0,
        size: CGSize,
        makeFrameDecoder: @escaping @Sendable (_ maxPixelSize: CGFloat?) -> any AnimatedImageFrameDecoding
    ) {
        guard delays.count > 1, size.width > 0, size.height > 0 else {
            return nil
        }
        self.data = data
        self.frameCount = delays.count
        self.delays = delays.map(AnimatedImageSource.correctedDelay)
        self.duration = self.delays.reduce(0, +)
        self.loopCount = max(0, loopCount)
        self.size = size
        self.customFrameDecoder = makeFrameDecoder
    }

    /// Returns what produces the frames of this animation, no larger than the
    /// given size in pixels.
    ///
    /// The players call it when the first of them needs a frame; call it to
    /// decode the frames yourself, from a renderer of your own.
    ///
    /// - parameter maxPixelSize: The longest side, in pixels, the frames may
    /// have. Larger frames are scaled down. `nil` – the size the animation is
    /// stored at – by default.
    public func makeFrameDecoder(maxPixelSize: CGFloat? = nil) -> any AnimatedImageFrameDecoding {
        if let customFrameDecoder {
            return customFrameDecoder(maxPixelSize)
        }
        return AnimatedImageFrameDecoder(source: self, maxPixelSize: maxPixelSize)
    }

    /// Applies the two corrections ``delays`` describes.
    static func correctedDelay(_ delay: TimeInterval) -> TimeInterval {
        delay >= minimumDelay ? delay : defaultDelay
    }

    /// Creates an image source over ``data`` for decoding the frames.
    ///
    /// Keep the one it returns alive for as long as you are decoding from it:
    /// a `CGImageSource` indexes the container on the first access, and
    /// re-creating it per frame turns random access from O(1) into O(n).
    ///
    /// - important: `CGImageSource` is not safe to use concurrently. Decode
    /// from one thread at a time, or create one source per decoder.
    public func makeImageSource() -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, AnimatedImageSource.imageSourceOptions)
    }

    /// The options to pass to `CGImageSourceCreateImageAtIndex` when decoding a
    /// frame of an animation.
    ///
    /// `kCGImageSourceShouldCache` is off because the frame buffer in the
    /// player is the only frame cache there should be: left on, Image I/O holds
    /// on to every frame it has ever decoded.
    ///
    /// - note: Computed rather than stored: `CFDictionary` isn't `Sendable`.
    public static var imageSourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    private static func size(of source: CGImageSource) -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double else {
            return .zero
        }
        return CGSize(width: width, height: height)
    }
}
