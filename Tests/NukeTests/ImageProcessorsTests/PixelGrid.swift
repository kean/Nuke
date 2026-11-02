// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The RGBA pixels of an image, top row first, with every pixel different in
/// the images it generates, so that a pixel in the wrong place can't go
/// unnoticed. The geometry tests work out what a processor should produce on
/// the array, and compare.
struct PixelGrid: Equatable, CustomStringConvertible {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// Generates an image with a different color in every pixel.
    ///
    /// - parameter isOpaque: If `false`, the alpha varies too.
    init(width: Int, height: Int, isOpaque: Bool = true) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let alpha = isOpaque ? 255 : 255 - (x + y * width) * 8 % 200
                // Premultiplied, so the color can't be above the alpha.
                bytes += [UInt8(min((40 + x * 13) % 256, alpha)), UInt8(min((40 + y * 17) % 256, alpha)), 50, UInt8(alpha)]
            }
        }
        self.init(width: width, height: height, bytes: bytes)
    }

    /// The pixels as stored, which ignores the orientation of the image.
    init(storedPixelsOf image: PlatformImage) throws {
        let bitmap = try #require(RGBABitmap(image: image))
        self.init(width: bitmap.width, height: bitmap.height, bytes: bitmap.bytes)
    }

    /// The pixels on screen: the platform draws the image, and the
    /// implementation of the orientation is its own, not the processors'.
    init(displayedPixelsOf image: PlatformImage) throws {
#if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
        try self.init(storedPixelsOf: rendered)
#else
        let cgImage = try #require(image.cgImage)
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: cgImage.width,
            pixelsHigh: cgImage.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        NSGraphicsContext.restoreGraphicsState()
        let rendered = try #require(representation.cgImage)
        let bitmap = try #require(RGBABitmap(cgImage: rendered))
        self.init(width: bitmap.width, height: bitmap.height, bytes: bitmap.bytes)
#endif
    }

    func makeCGImage() -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    func makeImage() -> PlatformImage {
        Test.platformImage(makeCGImage())
    }

    func pixel(x: Int, y: Int) -> ArraySlice<UInt8> {
        let offset = (y * width + x) * 4
        return bytes[offset..<(offset + 4)]
    }

    private func mapped(width: Int, height: Int, _ source: (_ x: Int, _ y: Int) -> (x: Int, y: Int)) -> PixelGrid {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let origin = source(x, y)
                bytes += pixel(x: origin.x, y: origin.y)
            }
        }
        return PixelGrid(width: width, height: height, bytes: bytes)
    }

    func cropped(x originX: Int, y originY: Int, width: Int, height: Int) -> PixelGrid {
        mapped(width: width, height: height) { x, y in (x + originX, y + originY) }
    }

    var flippedHorizontally: PixelGrid {
        mapped(width: width, height: height) { [width] x, y in (width - 1 - x, y) }
    }

    var flippedVertically: PixelGrid {
        mapped(width: width, height: height) { [height] x, y in (x, height - 1 - y) }
    }

    var rotatedClockwise: PixelGrid {
        mapped(width: height, height: width) { [height] x, y in (y, height - 1 - x) }
    }

    /// Returns `true` if the pixels match within a tolerance, for comparing
    /// what went through a color conversion on the way out.
    func isClose(to other: PixelGrid, tolerance: Int = 2) -> Bool {
        guard width == other.width, height == other.height else { return false }
        return zip(bytes, other.bytes).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
    }

    var description: String { "PixelGrid(\(width)x\(height))" }
}

extension Test {
    /// A grayscale image with an alpha channel. Core Graphics reads the format
    /// but has no context for it.
    static func grayscaleWithAlphaImage(width: Int, height: Int, gray: UInt8 = 100, alpha: UInt8 = 128) -> PlatformImage {
        var bytes = [UInt8]()
        for _ in 0..<(width * height) {
            bytes += [min(gray, alpha), alpha]
        }
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 16,
            bytesPerRow: width * 2,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return platformImage(cgImage)
    }
}

#if canImport(UIKit)
/// Every orientation an image can carry, for the tests that compare the output
/// with what the platform draws.
let allOrientations: [UIImage.Orientation] = [.up, .upMirrored, .down, .downMirrored, .left, .leftMirrored, .right, .rightMirrored]
#endif
