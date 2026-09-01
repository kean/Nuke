// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

/// An animated image – a GIF, an APNG, an animated WebP, or an animated HEIC –
/// described by the metadata parsed from its encoded data.
///
/// The type holds no decoded frames. Creating it reads the frame count, the
/// per-frame delays, the loop count, and the canvas size, all of which Image I/O
/// answers from the container without decompressing a single pixel. The frames
/// are decoded later, on demand, by `AnimatedImagePlayer` in `NukeUI` – or by a
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
/// The initializer returns `nil` for anything that isn't animated, including a
/// single-frame GIF.
///
/// - note: The type is a class because parsing isn't free – the frame count of
/// a GIF alone requires a scan of the container – and because the views compare
/// animations by identity to decide whether to restart playback.
public final class AnimatedImageSource: Sendable {
    /// The encoded image data.
    ///
    /// The same buffer ``ImageContainer/data`` holds, shared with it rather
    /// than copied.
    public let data: Data

    /// The format of the image, if the data matches a known one.
    public let type: AssetType?

    /// The number of frames. Always greater than one.
    public let frameCount: Int

    /// The display duration of every frame, in seconds.
    ///
    /// The values are the ones stored in the container, with two corrections
    /// that every browser and every animated image renderer applies: a missing
    /// or non-positive delay becomes ``defaultDelay``, and a delay below
    /// ``minimumDelay`` – which no display can keep up with anyway, and which
    /// old authoring tools wrote to mean "as fast as possible" – also becomes
    /// ``defaultDelay``.
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
    /// The threshold is the one browsers use. A GIF that asks for a 0 ms or a
    /// 10 ms delay is, in practice, a GIF written by a tool that meant "as fast
    /// as the renderer can go", and playing it at 100 fps burns CPU to produce
    /// a flicker.
    public static let minimumDelay: TimeInterval = 0.011

    /// Creates a source from the encoded image data.
    ///
    /// The pipeline does this for you – see ``ImageContainer/animation`` – and
    /// on the decoding queue, which is where the walk of the frame metadata
    /// belongs. Reach for this initializer for data that didn't come from the
    /// pipeline, and keep it off the main thread for a large animation.
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
        // An unrecognized container still animates: the frames are there, only
        // the delays are missing, and the default one is the browser behavior.
        let format = AnimatedImageFormat(source: source)
        self.data = data
        self.type = AssetType(data)
        self.frameCount = frameCount
        self.delays = (0..<frameCount).map {
            format?.delay(in: source, at: $0) ?? AnimatedImageSource.defaultDelay
        }
        self.duration = delays.reduce(0, +)
        self.loopCount = format?.loopCount(in: source) ?? 0
        self.size = AnimatedImageSource.size(of: source)
    }

    /// Creates an image source over ``data`` for decoding the frames.
    ///
    /// Keep the one it returns alive for as long as you are decoding from it.
    /// A `CGImageSource` indexes the container the first time it is asked for a
    /// frame, and re-creating it per frame turns random access from O(1) into
    /// O(n).
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
    /// on to every frame it has ever decoded, which for a long animation is
    /// exactly the unbounded growth the buffer exists to prevent.
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

/// The container-specific metadata keys.
///
/// Image I/O files the frame delay and the loop count under a different
/// dictionary for every format, and the keys inside those dictionaries differ
/// too, so there is no generic way to ask for them.
enum AnimatedImageFormat: CaseIterable {
    case gif, png, webp, heics

    /// Identifies the format by which container dictionary the image publishes.
    ///
    /// The dictionary is what the delays are read out of, so its presence is
    /// the question that actually matters – and it is a more direct answer than
    /// the type identifier, which names the still and the sequence flavors of a
    /// format differently (`public.heic` against `public.heics`) and so has to
    /// be kept in step with every one of them. Matching on `public.heic` left
    /// every frame of an animated HEIC with the default delay.
    ///
    /// A still image publishes no container dictionary at all, so this also
    /// answers `nil` for the images that have no animation metadata to read.
    init?(source: CGImageSource) {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let format = AnimatedImageFormat.allCases.first(where: { properties[$0.dictionaryKey] != nil }) else {
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
        }
    }

    var unclampedDelayKey: CFString {
        switch self {
        case .gif: kCGImagePropertyGIFUnclampedDelayTime
        case .png: kCGImagePropertyAPNGUnclampedDelayTime
        case .webp: kCGImagePropertyWebPUnclampedDelayTime
        case .heics: kCGImagePropertyHEICSUnclampedDelayTime
        }
    }

    var delayKey: CFString {
        switch self {
        case .gif: kCGImagePropertyGIFDelayTime
        case .png: kCGImagePropertyAPNGDelayTime
        case .webp: kCGImagePropertyWebPDelayTime
        case .heics: kCGImagePropertyHEICSDelayTime
        }
    }

    var loopCountKey: CFString {
        switch self {
        case .gif: kCGImagePropertyGIFLoopCount
        case .png: kCGImagePropertyAPNGLoopCount
        case .webp: kCGImagePropertyWebPLoopCount
        case .heics: kCGImagePropertyHEICSLoopCount
        }
    }

    /// Returns the display duration of the frame at the given index, corrected
    /// the way ``AnimatedImageSource/delays`` describes.
    func delay(in source: CGImageSource, at index: Int) -> TimeInterval {
        let properties = properties(in: source, at: index)
        // The unclamped value is the one the file actually asks for; the other
        // one has already been clamped by Image I/O for the same reason the
        // correction below exists.
        let delay = (properties?[unclampedDelayKey] as? TimeInterval)
            ?? (properties?[delayKey] as? TimeInterval)
            ?? 0
        guard delay >= AnimatedImageSource.minimumDelay else {
            return AnimatedImageSource.defaultDelay
        }
        return delay
    }

    /// Returns the number of loops the image asks for, or `0` for "forever".
    func loopCount(in source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let container = properties[dictionaryKey] as? [CFString: Any] else {
            return 0
        }
        return container[loopCountKey] as? Int ?? 0
    }

    private func properties(in source: CGImageSource, at index: Int) -> [CFString: Any]? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return nil
        }
        return properties[dictionaryKey] as? [CFString: Any]
    }
}
