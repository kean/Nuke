// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import Nuke

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A made-up animated format, for the tests that cover playing one Image I/O
/// has never heard of.
///
/// Deliberately not a real container: `CGImageSourceCreateWithData` returns
/// `nil` for it, which is the whole point. It is the case
/// ``AnimatedImageSource/init(data:)`` can't serve and
/// ``AnimatedImageSource/init(data:delays:loopCount:size:makeFrameDecoder:)``
/// exists for.
///
/// The layout, all little-endian: the eight bytes `FLIPBOOK`, the width, the
/// height, the frame count, and the loop count as `UInt16`s, then four bytes
/// per frame – the delay in hundredths of a second, and a red, a green, and a
/// blue component. Every frame is a solid color, so a test can tell one from
/// another by reading a single pixel.
struct Flipbook: Sendable {
    static let magic = Array("FLIPBOOK".utf8)

    let size: CGSize
    let loopCount: Int
    let frames: [Frame]

    struct Frame: Sendable, Equatable {
        var delay: TimeInterval
        var color: [UInt8] // Red, green, blue

        /// The pixel ``AnimatedImageTest/firstPixel(of:)`` reads back for it.
        var pixel: [UInt8] { color + [255] }
    }

    var delays: [TimeInterval] { frames.map(\.delay) }

    // MARK: Parsing

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 16, Array(bytes[0..<8]) == Flipbook.magic else {
            return nil
        }
        func number(at offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
        }
        let frameCount = number(at: 12)
        guard bytes.count >= 16 + frameCount * 4 else {
            return nil
        }
        self.size = CGSize(width: number(at: 8), height: number(at: 10))
        self.loopCount = number(at: 14)
        self.frames = (0..<frameCount).map { index in
            let offset = 16 + index * 4
            return Frame(
                delay: TimeInterval(bytes[offset]) / 100,
                color: Array(bytes[(offset + 1)..<(offset + 4)])
            )
        }
    }

    // MARK: Encoding

    /// Builds the encoded form of an animation with the given frames, each one
    /// a different solid color.
    static func encode(
        frameCount: Int = 4,
        delays: [TimeInterval]? = nil,
        loopCount: Int = 0,
        size: CGSize = CGSize(width: 8, height: 8)
    ) -> Data {
        var bytes = magic
        func append(_ value: Int) {
            bytes.append(UInt8(value & 0xFF))
            bytes.append(UInt8((value >> 8) & 0xFF))
        }
        append(Int(size.width))
        append(Int(size.height))
        append(frameCount)
        append(loopCount)
        for index in 0..<frameCount {
            let delay = delays.map { $0[min(index, $0.count - 1)] } ?? 0.1
            bytes.append(UInt8((delay * 100).rounded()))
            bytes.append(contentsOf: color(at: index))
        }
        return Data(bytes)
    }

    /// The color of the frame at the given index: a ramp of primaries, so that
    /// no two neighboring frames read back the same.
    static func color(at index: Int) -> [UInt8] {
        let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0], [255, 0, 255], [0, 255, 255]]
        return colors[index % colors.count]
    }

    // MARK: Frames

    /// Draws the frame at the given index, no larger than the given size.
    func makeImage(at index: Int, maxPixelSize: CGFloat? = nil) -> CGImage? {
        guard frames.indices.contains(index) else { return nil }
        var width = Int(size.width)
        var height = Int(size.height)
        if let maxPixelSize, maxPixelSize > 0 {
            let longestSide = CGFloat(max(width, height))
            if longestSide > maxPixelSize {
                let scale = maxPixelSize / longestSide
                width = max(1, Int((CGFloat(width) * scale).rounded()))
                height = max(1, Int((CGFloat(height) * scale).rounded()))
            }
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        let color = frames[index].color.map { CGFloat($0) / 255 }
        context.setFillColor(red: color[0], green: color[1], blue: color[2], alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// Produces the frames of a ``Flipbook``.
///
/// An actor, which is what keeps the drawing off the main one – the shape the
/// documentation asks for.
actor FlipbookFrameDecoder: AnimatedImageFrameDecoding {
    private let flipbook: Flipbook
    private let maxPixelSize: CGFloat?

    /// The frames it was asked for, in the order it was asked for them.
    private(set) var requestedIndexes: [Int] = []

    init(_ flipbook: Flipbook, maxPixelSize: CGFloat? = nil) {
        self.flipbook = flipbook
        self.maxPixelSize = maxPixelSize
    }

    func decode(at index: Int) -> CGImage? {
        requestedIndexes.append(index)
        return flipbook.makeImage(at: index, maxPixelSize: maxPixelSize)
    }
}

/// Reads the format the way an app adds one: an ``ImageDecoding`` registered
/// with ``ImageDecoderRegistry``, which produces both the still image and the
/// animation to play in its place.
struct FlipbookImageDecoder: ImageDecoding {
    /// Every decoder this initializer made, so that a test can look at what
    /// the pipeline asked its decoder for.
    static let decoders = FlipbookDecoderLog()

    init?(context: ImageDecodingContext) {
        guard context.isCompleted, Flipbook(data: context.data) != nil else {
            return nil // Not this format, or not all of it yet
        }
    }

    func decode(_ data: Data) throws -> ImageContainer {
        guard let flipbook = Flipbook(data: data),
              let image = flipbook.makeImage(at: 0) else {
            throw ImageDecodingError.unknown
        }
        var container = ImageContainer(image: makePlatformImage(image))
        // The data travels the way it does for the formats Image I/O reads:
        // the animation shares the buffer rather than copying it.
        container.data = data
        container.animation = AnimatedImageSource(
            data: data,
            delays: flipbook.delays,
            loopCount: flipbook.loopCount,
            size: flipbook.size,
            makeFrameDecoder: { maxPixelSize in
                let decoder = FlipbookFrameDecoder(flipbook, maxPixelSize: maxPixelSize)
                FlipbookImageDecoder.decoders.append(decoder)
                return decoder
            }
        )
        return container
    }

    private func makePlatformImage(_ image: CGImage) -> PlatformImage {
#if canImport(UIKit)
        UIImage(cgImage: image)
#else
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
#endif
    }
}

/// The decoders a ``FlipbookImageDecoder`` has handed out, which is how a test
/// asks what the player decoded and at what size.
final class FlipbookDecoderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FlipbookFrameDecoder] = []

    var all: [FlipbookFrameDecoder] { lock.withLock { storage } }

    func append(_ decoder: FlipbookFrameDecoder) {
        lock.withLock { storage.append(decoder) }
    }

    func removeAll() {
        lock.withLock { storage.removeAll() }
    }
}
