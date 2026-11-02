// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation

/// Animations whose frames are patches on the ones before them, written byte
/// by byte.
///
/// Image I/O won't write one: it re-encodes every frame it is given as a full
/// canvas, which makes the file answer in any order and tests nothing about an
/// order that isn't the one in the file. Real GIFs and APNGs are mostly
/// patches, and it is those a decoder has to compose.
///
/// The canvas is 16×16, made of four 8×8 quadrants of one color each, so that
/// a test can read what a frame came out as from the middle of each quadrant.
enum DeltaAnimation {
    enum Disposal: UInt8 {
        case none = 1, background = 2, previous = 3

        /// APNG numbers the same three from zero, in the same order.
        var apngOperation: UInt8 { rawValue - 1 }
    }

    enum Quadrant: Int, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var origin: (x: Int, y: Int) {
            switch self {
            case .topLeft: (0, 0)
            case .topRight: (8, 0)
            case .bottomLeft: (0, 8)
            case .bottomRight: (8, 8)
            }
        }
    }

    struct Frame {
        /// The quadrant the frame patches, or `nil` for the whole canvas.
        let quadrant: Quadrant?
        let color: Int
        let disposal: Disposal
    }

    /// Each frame depends on the ones before it: the first paints the canvas,
    /// and the rest patch it and dispose of the patch in every way there is.
    static let frames = [
        Frame(quadrant: nil, color: 0, disposal: .none),
        Frame(quadrant: .topLeft, color: 1, disposal: .none),
        Frame(quadrant: .topRight, color: 2, disposal: .previous),
        Frame(quadrant: .bottomLeft, color: 3, disposal: .background),
        Frame(quadrant: .bottomRight, color: 1, disposal: .none),
        Frame(quadrant: .topRight, color: 3, disposal: .none)
    ]

    /// A run of frames that each restore the canvas when they are done, which
    /// is how a small thing moving over a still background is usually stored,
    /// followed by frames that don't.
    static let restoringFrames = [
        Frame(quadrant: nil, color: 0, disposal: .none),
        Frame(quadrant: .topLeft, color: 1, disposal: .previous),
        Frame(quadrant: .topRight, color: 2, disposal: .previous),
        Frame(quadrant: .bottomLeft, color: 3, disposal: .previous),
        Frame(quadrant: .bottomRight, color: 1, disposal: .previous),
        Frame(quadrant: .topLeft, color: 3, disposal: .none),
        Frame(quadrant: .topRight, color: 1, disposal: .none)
    ]

    /// What each of ``restoringFrames`` looks like once it's composed.
    static let composedRestoringFrames: [[Int?]] = [
        [0, 0, 0, 0],
        [1, 0, 0, 0],
        [0, 2, 0, 0],
        [0, 0, 3, 0],
        [0, 0, 0, 1],
        [3, 0, 0, 0],
        [3, 1, 0, 0]
    ]

    /// What each of ``frames`` looks like once it's composed, as the color of
    /// each quadrant, `nil` for a quadrant that was cleared, which reads as
    /// nothing in an APNG and as black in a GIF with no transparent color.
    static let composedFrames: [[Int?]] = [
        [0, 0, 0, 0],
        [1, 0, 0, 0],
        [1, 2, 0, 0], // Restored to the frame before by the next one
        [1, 0, 3, 0],
        [1, 0, nil, 1], // Cleared by the end of the frame before
        [1, 3, nil, 1]
    ]

    static let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]

    /// Returns the quadrants of the image that aren't what the frame at the
    /// given index composes to, each with the pixel found there.
    static func mismatches(in image: CGImage, frameAt index: Int, of composedFrames: [[Int?]] = composedFrames) -> [String] {
        guard let bitmap = RGBABitmap(cgImage: image) else {
            return ["unreadable"]
        }
        return Quadrant.allCases.compactMap { quadrant in
            let (x, y) = (quadrant.origin.x + 4, quadrant.origin.y + 4)
            let color = composedFrames[index][quadrant.rawValue].map { colors[$0] } ?? [0, 0, 0]
            let isClose = bitmap.color(atX: x, y: y).isClose(to: PixelColor(red: color[0], green: color[1], blue: color[2]))
            return isClose ? nil : "\(quadrant) of frame \(index): \(bitmap.pixel(atX: x, y: y))"
        }
    }

    private static let canvasSize = 16

    private struct Bounds {
        let x: Int, y: Int, width: Int, height: Int
    }

    private static func bounds(of frame: Frame) -> Bounds {
        guard let quadrant = frame.quadrant else {
            return Bounds(x: 0, y: 0, width: canvasSize, height: canvasSize)
        }
        return Bounds(x: quadrant.origin.x, y: quadrant.origin.y, width: canvasSize / 2, height: canvasSize / 2)
    }

    // MARK: GIF

    /// A looping GIF of the given frames, each shown for 0.1 s.
    static func gif(frames: [Frame] = frames) -> Data {
        var bytes = Array("GIF89a".utf8)
        bytes += littleEndian(canvasSize) + littleEndian(canvasSize)
        bytes += [0x81, 0, 0] // A global color table of 4, background 0
        bytes += colors.flatMap { $0 }
        bytes += [0x21, 0xFF, 0x0B] + Array("NETSCAPE2.0".utf8) + [3, 1, 0, 0, 0]
        for frame in frames {
            let bounds = bounds(of: frame)
            bytes += [0x21, 0xF9, 4, frame.disposal.rawValue << 2, 10, 0, 0, 0]
            bytes += [0x2C]
            bytes += littleEndian(bounds.x) + littleEndian(bounds.y)
            bytes += littleEndian(bounds.width) + littleEndian(bounds.height)
            bytes += [0]
            bytes += lzw(Array(repeating: UInt8(frame.color), count: bounds.width * bounds.height))
        }
        bytes += [0x3B]
        return Data(bytes)
    }

    /// Encodes color indexes with a code size of 2.
    ///
    /// A clear code every two pixels stops the decoder's table from growing,
    /// so every code stays 3 bits wide and there is no dictionary to build.
    private static func lzw(_ pixels: [UInt8]) -> [UInt8] {
        let clear: UInt32 = 4, end: UInt32 = 5
        var codes: [UInt32] = []
        for (offset, pixel) in pixels.enumerated() {
            if offset % 2 == 0 { codes.append(clear) }
            codes.append(UInt32(pixel))
        }
        codes.append(end)

        var data: [UInt8] = []
        var accumulator: UInt32 = 0
        var bitCount: UInt32 = 0
        for code in codes {
            accumulator |= code << bitCount
            bitCount += 3
            while bitCount >= 8 {
                data.append(UInt8(accumulator & 0xFF))
                accumulator >>= 8
                bitCount -= 8
            }
        }
        if bitCount > 0 {
            data.append(UInt8(accumulator & 0xFF))
        }

        var blocks: [UInt8] = [2]
        for start in stride(from: 0, to: data.count, by: 255) {
            let block = data[start..<min(start + 255, data.count)]
            blocks += [UInt8(block.count)] + block
        }
        return blocks + [0]
    }

    private static func littleEndian(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    // MARK: APNG

    /// A looping APNG of the given frames, each shown for 0.1 s.
    static func apng(frames: [Frame] = frames) -> Data {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        bytes += chunk("IHDR", bigEndian(canvasSize) + bigEndian(canvasSize) + [8, 6, 0, 0, 0])
        bytes += chunk("acTL", bigEndian(frames.count) + bigEndian(0))
        var sequenceNumber = 0
        for (index, frame) in frames.enumerated() {
            let bounds = bounds(of: frame)
            var control = bigEndian(sequenceNumber)
            control += bigEndian(bounds.width) + bigEndian(bounds.height)
            control += bigEndian(bounds.x) + bigEndian(bounds.y)
            control += [0, 10, 0, 100] // 10/100 s
            control += [frame.disposal.apngOperation, 0] // Replace what's under it
            bytes += chunk("fcTL", control)
            sequenceNumber += 1

            let pixels = zlib(scanlines(of: frame))
            if index == 0 {
                bytes += chunk("IDAT", pixels)
            } else {
                bytes += chunk("fdAT", bigEndian(sequenceNumber) + pixels)
                sequenceNumber += 1
            }
        }
        bytes += chunk("IEND", [])
        return Data(bytes)
    }

    private static func scanlines(of frame: Frame) -> [UInt8] {
        let bounds = bounds(of: frame)
        let row: [UInt8] = [0] + Array(repeating: colors[frame.color] + [255], count: bounds.width).flatMap { $0 }
        return Array(repeating: row, count: bounds.height).flatMap { $0 }
    }

    /// Wraps the bytes in a zlib stream of one stored block.
    private static func zlib(_ bytes: [UInt8]) -> [UInt8] {
        let length = UInt16(bytes.count)
        var stream: [UInt8] = [0x78, 0x01, 1]
        stream += [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
        stream += bytes
        var (a, b): (UInt32, UInt32) = (1, 0)
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return stream + bigEndian(Int(b << 16 | a))
    }

    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let body = Array(type.utf8) + data
        return bigEndian(data.count) + body + bigEndian(Int(crc32(body)))
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }

    private static func bigEndian(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
