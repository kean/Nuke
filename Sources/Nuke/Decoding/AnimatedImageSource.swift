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
/// renderer of your own, built on ``makeImageSource()``.
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

    /// The format of the image, if the data matches a known one.
    public let type: AssetType?

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
    public let loopCount: Int

    /// The size of the animation canvas, in pixels.
    public let size: CGSize

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
        self.type = AssetType(data)
        self.frameCount = frameCount
        self.delays = (0..<frameCount).map {
            format?.delay(in: source, at: $0) ?? AnimatedImageSource.defaultDelay
        }
        self.duration = delays.reduce(0, +)
        self.loopCount = format?.loopCount(in: properties) ?? 0
        self.size = AnimatedImageSource.size(of: source)
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

/// The container dictionary an animated image publishes its metadata in.
///
/// Image I/O files the frame delay and the loop count under a different
/// dictionary for every format, so there is no generic way to ask for them.
/// The keys inside are the same for every one.
enum AnimatedImageFormat: CaseIterable {
    case gif, png, webp, heics, avis

    /// Identifies the format by which container dictionary the image publishes.
    ///
    /// More direct than the type identifier, which names the still and the
    /// sequence flavors of a format differently (`public.heic` against
    /// `public.heics`): matching on `public.heic` left every frame of an
    /// animated HEIC with the default delay. A still image publishes no
    /// container dictionary, so this is `nil` for it.
    ///
    /// - parameter properties: The container properties of the image source.
    init?(properties: [CFString: Any]) {
        guard let format = AnimatedImageFormat.allCases.first(where: { properties[$0.dictionaryKey] != nil }) else {
            return nil
        }
        self = format
    }

    var dictionaryKey: CFString {
        switch self {
        case .gif: kCGImagePropertyGIFDictionary
        case .png: kCGImagePropertyPNGDictionary
        case .webp: kCGImagePropertyWebPDictionary
        case .heics: kCGImagePropertyHEICSDictionary
        case .avis: kCGImagePropertyAVISDictionary
        }
    }

    /// The keys every container files its metadata under.
    ///
    /// `kCGImageProperty{GIF,APNG,WebP,HEICS}DelayTime` are all the same
    /// string, and Image I/O publishes `kCGImagePropertyAVISDictionary` with no
    /// constants for the keys inside it at all. Getting them wrong is silent,
    /// not fatal: every frame falls back to
    /// ``AnimatedImageSource/defaultDelay``.
    ///
    /// - note: Computed rather than stored: `CFString` isn't `Sendable`.
    private static var delayKey: CFString { "DelayTime" as CFString }
    private static var unclampedDelayKey: CFString { "UnclampedDelayTime" as CFString }
    private static var loopCountKey: CFString { "LoopCount" as CFString }

    /// Returns the display duration of the frame at the given index, corrected
    /// the way ``AnimatedImageSource/delays`` describes.
    func delay(in source: CGImageSource, at index: Int) -> TimeInterval {
        let properties = properties(in: source, at: index)
        // The unclamped value is the one the file asks for; the other one has
        // already been clamped by Image I/O.
        let delay = (properties?[Self.unclampedDelayKey] as? TimeInterval)
            ?? (properties?[Self.delayKey] as? TimeInterval)
            ?? 0
        guard delay >= AnimatedImageSource.minimumDelay else {
            return AnimatedImageSource.defaultDelay
        }
        return delay
    }

    /// Returns the number of loops the image asks for, or `0` for "forever".
    ///
    /// - parameter properties: The container properties of the image source.
    func loopCount(in properties: [CFString: Any]) -> Int {
        guard let container = properties[dictionaryKey] as? [CFString: Any] else {
            return 0
        }
        return container[Self.loopCountKey] as? Int ?? 0
    }

    private func properties(in source: CGImageSource, at index: Int) -> [CFString: Any]? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return nil
        }
        return properties[dictionaryKey] as? [CFString: Any]
    }
}
