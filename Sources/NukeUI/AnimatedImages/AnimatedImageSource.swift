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

    /// Whether the data has been parsed before, which is what says whether
    /// ``parse(data:completion:)`` will answer before it returns.
    static func isParsed(data: Data) -> Bool {
        AnimatedImageSourceCache.shared.parsed(for: data) != nil
    }

    /// Parses the data off the main thread and calls back with the animation,
    /// or `nil` if there isn't one.
    ///
    /// The answer arrives synchronously – the completion runs before this
    /// returns – when the data has been parsed before, which in a list is every
    /// display after the first. Otherwise the parse runs on a cooperative
    /// thread: counting the frames of a container and reading the delay of each
    /// one is a frame's worth of main-thread time for a large animation, and
    /// something is always on screen to hold the place in the meantime.
    ///
    /// - returns: The task doing the parsing, or `nil` if there was nothing to
    /// do. Cancel it to drop a result that is no longer wanted; the completion
    /// isn't called after that.
    @MainActor
    static func parse(
        data: Data,
        completion: @escaping @MainActor (AnimatedImageSource?) -> Void
    ) -> Task<Void, Never>? {
        if let parsed = AnimatedImageSourceCache.shared.parsed(for: data) {
            completion(parsed)
            return nil
        }
        return Task.detached(priority: .userInitiated) {
            let source = AnimatedImageSource.cached(data: data)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Cancellation can only come from the main actor, so by the
                // time this runs it has either happened or it hasn't.
                guard !Task.isCancelled else { return }
                completion(source)
            }
        }
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

/// The animations parsed most recently, keyed by the data they came from.
///
/// `NSCache` rather than a dictionary: it is thread-safe, it evicts under
/// memory pressure, and the entries are worth exactly nothing when the system
/// needs the memory back.
final class AnimatedImageSourceCache: @unchecked Sendable {
    static let shared = AnimatedImageSourceCache()

    /// How many parses are remembered.
    ///
    /// Bounded by count alone, because a cost limit here measures the wrong
    /// thing. What an entry actually adds is a frame count and an array of
    /// delays: the data it holds is the same buffer the ``ImageContainer`` in
    /// the image cache is holding, shared with it rather than copied. Charging
    /// each entry the size of its animation filled a 16 MB budget with
    /// animations that cost kilobytes apiece, and left a 20 MB one unable to
    /// stay at all – so a list of more than a handful of animations re-parsed
    /// every one of them on every scroll back, which is the exact thing this
    /// cache exists to prevent.
    ///
    /// The trade is that an entry that outlives its image cache entry becomes
    /// the last owner of that data. `NSCache` empties itself when the system
    /// asks, which is the bound on it.
    private static let countLimit = 200

    /// `NSNull` for data that turned out not to be animated.
    ///
    /// The failures have to be remembered too. The pipeline attaches the data
    /// to every GIF, animated or not – whether it is animated is exactly what
    /// this parse is answering – so a list of static GIFs would otherwise
    /// create a `CGImageSource` and count its frames on the main thread every
    /// time a cell was displayed.
    private let cache = NSCache<AnimatedImageDataKey, AnyObject>()

    init() {
        cache.countLimit = AnimatedImageSourceCache.countLimit
    }

    func source(for data: Data) -> AnimatedImageSource? {
        let key = AnimatedImageDataKey(data)
        if let entry = cache.object(forKey: key) {
            return entry as? AnimatedImageSource
        }
        guard let source = AnimatedImageSource(data: data) else {
            cache.setObject(NSNull(), forKey: key)
            return nil
        }
        cache.setObject(source, forKey: key)
        return source
    }

    /// What has already been parsed for the given data.
    ///
    /// The outer optional says whether the data has been parsed at all, the
    /// inner one whether it turned out to be animated.
    func parsed(for data: Data) -> AnimatedImageSource?? {
        guard let entry = cache.object(forKey: AnimatedImageDataKey(data)) else {
            return nil
        }
        return .some(entry as? AnimatedImageSource)
    }
}

/// The key the parsed animations are cached under.
///
/// Not `NSData`, whose hash covers the first 80 bytes. Animations written by
/// the same encoder at the same size are identical for far longer than that –
/// the signature, the screen descriptor, the palette – so every lookup in a
/// list of them collided, and `NSCache` fell through to comparing the contents
/// in full: a memcmp of the whole animation, per cell displayed.
///
/// The hash reads the length and a fixed number of bytes spread from the first
/// to the last instead, which costs the same and tells the images apart.
/// Equality is unchanged – the contents, in full – so a collision is still only
/// ever slow, never wrong.
final class AnimatedImageDataKey: NSObject {
    let data: Data
    private let precomputedHash: Int

    init(_ data: Data) {
        self.data = data
        var hasher = Hasher()
        hasher.combine(data.count)
        let sampleCount = min(32, data.count)
        if sampleCount == 1 {
            hasher.combine(data[data.startIndex])
        } else if sampleCount > 1 {
            for sample in 0..<sampleCount {
                let offset = sample * (data.count - 1) / (sampleCount - 1)
                hasher.combine(data[data.index(data.startIndex, offsetBy: offset)])
            }
        }
        self.precomputedHash = hasher.finalize()
    }

    override var hash: Int { precomputedHash }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AnimatedImageDataKey else { return false }
        return precomputedHash == other.precomputedHash && data == other.data
    }
}
