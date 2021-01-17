// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

#if os(watchOS)
import WatchKit
#endif

#if os(macOS)
import Cocoa
#endif

// MARK: - ImageProcessing

/// Performs image processing.
///
/// For basic processing needs, implement the following method:
///
/// ```
/// func process(image: PlatformImage) -> PlatformImage?
/// ```
///
/// If your processor needs to manipulate image metadata (`ImageContainer`), or
/// get access to more information via the context (`ImageProcessingContext`),
/// there is an additional method that allows you to do that:
///
/// ```
/// func process(image container: ImageContainer, context: ImageProcessingContext) -> ImageContainer?
/// ```
///
/// You must implement either one of those methods.
public protocol ImageProcessing {
    /// Returns a processed image. By default, returns `nil`.
    ///
    /// - note: Gets called a background queue managed by the pipeline.
    func process(_ image: PlatformImage) -> PlatformImage?

    /// Returns a processed image. By default, this calls the basic `process(image:)` method.
    ///
    /// - note: Gets called a background queue managed by the pipeline.
    func process(_ container: ImageContainer, context: ImageProcessingContext) -> ImageContainer?

    /// Returns a string that uniquely identifies the processor.
    ///
    /// Consider using the reverse DNS notation.
    var identifier: String { get }

    /// Returns a unique processor identifier.
    ///
    /// The default implementation simply returns `var identifier: String` but
    /// can be overridden as a performance optimization - creating and comparing
    /// strings is _expensive_ so you can opt-in to return something which is
    /// fast to create and to compare. See `ImageProcessors.Resize` for an example.
    ///
    /// - note: A common approach is to make your processor `Hashable` and return `self`
    /// from `hashableIdentifier`.
    var hashableIdentifier: AnyHashable { get }
}

public extension ImageProcessing {
    /// The default implementation simply calls the basic
    /// `process(_ image: PlatformImage) -> PlatformImage?` method.
    func process(_ container: ImageContainer, context: ImageProcessingContext) -> ImageContainer? {
        container.map(process)
    }

    /// The default impleemntation simply returns `var identifier: String`.
    var hashableIdentifier: AnyHashable { identifier }
}

/// Image processing context used when selecting which processor to use.
public struct ImageProcessingContext {
    public let request: ImageRequest
    public let response: ImageResponse
    public let isFinal: Bool

    public init(request: ImageRequest, response: ImageResponse, isFinal: Bool) {
        self.request = request
        self.response = response
        self.isFinal = isFinal
    }
}

// MARK: - ImageProcessors

/// A namespace for all processors that implement `ImageProcessing` protocol.
public enum ImageProcessors {}

// MARK: - ImageProcessors.Resize

extension ImageProcessors {
    /// Scales an image to a specified size.
    public struct Resize: ImageProcessing, Hashable, CustomStringConvertible {
        private let size: Size
        private let contentMode: ContentMode
        private let crop: Bool
        private let upscale: Bool

        /// An option for how to resize the image.
        public enum ContentMode: CustomStringConvertible {
            /// Scales the image so that it completely fills the target area.
            /// Maintains the aspect ratio of the original image.
            case aspectFill

            /// Scales the image so that it fits the target size. Maintains the
            /// aspect ratio of the original image.
            case aspectFit

            public var description: String {
                switch self {
                case .aspectFill: return ".aspectFill"
                case .aspectFit: return ".aspectFit"
                }
            }
        }

        /// Initializes the processor with the given size.
        ///
        /// - parameter size: The target size.
        /// - parameter unit: Unit of the target size, `.points` by default.
        /// - parameter contentMode: `.aspectFill` by default.
        /// - parameter crop: If `true` will crop the image to match the target size.
        /// Does nothing with content mode .aspectFill. `false` by default.
        /// - parameter upscale: `false` by default.
        public init(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ContentMode = .aspectFill, crop: Bool = false, upscale: Bool = false) {
            self.size = Size(cgSize: CGSize(size: size, unit: unit))
            self.contentMode = contentMode
            self.crop = crop
            self.upscale = upscale
        }

        /// Resizes the image to the given width preserving aspect ratio.
        ///
        /// - parameter unit: Unit of the target size, `.points` by default.
        public init(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) {
            self.init(size: CGSize(width: width, height: 9999), unit: unit, contentMode: .aspectFit, crop: false, upscale: upscale)
        }

        /// Resizes the image to the given height preserving aspect ratio.
        ///
        /// - parameter unit: Unit of the target size, `.points` by default.
        public init(height: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) {
            self.init(size: CGSize(width: 9999, height: height), unit: unit, contentMode: .aspectFit, crop: false, upscale: upscale)
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            if crop && contentMode == .aspectFill {
                return image.processed.byResizingAndCropping(to: size.cgSize)
            } else {
                return image.processed.byResizing(to: size.cgSize, contentMode: contentMode, upscale: upscale)
            }
        }

        public var identifier: String {
            "com.github.kean/nuke/resize?s=\(size.cgSize),cm=\(contentMode),crop=\(crop),upscale=\(upscale)"
        }

        public var hashableIdentifier: AnyHashable { self }

        public var description: String {
            "Resize(size: \(size.cgSize) pixels, contentMode: \(contentMode), crop: \(crop), upscale: \(upscale))"
        }
    }
}

// MARK: - ImageProcessors.Circle

extension ImageProcessors {

    /// Rounds the corners of an image into a circle. If the image is not a square,
    /// crops it to a square first.
    public struct Circle: ImageProcessing, Hashable, CustomStringConvertible {
        private let border: ImageProcessingOptions.Border?

        public init(border: ImageProcessingOptions.Border? = nil) {
            self.border = border
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            image.processed.byDrawingInCircle(border: border)
        }

        public var identifier: String {
            if let border = self.border {
                return "com.github.kean/nuke/circle?border=\(border)"
            } else {
                return "com.github.kean/nuke/circle"
            }
        }

        public var hashableIdentifier: AnyHashable { self }

        public var description: String {
            "Circle(border: \(border?.description ?? "nil"))"
        }
    }
}

// MARK: - ImageProcessors.RoundedCorners

extension ImageProcessors {
    /// Rounds the corners of an image to the specified radius.
    ///
    /// - warning: In order for the corners to be displayed correctly, the image must exactly match the size
    /// of the image view in which it will be displayed. See `ImageProcessor.Resize` for more info.
    public struct RoundedCorners: ImageProcessing, Hashable, CustomStringConvertible {
        private let radius: CGFloat
        private let border: ImageProcessingOptions.Border?

        /// Initializes the processor with the given radius.
        ///
        /// - parameter radius: The radius of the corners.
        /// - parameter unit: Unit of the radius, `.points` by default.
        /// - parameter border: An optional border drawn around the image.
        public init(radius: CGFloat, unit: ImageProcessingOptions.Unit = .points, border: ImageProcessingOptions.Border? = nil) {
            self.radius = radius.converted(to: unit)
            self.border = border
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            image.processed.byAddingRoundedCorners(radius: radius, border: border)
        }

        public var identifier: String {
            if let border = self.border {
                return "com.github.kean/nuke/rounded_corners?radius=\(radius),border=\(border)"
            } else {
                return "com.github.kean/nuke/rounded_corners?radius=\(radius)"
            }
        }

        public var hashableIdentifier: AnyHashable { self }

        public var description: String {
            "RoundedCorners(radius: \(radius) pixels, border: \(border?.description ?? "nil"))"
        }
    }
}

#if os(iOS) || os(tvOS) || os(macOS)

// MARK: - ImageProcessors.CoreImageFilter

import CoreImage

extension ImageProcessors {

    /// Applies Core Image filter (`CIFilter`) to the image.
    ///
    /// # Performance Considerations.
    ///
    /// Prefer chaining multiple `CIFilter` objects using `Core Image` facilities
    /// instead of using multiple instances of `ImageProcessors.CoreImageFilter`.
    ///
    /// # References
    ///
    /// - [Core Image Programming Guide](https://developer.apple.com/library/ios/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html)
    /// - [Core Image Filter Reference](https://developer.apple.com/library/prerelease/ios/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html)
    public struct CoreImageFilter: ImageProcessing, CustomStringConvertible {
        private let name: String
        private let parameters: [String: Any]
        public let identifier: String

        /// - parameter identifier: Uniquely identifies the processor.
        public init(name: String, parameters: [String: Any], identifier: String) {
            self.name = name
            self.parameters = parameters
            self.identifier = identifier
        }

        public init(name: String) {
            self.name = name
            self.parameters = [:]
            self.identifier = "com.github.kean/nuke/core_image?name=\(name))"
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            let filter = CIFilter(name: name, parameters: parameters)
            return CoreImageFilter.apply(filter: filter, to: image)
        }

        // MARK: - Apply Filter

        /// A default context shared between all Core Image filters. The context
        /// has `.priorityRequestLow` option set to `true`.
        public static var context = CIContext(options: [.priorityRequestLow: true])

        public static func apply(filter: CIFilter?, to image: PlatformImage) -> PlatformImage? {
            guard let filter = filter else {
                return nil
            }
            return applyFilter(to: image) {
                filter.setValue($0, forKey: kCIInputImageKey)
                return filter.outputImage
            }
        }

        static func applyFilter(to image: PlatformImage, context: CIContext = context, closure: (CoreImage.CIImage) -> CoreImage.CIImage?) -> PlatformImage? {
            let ciImage: CoreImage.CIImage? = {
                if let image = image.ciImage {
                    return image
                }
                if let image = image.cgImage {
                    return CoreImage.CIImage(cgImage: image)
                }
                return nil
            }()
            guard let inputImage = ciImage, let outputImage = closure(inputImage) else {
                return nil
            }
            guard let imageRef = context.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
            }
            return PlatformImage.make(cgImage: imageRef, source: image)
        }

        public var description: String {
            "CoreImageFilter(name: \(name), parameters: \(parameters))"
        }
    }
}

// MARK: - ImageProcessors.GaussianBlur

extension ImageProcessors {
    /// Blurs an image using `CIGaussianBlur` filter.
    public struct GaussianBlur: ImageProcessing, Hashable, CustomStringConvertible {
        private let radius: Int

        /// Initializes the receiver with a blur radius.
        public init(radius: Int = 8) {
            self.radius = radius
        }

        /// Applies `CIGaussianBlur` filter to the image.
        public func process(_ image: PlatformImage) -> PlatformImage? {
            let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": radius])
            return CoreImageFilter.apply(filter: filter, to: image)
        }

        public var identifier: String {
            "com.github.kean/nuke/gaussian_blur?radius=\(radius)"
        }

        public var hashableIdentifier: AnyHashable { self }

        public var description: String {
            "GaussianBlur(radius: \(radius))"
        }
    }
}

#endif

// MARK: - ImageDecompression (Internal)

struct ImageDecompression {

    static func decompress(image: PlatformImage) -> PlatformImage {
        let output = image.decompressed() ?? image
        ImageDecompression.setDecompressionNeeded(false, for: output)
        return output
    }

    // MARK: Managing Decompression State

    static var isDecompressionNeededAK = "ImageDecompressor.isDecompressionNeeded.AssociatedKey"

    static func setDecompressionNeeded(_ isDecompressionNeeded: Bool, for image: PlatformImage) {
        objc_setAssociatedObject(image, &isDecompressionNeededAK, isDecompressionNeeded, .OBJC_ASSOCIATION_RETAIN)
    }

    static func isDecompressionNeeded(for image: PlatformImage) -> Bool? {
        objc_getAssociatedObject(image, &isDecompressionNeededAK) as? Bool
    }
}

// MARK: - ImageProcessors.Composition

extension ImageProcessors {
    /// Composes multiple processors.
    public struct Composition: ImageProcessing, Hashable, CustomStringConvertible {
        let processors: [ImageProcessing]

        /// Composes multiple processors.
        public init(_ processors: [ImageProcessing]) {
            // note: multiple compositions are not flatten by default.
            self.processors = processors
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            processors.reduce(image) { image, processor in
                autoreleasepool {
                    image.flatMap { processor.process($0) }
                }
            }
        }

        /// Processes the given image by applying each processor in an order in
        /// which they were added. If one of the processors fails to produce
        /// an image the processing stops and `nil` is returned.
        public func process(_ container: ImageContainer, context: ImageProcessingContext) -> ImageContainer? {
            processors.reduce(container) { container, processor in
                autoreleasepool {
                    container.flatMap { processor.process($0, context: context) }
                }
            }
        }

        public var identifier: String {
            processors.map({ $0.identifier }).joined()
        }

        public var hashableIdentifier: AnyHashable { self }

        public func hash(into hasher: inout Hasher) {
            for processor in processors {
                hasher.combine(processor.hashableIdentifier)
            }
        }

        public static func == (lhs: Composition, rhs: Composition) -> Bool {
            lhs.processors == rhs.processors
        }

        public var description: String {
            "Composition(processors: \(processors))"
        }
    }
}

// MARK: - ImageProcessors.Anonymous

extension ImageProcessors {
    /// Processed an image using a specified closure.
    public struct Anonymous: ImageProcessing, CustomStringConvertible {
        public let identifier: String
        private let closure: (PlatformImage) -> PlatformImage?

        public init(id: String, _ closure: @escaping (PlatformImage) -> PlatformImage?) {
            self.identifier = id
            self.closure = closure
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            self.closure(image)
        }

        public var description: String {
            "AnonymousProcessor(identifier: \(identifier)"
        }
    }
}

// MARK: - Image Processing (Internal)

private extension PlatformImage {
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
        guard let cgImage = cgImage else {
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

    /// Decompresses the input image by drawing in the the `CGContext`.
    func decompressed() -> PlatformImage? {
        guard let cgImage = cgImage else {
            return nil
        }
        return draw(inCanvasWithSize: cgImage.size, drawRect: CGRect(origin: .zero, size: cgImage.size))
    }
}

// MARK: - ImageProcessingExtensions

private extension PlatformImage {
    var processed: ImageProcessingExtensions {
        ImageProcessingExtensions(image: self)
    }
}

private struct ImageProcessingExtensions {
    let image: PlatformImage

    func byResizing(to targetSize: CGSize,
                    contentMode: ImageProcessors.Resize.ContentMode,
                    upscale: Bool) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        #if os(iOS) || os(tvOS) || os(watchOS)
        let targetSize = targetSize.rotatedForOrientation(image.imageOrientation)
        #endif
        let scale = cgImage.size.getScale(targetSize: targetSize, contentMode: contentMode)
        guard scale < 1 || upscale else {
            return image // The image doesn't require scaling
        }
        let size = cgImage.size.scaled(by: scale).rounded()
        return image.draw(inCanvasWithSize: size)
    }

    /// Crops the input image to the given size and resizes it if needed.
    /// - note: this method will always upscale.
    func byResizingAndCropping(to targetSize: CGSize) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        #if os(iOS) || os(tvOS) || os(watchOS)
        let targetSize = targetSize.rotatedForOrientation(image.imageOrientation)
        #endif
        let scale = cgImage.size.getScale(targetSize: targetSize, contentMode: .aspectFill)
        let scaledSize = cgImage.size.scaled(by: scale)
        let drawRect = scaledSize.centeredInRectWithSize(targetSize)
        return image.draw(inCanvasWithSize: targetSize, drawRect: drawRect)
    }

    func byDrawingInCircle(border: ImageProcessingOptions.Border?) -> PlatformImage? {
        guard let squared = byCroppingToSquare(), let cgImage = squared.cgImage else {
            return nil
        }
        let radius = CGFloat(cgImage.width) / 2.0 // Can use any dimension since image is a square
        return squared.processed.byAddingRoundedCorners(radius: radius, border: border)
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
            dx: max(0, (imageSize.width - targetSize.width) / 2),
            dy: max(0, (imageSize.height - targetSize.height) / 2)
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

        if let border = border {
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

// MARK: - CoreGraphics Helpers (Internal)

#if os(macOS)
typealias Color = NSColor
#else
typealias Color = UIColor
#endif

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
}

private extension CGFloat {
    func converted(to unit: ImageProcessingOptions.Unit) -> CGFloat {
        switch unit {
        case .pixels: return self
        case .points: return self * Screen.scale
        }
    }
}

// Adds Hashable without making changes to public CGSize API
private struct Size: Hashable {
    let cgSize: CGSize

    func hash(into hasher: inout Hasher) {
        hasher.combine(cgSize.width)
        hasher.combine(cgSize.height)
    }
}

private extension CGSize {
    /// Creates the size in pixels by scaling to the input size to the screen scale
    /// if needed.
    init(size: CGSize, unit: ImageProcessingOptions.Unit) {
        switch unit {
        case .pixels: self = size // The size is already in pixels
        case .points: self = size.scaled(by: Screen.scale)
        }
    }

    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }

    func rounded() -> CGSize {
        CGSize(width: CGFloat(round(width)), height: CGFloat(round(height)))
    }
}

#if os(iOS) || os(tvOS) || os(watchOS)
private extension CGSize {
    func rotatedForOrientation(_ imageOrientation: UIImage.Orientation) -> CGSize {
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width) // Rotate 90 degrees
        case .up, .upMirrored, .down, .downMirrored:
            return self
        @unknown default:
            return self
        }
    }
}
#endif

extension CGSize {
    func getScale(targetSize: CGSize, contentMode: ImageProcessors.Resize.ContentMode) -> CGFloat {
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

// MARK: - ImageProcessing Extensions (Internal)

func == (lhs: [ImageProcessing], rhs: [ImageProcessing]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    // Lazily creates `hashableIdentifiers` because for some processors the
    // identifiers might be expensive to compute.
    return zip(lhs, rhs).allSatisfy {
        $0.hashableIdentifier == $1.hashableIdentifier
    }
}

// MARK: - ImageProcessingOptions

public enum ImageProcessingOptions {

    public enum Unit: CustomStringConvertible {
        case points
        case pixels

        public var description: String {
            switch self {
            case .points: return "points"
            case .pixels: return "pixels"
            }
        }
    }

    #if os(iOS) || os(tvOS) || os(watchOS)

    /// Draws a border.
    ///
    /// - warning: To make sure that the border looks the way you expect,
    /// make sure that the images you display exactly match the size of the
    /// views in which they get displayed. If you can't guarantee that, pleasee
    /// consider adding border to a view layer. This should be your primary
    /// option regardless.
    public struct Border: Hashable, CustomStringConvertible {
        public let color: UIColor
        public let width: CGFloat

        /// - parameter color: Border color.
        /// - parameter width: Border width. 1 points by default.
        /// - parameter unit: Unit of the width, `.points` by default.
        public init(color: UIColor, width: CGFloat = 1, unit: Unit = .points) {
            self.color = color
            self.width = width.converted(to: unit)
        }

        public var description: String {
            "Border(color: \(color.hex), width: \(width) pixels)"
        }
    }

    #else

    /// Draws a border.
    ///
    /// - warning: To make sure that the border looks the way you expect,
    /// make sure that the images you display exactly match the size of the
    /// views in which they get displayed. If you can't guarantee that, pleasee
    /// consider adding border to a view layer. This should be your primary
    /// option regardless.
    public struct Border: Hashable, CustomStringConvertible { // Duplicated to avoid introducing PlatformColor
        public let color: NSColor
        public let width: CGFloat

        /// - parameter color: Border color.
        /// - parameter width: Border width. 1 points by default.
        /// - parameter unit: Unit of the width, `.points` by default.
        public init(color: NSColor, width: CGFloat = 1, unit: Unit = .points) {
            self.color = color
            self.width = width.converted(to: unit)
        }

        public var description: String {
            "Border(color: \(color.hex), width: \(width) pixels)"
        }
    }

    #endif
}

// MARK: - Misc (Internal)

struct Screen {
    #if os(iOS) || os(tvOS)
    /// Returns the current screen scale.
    static var scale: CGFloat { UIScreen.main.scale }
    #elseif os(watchOS)
    /// Returns the current screen scale.
    static var scale: CGFloat { WKInterfaceDevice.current().screenScale }
    #elseif os(macOS)
    /// Always returns 1.
    static var scale: CGFloat { 1 }
    #endif
}

extension Color {
    /// Returns a hex representation of the color, e.g. "#FFFFAA".
    var hex: String {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let components = [r, g, b, a < 1 ? a : nil]
        return "#" + components
            .compactMap { $0 }
            .map { String(format: "%02lX", lroundf(Float($0) * 255)) }
            .joined()
    }
}

private extension CGContext {
    static func make(_ image: CGImage, size: CGSize, alphaInfo: CGImageAlphaInfo? = nil) -> CGContext? {
        let alphaInfo: CGImageAlphaInfo = alphaInfo ?? (image.isOpaque ? .noneSkipLast : .premultipliedLast)

        // Create the context which matches the input image.
        if let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) {
            return ctx
        }

        // In case the combination of parameters (color space, bits per component, etc)
        // is nit supported by Core Graphics, switch to default context.
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        return CGContext(
            data: nil,
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        )
    }
}
