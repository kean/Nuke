// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Nuke
import Testing

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Reading Pixels

/// Reads the image into a known RGBA (premultiplied last) bitmap so that the
/// individual pixels can be inspected regardless of the source color space.
struct RGBABitmap: Equatable {
    let width: Int
    let height: Int

    /// The components of every pixel, row by row from the top: red, green,
    /// blue, and alpha.
    let bytes: [UInt8]

    private var bytesPerRow: Int { width * 4 }

    init?(image: PlatformImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }

    init?(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let isSuccess = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard isSuccess else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func red(atX x: Int, y: Int) -> UInt8 {
        bytes[y * bytesPerRow + x * 4]
    }

    func alpha(atX x: Int, y: Int) -> UInt8 {
        bytes[y * bytesPerRow + x * 4 + 3]
    }

    /// Returns the color components of the pixel, without the alpha.
    func color(atX x: Int, y: Int) -> PixelColor {
        let offset = y * bytesPerRow + x * 4
        return PixelColor(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
    }

    /// Returns the red, green, blue, and alpha components of the pixel.
    func pixel(atX x: Int, y: Int) -> [UInt8] {
        let offset = y * bytesPerRow + x * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}

/// The color components of a pixel, compared with a tolerance for resampling.
struct PixelColor: CustomStringConvertible {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    func isClose(to other: PixelColor) -> Bool {
        abs(Int(red) - Int(other.red)) <= 8 &&
        abs(Int(green) - Int(other.green)) <= 8 &&
        abs(Int(blue) - Int(other.blue)) <= 8
    }

    var description: String { "(\(red), \(green), \(blue))" }
}

/// Returns the RGBA components of every pixel of the image, row by row, read
/// in the device RGB space.
func pixels(of image: PlatformImage) throws -> [UInt8] {
    try #require(RGBABitmap(image: image)).bytes
}

/// Returns the RGBA components of the pixel, read in the device RGB space.
func pixelComponents(of image: PlatformImage, x: Int, y: Int) throws -> [UInt8] {
    try #require(RGBABitmap(image: image)).pixel(atX: x, y: y)
}

extension Test {
    /// The RGBA components of the top-left pixel, which is what tells apart
    /// images of one solid color each, such as the frames of the generated
    /// animations.
    static func firstPixel(of image: PlatformImage?) -> [UInt8]? {
        guard let cgImage = image?.cgImage else { return nil }
        return firstPixel(of: cgImage)
    }

    static func firstPixel(of image: CGImage) -> [UInt8]? {
        RGBABitmap(cgImage: image)?.pixel(atX: 0, y: 0)
    }
}

// MARK: - Drawing Images

extension Test {
    /// An image of the given pixel format filled with a solid color, or `nil`
    /// if Core Graphics has no context for the format.
    static func makeImage(
        width: Int,
        height: Int,
        bitsPerComponent: Int = 8,
        colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB(),
        alphaInfo: CGImageAlphaInfo = .premultipliedLast,
        color: CGColor
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Returns a transparent image with an opaque blue square in the middle.
    static func imageWithOpaqueSquare(size: Int, square: Int) -> PlatformImage {
        let context = makeRGBAContext(width: size, height: size, alphaInfo: .premultipliedLast)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let origin = (size - square) / 2
        context.fill(CGRect(x: origin, y: origin, width: square, height: square))
        return platformImage(context.makeImage()!)
    }

    /// Returns an opaque image made of solid red, green, and blue stripes of
    /// equal size, in that order.
    static func stripedImage(width: Int, height: Int, isVertical: Bool) -> PlatformImage {
        let context = makeRGBAContext(width: width, height: height, alphaInfo: .noneSkipLast)
        let colors = [
            CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        ]
        for (index, color) in colors.enumerated() {
            context.setFillColor(color)
            if isVertical {
                let stripe = width / colors.count
                context.fill(CGRect(x: index * stripe, y: 0, width: stripe, height: height))
            } else {
                let stripe = height / colors.count
                context.fill(CGRect(x: 0, y: index * stripe, width: width, height: stripe))
            }
        }
        return platformImage(context.makeImage()!)
    }

    /// Wraps the bitmap in a platform image of one point to a pixel.
    static func platformImage(_ cgImage: CGImage) -> PlatformImage {
#if os(macOS)
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
#else
        UIImage(cgImage: cgImage)
#endif
    }

    private static func makeRGBAContext(width: Int, height: Int, alphaInfo: CGImageAlphaInfo) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        )!
    }
}
