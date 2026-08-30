// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import Nuke

/// An animated image – a GIF, an APNG, an animated WebP, or an animated HEIC –
/// described by the metadata parsed from its encoded data.
///
/// The type holds no decoded frames. Creating it reads the frame count, the
/// per-frame delays, the loop count, and the canvas size, all of which Image I/O
/// answers from the container without decompressing a single pixel. The frames
/// are decoded later, on demand, by ``AnimatedImagePlayer``.
///
/// ```swift
/// guard let source = AnimatedImageSource(container: response.container) else {
///     return // Not an animated image – display `container.image` as usual
/// }
/// print(source.frameCount, source.duration, source.loopCount)
/// ```
///
/// The initializers return `nil` for anything that isn't animated, including a
/// single-frame GIF, so a non-`nil` value answers "can this be played?"
///
/// - note: The type is a class because parsing isn't free – the frame count of
/// a GIF alone requires a scan of the container – and because the views compare
/// sources by identity to decide whether to restart the animation.
public final class AnimatedImageSource: Sendable {
    /// The encoded image data.
    public let data: Data

    /// The format of the image, if Nuke recognizes it.
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
    /// - returns: `nil` if the data isn't an image, or if the image has a
    /// single frame.
    public init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
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

    /// Creates a source from an image loaded by the pipeline.
    ///
    /// The pipeline attaches the original data to the containers of the images
    /// it recognizes as animated (see ``ImageContainer/data``), which is what
    /// this initializer needs. It returns `nil` for every other image.
    public convenience init?(container: ImageContainer) {
        guard let data = container.data else {
            return nil
        }
        self.init(data: data)
    }

    /// Returns the animation for the given data, parsing it only if it hasn't
    /// been parsed recently.
    ///
    /// Parsing walks the properties of every frame, and the pipeline hands the
    /// same data to a view every time a memory-cached image is displayed, so
    /// scrolling back to an animation in a list would otherwise pay for it
    /// again. The views go through here; ``init(data:)`` always parses.
    static func cached(data: Data) -> AnimatedImageSource? {
        AnimatedImageSourceCache.shared.source(for: data)
    }

    /// Returns the animation attached to the container, if there is one.
    static func cached(container: ImageContainer) -> AnimatedImageSource? {
        container.data.flatMap(cached(data:))
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

/// Options passed to every `CGImageSource` the module creates.
///
/// `kCGImageSourceShouldCache` is off because the buffer in
/// ``AnimatedImagePlayer`` is the only frame cache there should be: left on,
/// Image I/O holds on to every frame it has ever decoded, which for a long
/// animation is exactly the unbounded growth the buffer exists to prevent.
var imageSourceOptions: CFDictionary {
    [kCGImageSourceShouldCache: false] as CFDictionary
}

/// The container-specific metadata keys.
///
/// Image I/O files the frame delay and the loop count under a different
/// dictionary for every format, and the keys inside those dictionaries differ
/// too, so there is no generic way to ask for them.
enum AnimatedImageFormat: CaseIterable {
    case gif, png, webp, heics

    init?(source: CGImageSource) {
        guard let type = CGImageSourceGetType(source) as String? else {
            return nil
        }
        switch type {
        case AssetType.gif.rawValue: self = .gif
        case AssetType.png.rawValue: self = .png
        case AssetType.webp.rawValue: self = .webp
        // Image I/O reports the still and the sequence flavors of the ISO base
        // media formats under the same identifier and files the metadata of
        // both under the HEICS dictionary.
        case AssetType.heic.rawValue, AssetType.avif.rawValue: self = .heics
        default: return nil
        }
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

/// The animations parsed most recently, keyed by the data they came from.
///
/// `NSCache` rather than a dictionary: it is thread-safe, it evicts under
/// memory pressure, and the entries are worth exactly nothing when the system
/// needs the memory back. The cost of an entry is the data the source holds on
/// to, which the image cache is usually holding as well.
final class AnimatedImageSourceCache: @unchecked Sendable {
    static let shared = AnimatedImageSourceCache()

    /// `NSNull` for data that turned out not to be animated.
    ///
    /// The failures have to be remembered too. The pipeline attaches the data
    /// to every GIF, animated or not – whether it is animated is exactly what
    /// this parse is answering – so a list of static GIFs would otherwise
    /// create a `CGImageSource` and count its frames on the main thread every
    /// time a cell was displayed.
    private let cache = NSCache<NSData, AnyObject>()

    init() {
        cache.countLimit = 32
        cache.totalCostLimit = 16 * 1_048_576
    }

    func source(for data: Data) -> AnimatedImageSource? {
        let key = data as NSData
        if let entry = cache.object(forKey: key) {
            return entry as? AnimatedImageSource
        }
        guard let source = AnimatedImageSource(data: data) else {
            // Nothing is held that the caller isn't holding already – the key
            // is the same buffer – so the entry costs nothing and never pushes
            // a parsed animation out.
            cache.setObject(NSNull(), forKey: key, cost: 0)
            return nil
        }
        cache.setObject(source, forKey: key, cost: data.count)
        return source
    }

    /// `true` when the data has been parsed and remembered as a still image.
    /// Exists for the tests.
    func isKnownStatic(_ data: Data) -> Bool {
        cache.object(forKey: data as NSData) is NSNull
    }
}
