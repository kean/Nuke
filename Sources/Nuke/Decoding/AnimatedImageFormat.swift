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

    /// Whether the decoder should be asked for the frames in the order the
    /// file stores them.
    ///
    /// A frame of these formats can be a patch on the ones before it, so Image
    /// I/O produces it by walking forward from the last frame it composed, and
    /// from the start of the animation to go back. Taking the 22 frames of
    /// `cat.gif` from last to first costs 9 times what first to last does as a
    /// GIF, 9 times as an APNG with delta frames, and 8 as a WebP. It costs the
    /// same as a HEIC or an AVIF sequence, which is why those are left out,
    /// and as an APNG of full frames, which nothing short of reading its frame
    /// headers tells from one of deltas.
    var composesFramesInFileOrder: Bool {
        switch self {
        case .gif, .png, .webp: true
        case .heics, .avis: false
        }
    }

    /// Returns the frames of an APNG that ask for the canvas to be restored
    /// to what it was before them, which Image I/O publishes no property for.
    ///
    /// The first frame is not among them: there is nothing to restore, and
    /// the format says to treat it as clearing the canvas.
    ///
    /// - returns: An empty set for data that isn't a PNG, or that a chunk
    /// doesn't fit in.
    static func framesRestoringTheCanvas(in data: Data) -> Set<Int> {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.starts(with: signature) else {
            return []
        }
        // The chunks are length-prefixed, so reaching every frame control
        // chunk reads a dozen bytes of each and inflates nothing.
        let disposalOffset = 24 // Into the chunk data of `fcTL`
        let restorePrevious: UInt8 = 2
        return data.withUnsafeBytes { bytes in
            var frames = Set<Int>()
            var frame = 0
            var offset = signature.count
            while offset + 8 <= bytes.count {
                let length = (0..<4).reduce(0) { $0 << 8 | Int(bytes[offset + $1]) }
                let isFrameControl = bytes[offset + 4] == 0x66 && bytes[offset + 5] == 0x63 // "fc"
                    && bytes[offset + 6] == 0x54 && bytes[offset + 7] == 0x4C // "TL"
                guard offset + 8 + length <= bytes.count else {
                    break
                }
                if isFrameControl {
                    if frame > 0, length > disposalOffset, bytes[offset + 8 + disposalOffset] == restorePrevious {
                        frames.insert(frame)
                    }
                    frame += 1
                }
                offset += 8 + length + 4 // The checksum
            }
            return frames
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
        return AnimatedImageSource.correctedDelay(delay)
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
