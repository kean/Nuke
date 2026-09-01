// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import Nuke
import UniformTypeIdentifiers

/// Animated images built at run time.
///
/// Generating them beats checking in a binary: a test can ask for the exact
/// frame count, delays, loop count, and canvas size it wants to assert on, and
/// every frame is a different solid color, so "did the frame change?" is a
/// question the tests can actually answer.
extension Test {
    /// Builds an animated GIF.
    ///
    /// - parameter delays: The delay of each frame, in seconds. GIF stores
    /// delays in hundredths of a second, so use multiples of `0.01`.
    /// - parameter loopCount: The loop count to write, or `nil` to write none:
    /// a GIF with no loop count gets no Netscape application extension at all,
    /// which is the "play once" case.
    static func animatedGIF(
        frameCount: Int = 4,
        delays: [TimeInterval]? = nil,
        loopCount: Int? = 0,
        size: CGSize = CGSize(width: 8, height: 8)
    ) -> Data {
        makeAnimation(
            type: UTType.gif,
            frameCount: frameCount,
            delays: delays ?? Array(repeating: 0.1, count: frameCount),
            size: size,
            containerKey: kCGImagePropertyGIFDictionary,
            loopCountKey: kCGImagePropertyGIFLoopCount,
            loopCount: loopCount,
            delayKeys: [kCGImagePropertyGIFDelayTime, kCGImagePropertyGIFUnclampedDelayTime]
        )! // Image I/O writes GIF on every platform
    }

    /// Builds an animated PNG, or returns `nil` if Image I/O on this platform
    /// can't write one.
    static func animatedPNG(
        frameCount: Int = 4,
        delays: [TimeInterval]? = nil,
        loopCount: Int = 0,
        size: CGSize = CGSize(width: 8, height: 8)
    ) -> Data? {
        let data = makeAnimation(
            type: UTType.png,
            frameCount: frameCount,
            delays: delays ?? Array(repeating: 0.1, count: frameCount),
            size: size,
            containerKey: kCGImagePropertyPNGDictionary,
            loopCountKey: kCGImagePropertyAPNGLoopCount,
            loopCount: loopCount,
            delayKeys: [kCGImagePropertyAPNGDelayTime, kCGImagePropertyAPNGUnclampedDelayTime]
        )
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == frameCount else {
            return nil
        }
        return data
    }

    /// Builds an animated HEIC – a HEIF image sequence – or returns `nil` if
    /// Image I/O on this platform can't write one.
    ///
    /// The one fixture whose container is written by the same encoder Apple's
    /// own tools use, which is the point: a hand-built `ftyp` box proves what
    /// the sniffer does with the brands a test chose, not with the ones a real
    /// sequence carries (`msf1` up front, the codec further down the list).
    static func animatedHEICS(
        frameCount: Int = 4,
        delays: [TimeInterval]? = nil,
        loopCount: Int = 0,
        size: CGSize = CGSize(width: 8, height: 8)
    ) -> Data? {
        let data = makeAnimation(
            type: heics,
            frameCount: frameCount,
            delays: delays ?? Array(repeating: 0.1, count: frameCount),
            size: size,
            containerKey: kCGImagePropertyHEICSDictionary,
            loopCountKey: kCGImagePropertyHEICSLoopCount,
            loopCount: loopCount,
            delayKeys: [kCGImagePropertyHEICSDelayTime, kCGImagePropertyHEICSUnclampedDelayTime]
        )
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == frameCount else {
            return nil
        }
        return data
    }

    /// The HEIF image sequence type. `UTType` has no constant for it.
    private static let heics = UTType("public.heics") ?? .heic

    /// Builds a single-frame PNG of the given size.
    static func staticPNG(size: CGSize = CGSize(width: 8, height: 8)) -> Data {
        makeAnimation(
            type: UTType.png,
            frameCount: 1,
            delays: [0],
            size: size,
            containerKey: kCGImagePropertyPNGDictionary,
            loopCountKey: kCGImagePropertyAPNGLoopCount,
            loopCount: 0,
            delayKeys: []
        )! // Image I/O writes PNG on every platform
    }

    /// The color the frame at the given index is filled with, so that a test
    /// can tell one decoded frame from another.
    static func animationFrameColor(at index: Int) -> CGColor {
        let hue = CGFloat(index % 6) / 6
        return CGColor(red: hue, green: 1 - hue, blue: CGFloat((index % 2)), alpha: 1)
    }

    private static func makeAnimation(
        type: UTType,
        frameCount: Int,
        delays: [TimeInterval],
        size: CGSize,
        containerKey: CFString,
        loopCountKey: CFString,
        loopCount: Int?,
        delayKeys: [CFString]
    ) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            type.identifier as CFString,
            frameCount,
            nil
        ) else {
            return nil // No encoder for this format on this platform
        }
        if let loopCount {
            CGImageDestinationSetProperties(destination, [
                containerKey: [loopCountKey: loopCount]
            ] as CFDictionary)
        }
        for index in 0..<frameCount {
            var frameProperties: [CFString: Any] = [:]
            if !delayKeys.isEmpty {
                let delay = delays[min(index, delays.count - 1)]
                frameProperties[containerKey] = Dictionary(
                    uniqueKeysWithValues: delayKeys.map { ($0, delay) }
                )
            }
            CGImageDestinationAddImage(
                destination,
                makeFrame(index: index, size: size),
                frameProperties as CFDictionary
            )
        }
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func makeFrame(index: Int, size: CGSize) -> CGImage {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(animationFrameColor(at: index))
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()!
    }
}
