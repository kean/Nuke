// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import os

#if os(watchOS)
import WatchKit.WKInterfaceDevice
#endif

#if canImport(UIKit)
 import UIKit
 #endif

 #if canImport(AppKit)
 import AppKit
 #endif

extension PlatformImage {
    var processed: ImageProcessingExtensions {
        ImageProcessingExtensions(image: self)
    }
}

struct ImageProcessingExtensions {
    let image: PlatformImage

    func byResizing(to targetSize: CGSize,
                    contentMode: ImageProcessingOptions.ContentMode,
                    upscale: Bool) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
#if canImport(UIKit)
        let targetSize = targetSize.rotatedForOrientation(CGImagePropertyOrientation(image.imageOrientation))
#endif
        guard targetSize.isFinite else {
            return nil // Nothing to draw, and NaN would slip past the scale check
        }
        let scale = cgImage.size.getScale(targetSize: targetSize, contentMode: contentMode)
        guard scale < 1 || upscale else {
            return image // The image doesn't require scaling
        }
        let size = cgImage.size.scaled(by: scale).rounded()
        return image.draw(inCanvasWithSize: size)
    }

    /// Crops the input image to the given size and resizes it if needed.
    /// - note: if `upscale` is `false`, the image is never enlarged: it's
    /// cropped to the target aspect ratio at its native resolution instead.
    func byResizingAndCropping(to targetSize: CGSize, upscale: Bool) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
#if canImport(UIKit)
        let targetSize = targetSize.rotatedForOrientation(CGImagePropertyOrientation(image.imageOrientation))
#endif
        guard targetSize.isFinite else {
            return nil // Nothing to draw
        }
        var scale = cgImage.size.getScale(targetSize: targetSize, contentMode: .aspectFill)
        var canvasSize = targetSize
        if scale > 1 && !upscale {
            canvasSize = targetSize.scaled(by: 1 / scale).rounded()
            scale = 1
        }
        let scaledSize = cgImage.size.scaled(by: scale)
        let drawRect = scaledSize.centeredInRectWithSize(canvasSize)
        return image.draw(inCanvasWithSize: canvasSize, drawRect: drawRect)
    }

    func byDrawingInCircle(border: ImageProcessingOptions.Border?) -> PlatformImage? {
        guard let squared = byCroppingToSquare(), let cgImage = squared.cgImage else {
            return nil
        }
        let radius = CGFloat(cgImage.width) // Can use any dimension since image is a square
        return squared.processed.byAddingRoundedCorners(radius: radius / 2.0, border: border)
    }

    /// Draws an image in square by preserving an aspect ratio and filling the
    /// square if needed. If the image is already a square, returns an original image.
    func byCroppingToSquare() -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        guard cgImage.width != cgImage.height else {
            return image // Already a square
        }

        let imageSize = cgImage.size
        let side = min(cgImage.width, cgImage.height)
        let targetSize = CGSize(width: side, height: side)
        let cropRect = CGRect(origin: .zero, size: targetSize).offsetBy(
            dx: max(0, (imageSize.width - targetSize.width) / 2).rounded(.down),
            dy: max(0, (imageSize.height - targetSize.height) / 2).rounded(.down)
        )
        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return PlatformImage.make(cgImage: cropped, source: image)
    }

    /// Adds rounded corners with the given radius to the image.
    /// - parameter radius: Radius in pixels.
    /// - parameter border: Optional stroke border.
    func byAddingRoundedCorners(radius: CGFloat, border: ImageProcessingOptions.Border? = nil) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        guard let ctx = CGContext.make(cgImage, size: cgImage.size, alphaInfo: .premultipliedLast) else {
            return nil
        }
        let rect = CGRect(origin: CGPoint.zero, size: cgImage.size)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(cgImage, in: CGRect(origin: CGPoint.zero, size: cgImage.size))

        if let border {
            ctx.setStrokeColor(border.color.cgColor)
            ctx.addPath(path)
            ctx.setLineWidth(border.width)
            ctx.strokePath()
        }
        guard let outputCGImage = ctx.makeImage() else {
            return nil
        }
        return PlatformImage.make(cgImage: outputCGImage, source: image)
    }
}

extension PlatformImage {
    /// Draws the image in a `CGContext` in a canvas with the given size using
    /// the specified draw rect.
    ///
    /// For example, if the canvas size is `CGSize(width: 10, height: 10)` and
    /// the draw rect is `CGRect(x: -5, y: 0, width: 20, height: 10)` it would
    /// draw the input image (which is horizontal based on the known draw rect)
    /// in a square by centering it in the canvas.
    ///
    /// - parameter drawRect: `nil` by default. If `nil` will use the canvas rect.
    func draw(inCanvasWithSize canvasSize: CGSize, drawRect: CGRect? = nil) -> PlatformImage? {
        guard let cgImage else {
            return nil
        }
        guard let ctx = CGContext.make(cgImage, size: canvasSize) else {
            return nil
        }
        ctx.draw(cgImage, in: drawRect ?? CGRect(origin: .zero, size: canvasSize))
        guard let outputCGImage = ctx.makeImage() else {
            return nil
        }
        return PlatformImage.make(cgImage: outputCGImage, source: self)
    }

    /// Decompresses the input image by drawing in the `CGContext`.
    func decompressed(isUsingPrepareForDisplay: Bool) -> PlatformImage? {
#if os(iOS) || os(tvOS) || os(visionOS)
        if isUsingPrepareForDisplay, let image = preparingForDisplay() {
            return image
        }
#endif
        guard let cgImage else {
            return nil
        }
        return draw(inCanvasWithSize: cgImage.size, drawRect: CGRect(origin: .zero, size: cgImage.size))
    }
}

extension CGContext {
    static func make(_ image: CGImage, size: CGSize, alphaInfo: CGImageAlphaInfo? = nil) -> CGContext? {
        if let ctx = CGContext.make(image, size: size, alphaInfo: alphaInfo, colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB()) {
            return ctx
        }
        // In case the combination of parameters (color space, bits per component, etc)
        // is not supported by Core Graphics, switch to default context.
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        return CGContext.make(image, size: size, alphaInfo: alphaInfo, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    static func make(_ image: CGImage, size: CGSize, alphaInfo: CGImageAlphaInfo?, colorSpace: CGColorSpace) -> CGContext? {
        // The target sizes come straight from the user, e.g. from
        // `ImageProcessors.Resize`, and `Int(_:)` traps on the values that an
        // `Int` can't represent – NaN, infinity, and anything out of range.
        guard let width = size.width.pixelDimension,
              let height = size.height.pixelDimension else {
            return nil
        }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: (alphaInfo ?? preferredAlphaInfo(for: image, colorSpace: colorSpace)).rawValue
        )
    }

    /// - See https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html#//apple_ref/doc/uid/TP30001066-CH203-BCIBHHBB
    private static func preferredAlphaInfo(for image: CGImage, colorSpace: CGColorSpace) -> CGImageAlphaInfo {
        guard image.isOpaque else {
            return .premultipliedLast
        }
        if colorSpace.numberOfComponents == 1 && image.bitsPerPixel == 8 {
            return .none // The only pixel format supported for grayscale CS
        }
        return .noneSkipLast
    }
}

extension CGFloat {
    func converted(to unit: ImageProcessingOptions.Unit) -> CGFloat {
        switch unit {
        case .pixels: return self
        case .points: return self * Screen.scale
        }
    }

    /// Returns the value as a canvas dimension in pixels, or `nil` if it can't
    /// be represented by one because it's not finite, is out of range, or is
    /// too small to draw in. The comparisons are always `false` for NaN.
    var pixelDimension: Int? {
        // The upper bound is well above anything Core Graphics can allocate and
        // is only there to keep the conversion in range on 32-bit platforms.
        guard self >= 1, self <= 1_073_741_824 else {
            return nil
        }
        return Int(self)
    }
}

extension CGSize {
    /// Returns `true` if neither of the dimensions is NaN or infinite.
    var isFinite: Bool {
        width.isFinite && height.isFinite
    }

    func getScale(targetSize: CGSize, contentMode: ImageProcessingOptions.ContentMode) -> CGFloat {
        let scaleHor = targetSize.width / width
        let scaleVert = targetSize.height / height

        switch contentMode {
        case .aspectFill:
            return max(scaleHor, scaleVert)
        case .aspectFit:
            return min(scaleHor, scaleVert)
        }
    }

    /// Calculates a rect such that the output rect will be in the center of
    /// the rect of the input size (assuming origin: .zero)
    func centeredInRectWithSize(_ targetSize: CGSize) -> CGRect {
        // First, resize the original size to fill the target size.
        CGRect(origin: .zero, size: self).offsetBy(
            dx: -(width - targetSize.width) / 2,
            dy: -(height - targetSize.height) / 2
        )
    }
}

#if canImport(UIKit)
extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

extension UIImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}

#endif

extension CGSize {
    func rotatedForOrientation(_ imageOrientation: CGImagePropertyOrientation) -> CGSize {
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width) // Rotate 90 degrees
        case .up, .upMirrored, .down, .downMirrored:
            return self
        }
    }
}

#if os(macOS)
extension NSImage {
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    var ciImage: CIImage? {
        cgImage.map { CIImage(cgImage: $0) }
    }

    static func make(cgImage: CGImage, source: NSImage) -> NSImage {
        NSImage(cgImage: cgImage, size: .zero)
    }

    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }
}
#else
extension UIImage {
    static func make(cgImage: CGImage, source: UIImage) -> UIImage {
        UIImage(cgImage: cgImage, scale: source.scale, orientation: source.imageOrientation)
    }
}
#endif

extension CGImage {
    /// Returns `true` if the image doesn't contain alpha channel.
    var isOpaque: Bool {
        let alpha = alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }

    /// Draws the image at the given size, in pixels, with the orientation
    /// baked into the pixels it returns.
    ///
    /// What a renderer that can't orient an image as it decodes has to do:
    /// `CGImageSourceCreateImageAtIndex` hands back the pixels the way the
    /// container stores them, and the orientation it declares is a transform
    /// on top of them – the one Image I/O applies itself when it is asked for
    /// a thumbnail with `kCGImageSourceCreateThumbnailWithTransform`.
    ///
    /// - parameter size: The size to draw at, in pixels, before the
    /// orientation is applied. The image it returns is that size rotated, for
    /// the four orientations that turn a frame on its side.
    func drawn(inCanvasWithSize size: CGSize, orientation: CGImagePropertyOrientation) -> CGImage? {
        guard let context = CGContext.make(self, size: size.rotatedForOrientation(orientation)) else {
            return nil
        }
        context.concatenate(.orienting(orientation, size: size))
        context.draw(self, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}

private extension CGAffineTransform {
    /// The transform that displays an image of the given size, in pixels, the
    /// way the orientation says it must be: applied to a context of the
    /// rotated size, with the image drawn into `(0, 0, size)`.
    ///
    /// Each matrix maps the corners of the stored image onto the corners the
    /// EXIF orientation puts them at – the value names which edge row 0 and
    /// column 0 of the stored image end up on – in the y-up space a bitmap
    /// context draws in.
    static func orienting(_ orientation: CGImagePropertyOrientation, size: CGSize) -> CGAffineTransform {
        let (width, height) = (size.width, size.height)
        switch orientation {
        case .up: return .identity
        case .upMirrored: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
        case .down: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case .downMirrored: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        case .leftMirrored: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width)
        case .right: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        case .rightMirrored: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .left: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        }
    }
}

// MARK: - Geometry

// A rect or a direction means nothing on the stored pixels of a photo taken on
// its side, so these act on the image as it's displayed, unlike the resizing
// above, which can leave the orientation on the output.
//
// They draw rather than call `CGImage.cropping(to:)`. Its result keeps the whole
// input alive while the cache charges for the crop, and an image that isn't
// decoded yet stays that way until the main thread displays it, since the
// pipeline only decompresses what the decoder produced.
extension ImageProcessingExtensions {
    /// Crops the image to the given rect.
    ///
    /// - parameter rect: The rect in pixels, measured from the top-left corner
    /// of the image as it's displayed.
    func byCropping(to rect: CGRect) -> PlatformImage? {
        guard let size = displayedSize, rect.isFinite else {
            return nil
        }
        let bounds = CGRect(origin: .zero, size: size)
        let intersection = rect.intersection(bounds)
        guard !intersection.isEmpty else {
            return nil // There are no pixels in it
        }
        let crop = intersection.integral
        guard crop != bounds else {
            return image
        }
        // The y axis of a context points up, and the rect is measured from the
        // top, so it's the bottom of the rect that goes on the bottom of the canvas.
        return byDrawingDisplayedImage(
            inCanvasWithSize: crop.size,
            transform: CGAffineTransform(translationX: -crop.minX, y: crop.maxY - size.height)
        )
    }

    /// Mirrors the image as it's displayed.
    func byFlipping(_ direction: ImageProcessors.Flip.Direction) -> PlatformImage? {
        guard let size = displayedSize else {
            return nil
        }
        switch direction {
        case .horizontal:
            return byDrawingDisplayedImage(inCanvasWithSize: size, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0))
        case .vertical:
            return byDrawingDisplayedImage(inCanvasWithSize: size, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
        }
    }

    /// Rotates the image as it's displayed.
    ///
    /// - parameter degrees: The clockwise angle, in `0..<360`.
    func byRotating(degrees: CGFloat) -> PlatformImage? {
        guard let size = displayedSize, degrees.isFinite else {
            return nil
        }
        let (width, height) = (size.width, size.height)
        let turned = CGSize(width: height, height: width)
        // The quarter turns are spelled out so that they are exact, instead of
        // counting on Core Graphics to round away the error of `cos` and `sin`.
        switch degrees {
        case 0:
            return image
        case 90:
            return byDrawingDisplayedImage(inCanvasWithSize: turned, transform: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width))
        case 180:
            return byDrawingDisplayedImage(inCanvasWithSize: size, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height))
        case 270:
            return byDrawingDisplayedImage(inCanvasWithSize: turned, transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0))
        default:
            // The y axis of a context points up, so a clockwise turn is negative.
            let radians = -degrees * .pi / 180
            let box = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: radians))
            // The tolerance keeps the rounding error of `cos` and `sin` from
            // adding a pixel to a box that comes to a whole number.
            let canvas = CGSize(width: (box.width - 1e-6).rounded(.up), height: (box.height - 1e-6).rounded(.up))
            let transform = CGAffineTransform(translationX: canvas.width / 2, y: canvas.height / 2)
                .rotated(by: radians)
                .translatedBy(x: -width / 2, y: -height / 2)
            return byDrawingDisplayedImage(inCanvasWithSize: canvas, alphaInfo: .premultipliedLast, interpolationQuality: .high, transform: transform)
        }
    }

    /// Paints the color over the image, where the image isn't transparent.
    func byTinting(with color: PlatformColor) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let alphaInfo: CGImageAlphaInfo = cgImage.isOpaque ? .noneSkipLast : .premultipliedLast
        // The color has to survive the context, so a monochrome image doesn't
        // get a context of its own color space.
        var colorSpace = cgImage.colorSpace
        if colorSpace?.model != .rgb {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        let context = colorSpace.flatMap { CGContext.make(cgImage, size: cgImage.size, alphaInfo: alphaInfo, colorSpace: $0) }
        guard let ctx = context ?? CGContext.make(cgImage, size: cgImage.size, alphaInfo: alphaInfo, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
            return nil
        }
        let rect = CGRect(origin: .zero, size: cgImage.size)
        ctx.draw(cgImage, in: rect)
        ctx.setBlendMode(.sourceAtop)
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
        guard let outputCGImage = ctx.makeImage() else {
            return nil
        }
        return PlatformImage.make(cgImage: outputCGImage, source: image)
    }

    /// The orientation the image displays its stored pixels in. `NSImage` has
    /// none: it's in the pixels already.
    private var displayedOrientation: CGImagePropertyOrientation {
#if canImport(UIKit)
        CGImagePropertyOrientation(image.imageOrientation)
#else
        .up
#endif
    }

    /// The size of the image in pixels, as it's displayed.
    private var displayedSize: CGSize? {
        image.cgImage?.size.rotatedForOrientation(displayedOrientation)
    }

    /// Draws the image as it's displayed in a canvas of the given size, and
    /// returns it with the orientation baked into the pixels.
    ///
    /// - parameter transform: What to do to the image, which has its bottom-left
    /// corner at the origin of a context whose y axis points up.
    /// - parameter interpolationQuality: `.none` by default, for a transform
    /// that maps pixels to pixels.
    private func byDrawingDisplayedImage(
        inCanvasWithSize canvasSize: CGSize,
        alphaInfo: CGImageAlphaInfo? = nil,
        interpolationQuality: CGInterpolationQuality = .none,
        transform: CGAffineTransform
    ) -> PlatformImage? {
        guard let cgImage = image.cgImage,
              let ctx = CGContext.make(cgImage, size: canvasSize, alphaInfo: alphaInfo) else {
            return nil
        }
        ctx.interpolationQuality = interpolationQuality
        ctx.concatenate(transform)
        ctx.concatenate(.orienting(displayedOrientation, size: cgImage.size))
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: cgImage.size))
        guard let outputCGImage = ctx.makeImage() else {
            return nil
        }
#if canImport(UIKit)
        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: .up)
#else
        return PlatformImage.make(cgImage: outputCGImage, source: image)
#endif
    }
}

private extension CGRect {
    /// Returns `true` if none of the components is NaN or infinite.
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && size.isFinite
    }
}

extension CGSize {
    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }

    func rounded() -> CGSize {
        CGSize(width: CGFloat(round(width)), height: CGFloat(round(height)))
    }
}

enum Screen {
#if os(iOS) || os(tvOS)
    /// Returns the current screen scale. Never returns `0`.
    ///
    /// - note: `UITraitCollection.current` is only populated in the contexts
    /// managed by UIKit and its `displayScale` is `0` everywhere else, e.g. when
    /// a request is created on a background thread. That's why the scale has to
    /// be re-evaluated on every access with the last known valid value used as
    /// a fallback – caching it once would latch `0` for the entire lifetime of
    /// the process.
    static var scale: CGFloat {
        let scale = UITraitCollection.current.displayScale
        guard scale > 0 else {
            return lastKnownScale.withLock { $0 }
        }
        lastKnownScale.withLock { $0 = scale }
        return scale
    }

    private static let lastKnownScale = OSAllocatedUnfairLock<CGFloat>(initialState: 1)
#elseif os(watchOS)
    /// Returns the current screen scale. Never returns `0`.
    ///
    /// - note: unlike `UITraitCollection.current`, `WKInterfaceDevice` reports
    /// the scale of the device regardless of the context, so it's safe to cache.
    static let scale: CGFloat = max(1, WKInterfaceDevice.current().screenScale)
#else
    /// Always returns 1.
    static let scale: CGFloat = 1
#endif
}

#if os(macOS)
typealias Color = NSColor
#else
typealias Color = UIColor
#endif

extension Color {
    /// Returns a hex representation of the color, e.g. "#FFFFAA", or `nil` if
    /// the color has no sRGB representation, e.g. a pattern color.
    ///
    /// - note: The components are clamped to `0...1`. The colors in the
    /// extended sRGB space – which is what a P3 color converts to – have
    /// components outside of that range and would otherwise produce malformed
    /// hex, e.g. `"117"` for `1.093`.
    var hex: String? {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
#if os(macOS)
        // Unlike `UIColor`, `NSColor` doesn't convert the color on the fly and
        // raises an `NSInvalidArgumentException` if it's outside an RGB
        // colorspace – including the grays, e.g. `.black`, and the catalog
        // colors, e.g. `.labelColor`. `usingColorSpace(_:)` returns `nil` for
        // the colors that can't be converted at all, e.g. pattern colors.
        guard let color = usingColorSpace(.sRGB) else {
            return nil
        }
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
#else
        // Returns `false` and leaves the components untouched for the colors
        // with no RGB representation, e.g. pattern colors.
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return nil
        }
#endif
        let components = [r, g, b, a < 1 ? a : nil]
        return "#" + components
            .compactMap { $0 }
            .map { String(format: "%02lX", lroundf(Float(min(max($0, 0), 1)) * 255)) }
            .joined()
    }
}

/// Creates an image thumbnail. Uses significantly less memory than other options.
/// - parameter data: Data object from which to read the image.
/// - parameter options: Image loading options.
/// - parameter scale: The scale factor to assume when interpreting the image data, defaults to 1.
func makeThumbnail(data: Data, options: ImageRequest.ThumbnailOptions, scale: CGFloat = 1.0) -> PlatformImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
        return nil
    }
    return makeThumbnail(source: source, options: options, scale: scale)
}

/// Creates a thumbnail from the first image in the source, which can be an
/// incremental source with partially downloaded data.
func makeThumbnail(source: CGImageSource, options: ImageRequest.ThumbnailOptions, scale: CGFloat = 1.0) -> PlatformImage? {
    let maxPixelSize = getMaxPixelSize(for: source, options: options)
    let flags = options.options
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: flags.contains(.createThumbnailFromImageAlways),
        kCGImageSourceCreateThumbnailFromImageIfAbsent: flags.contains(.createThumbnailFromImageIfAbsent),
        kCGImageSourceShouldCacheImmediately: flags.contains(.shouldCacheImmediately),
        kCGImageSourceCreateThumbnailWithTransform: flags.contains(.createThumbnailWithTransform),
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize] as [CFString: Any]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    // When `createThumbnailWithTransform` is enabled, ImageIO already bakes
    // the EXIF orientation into the thumbnail pixels. Passing the original
    // orientation to UIImage would apply it a second time (double rotation).
    if flags.contains(.createThumbnailWithTransform) {
#if canImport(UIKit)
        return PlatformImage(cgImage: image, scale: scale, orientation: .up)
#else
        return PlatformImage(cgImage: image)
#endif
    }
    return makeImage(from: image, source: source, scale: scale)
}

/// Creates a `PlatformImage` from a `CGImage` produced by a `CGImageSource`,
/// reading EXIF orientation from the source properties.
func makeImage(from cgImage: CGImage, source: CGImageSource, scale: CGFloat = 1.0) -> PlatformImage {
#if canImport(UIKit)
    var orientation: UIImage.Orientation = .up
    if let imageProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [AnyHashable: Any],
       let orientationValue = imageProperties[kCGImagePropertyOrientation as String] as? UInt32,
       let cgOrientation = CGImagePropertyOrientation(rawValue: orientationValue) {
        orientation = UIImage.Orientation(cgOrientation)
    }
    return PlatformImage(cgImage: cgImage, scale: scale, orientation: orientation)
#else
    return PlatformImage(cgImage: cgImage)
#endif
}

func getMaxPixelSize(for source: CGImageSource, options thumbnailOptions: ImageRequest.ThumbnailOptions) -> CGFloat {
    guard thumbnailOptions.options.contains(.flexible) else {
        return CGFloat(thumbnailOptions.size.width)
    }
    var targetSize = thumbnailOptions.size.cgSize
    let contentMode = thumbnailOptions.contentMode
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
          let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
        return max(targetSize.width, targetSize.height)
    }
    let orientation = (properties[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init) ?? .up
#if canImport(UIKit)
    targetSize = targetSize.rotatedForOrientation(orientation)
#endif
    let imageSize = CGSize(width: width, height: height)
    let scale = imageSize.getScale(targetSize: targetSize, contentMode: contentMode)
    let size = imageSize.scaled(by: scale).rounded()
    return max(size.width, size.height)
}
