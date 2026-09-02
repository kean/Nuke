// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

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
    /// animated HEIC with the default delay.
    ///
    /// This is also the test for whether the image animates at all: a still, a
    /// multi-page TIFF, and a multi-image HEIC publish no container dictionary,
    /// and `nil` here means there is nothing to play.
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
            return defaultLoopCount
        }
        return container[Self.loopCountKey] as? Int ?? defaultLoopCount
    }

    /// The number of loops to assume for a container that declares none.
    ///
    /// A GIF stores its loop count in the Netscape application extension, and
    /// a GIF without that block asks to be played once – the semantics every
    /// browser follows. Every other format either always declares a count or
    /// has nowhere to put one, and there "forever" is the right guess.
    private var defaultLoopCount: Int {
        self == .gif ? 1 : 0
    }

    private func properties(in source: CGImageSource, at index: Int) -> [CFString: Any]? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return nil
        }
        return properties[dictionaryKey] as? [CFString: Any]
    }
}
