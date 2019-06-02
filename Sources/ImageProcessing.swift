// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Performs image processing.
public protocol ImageProcessing {
    /// Returns processed image.
    func process(image: Image, context: ImageProcessingContext?) -> Image?

    /// Returns a string which uniquely identifies the processor.
    var identifier: String { get }

    /// Returns a unique processor identifier.
    ///
    /// The default implementation simply returns `var identifier: String` but
    /// can be overridden as a performance optimization - creating and comparing
    /// strings is _expensive_ so you can opt-in to return something which is
    /// fast to create and to compare. See `ImageProcessor.Resize` to example.
    var hashableIdentifier: AnyHashable { get }
}

extension ImageProcessing {
    public func process(image: Image) -> Image? {
        return self.process(image: image, context: nil)
    }
}

public extension ImageProcessing {
    var hashableIdentifier: AnyHashable {
        return identifier
    }
}

/// Image processing context used when selecting which processor to use.
public struct ImageProcessingContext {
    public let request: ImageRequest
    public let isFinal: Bool
    public let scanNumber: Int? // need a more general purpose way to implement this
}

// MARK: - ImageProcessor

public enum ImageProcessor {}

// MARK: - ImageProcessor.Anonymous

extension ImageProcessor {
    public struct Anonymous: ImageProcessing {
        public let identifier: String
        private let closure: (Image) -> Image?

        public init(id: String, _ closure: @escaping (Image) -> Image?) {
            self.identifier = id
            self.closure = closure
        }

        public func process(image: Image, context: ImageProcessingContext?) -> Image? {
            return self.closure(image)
        }
    }
}

// MARK: - ImageProcessor.Composition

extension ImageProcessor {
    /// Composes multiple processors.
    public struct Composition: ImageProcessing, Hashable {
        let processors: [ImageProcessing]

        /// Composes multiple processors.
        public init(_ processors: [ImageProcessing]) {
            self.processors = processors
        }

        /// Processes the given image by applying each processor in an order in
        /// which they were added. If one of the processors fails to produce
        /// an image the processing stops and `nil` is returned.
        public func process(image: Image, context: ImageProcessingContext?) -> Image? {
            return processors.reduce(image) { image, processor in
                return autoreleasepool {
                    image.flatMap { processor.process(image: $0, context: context) }
                }
            }
        }

        public var identifier: String {
            return processors.map({ $0.identifier }).joined()
        }

        public var hashableIdentifier: AnyHashable {
            return self
        }

        public func hash(into hasher: inout Hasher) {
            for processor in processors {
                hasher.combine(processor.hashableIdentifier)
            }
        }

        public static func == (lhs: Composition, rhs: Composition) -> Bool {
            return lhs.processors == rhs.processors
        }
    }
}


#if os(watchOS)
import WatchKit
#endif

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit

// MARK: - ImageProcessor.Resize

extension ImageProcessor {

    public enum Unit {
        case points
        case pixels
    }

    public struct Resize: ImageProcessing, Hashable {

        private let size: CGSize
        private let contentMode: ContentMode
        private let upscale: Bool

        /// An option for how to resize the image.
        public enum ContentMode {
            /// Scales the image so that it completely fills the target size.
            /// Doesn't clip images.
            case aspectFill

            /// Scales the image so that it fits the target size.
            case aspectFit
        }

        /// Initializes the resizing image processor.
        ///
        /// - parameter size: The target reference size.
        /// - parameter unit: `.points` by default.
        /// - parameter upscale: `false` by default.
        public init(size: CGSize, unit: Unit = .points, contentMode: ContentMode = .aspectFill, upscale: Bool = false) {
            self.size = CGSize(size: size, unit: unit)
            self.contentMode = contentMode
            self.upscale = upscale
        }

        public func process(image: Image, context: ImageProcessingContext?) -> Image? {
            return image.processed.byResizing(to: size, contentMode: contentMode, upscale: upscale)
        }

        public var identifier: String {
            return "ImageProcessor.Resize(\(size)\(contentMode)\(upscale))"
        }

        public var hashableIdentifier: AnyHashable {
            return self
        }
    }
}

// MARK: - ImageProcessor.Crop

extension ImageProcessor {

    public struct Crop: ImageProcessing, Hashable {

        private let size: CGSize

        /// Initializes the cropping image processor. Crops the image to the given
        /// size by resizing the image to fill the canvas maintaining its aspect
        /// ratio. The cropped image is centered in the canvas.
        public init(size: CGSize, unit: Unit = .points) {
            self.size = CGSize(size: size, unit: unit)
        }

        public func process(image: Image, context: ImageProcessingContext?) -> Image? {
            return image.processed.byResizingAndCropping(to: size)
        }

        public var identifier: String {
            return "ImageProcessor.Crop(\(size)"
        }

        public var hashableIdentifier: AnyHashable {
            return self
        }
    }
}

// MARK: - ImageProcessor.Circle

extension ImageProcessor {

    public struct Circle: ImageProcessing, Hashable {
        public init() {}

        public func process(image: Image, context: ImageProcessingContext?) -> Image? {
            return image.processed.byDrawingInCircle()
        }

        public var identifier: String {
            return "ImageProcessor.Circle"
        }

        public var hashableIdentifier: AnyHashable {
            return self
        }
    }
}

// MARK: - ImageProcessor.RoundedCorners

extension ImageProcessor {

    public struct RoundedCorners: ImageProcessing, Hashable {
        private let radius: CGFloat

        public init(radius: CGFloat, unit: Unit = .points) {
            switch unit {
            case .pixels:
                self.radius = radius
            case .points:
                self.radius = radius * Screen.scale
            }
        }

        public func process(image: Image, context: ImageProcessingContext?) -> Image? {
            return image.processed.byAddingRoundedCorners(radius: radius)
        }

        public var identifier: String {
            return "ImageProcessor.RoundedCorners(\(radius))"
        }

        public var hashableIdentifier: AnyHashable {
            return self
        }
    }
}

#if os(iOS) || os(tvOS)

// MARK: - ImageProcessor.CoreImageFilter

import CoreImage

extension ImageProcessor {

    /// Applies Core Image filter `CIFilter` to the image.
    ///
    /// # Performance Considerations.
    ///
    /// Prefer chaining multiple `CIFilter` objects using `Core Image` facilities
    /// instead of using multiple instances of `ImageProcessor.CoreImageFilter`.
    ///
    /// # References
    ///
    /// - [Core Image Programming Guide](https://developer.apple.com/library/ios/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html)
    /// - [Core Image Filter Reference](https://developer.apple.com/library/prerelease/ios/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html)
    public struct CoreImageFilter: ImageProcessing {
        private let name: String
        private let parameters: [String: Any]

        public init(name: String, parameters: [String: Any]) {
            self.name = name
            self.parameters = parameters
        }

        public func process(image: Image, context: ImageProcessingContext?) -> Image? {
            let filter = CIFilter(name: name, parameters: parameters)
            return CoreImageFilter.apply(filter: filter, to: image)
        }

        public var identifier: String {
            return "ImageProcessor.CoreImageFilter(\(name))\(parameters))" }

        // MARK: - Apply Filter

        /// A default context shared between all Core Image filters. The context
        /// has `.priorityRequestLow` option set to `true`.
        public static var context = CIContext(options: [.priorityRequestLow: true])

        static func applyFilter(to image: UIImage, context: CIContext = context, closure: (CoreImage.CIImage) -> CoreImage.CIImage?) -> UIImage? {
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
            guard let imageRef = context.createCGImage(outputImage, from: inputImage.extent) else {
                return nil
            }
            return UIImage(cgImage: imageRef, scale: image.scale, orientation: image.imageOrientation)
        }

        static func apply(filter: CIFilter?, to image: UIImage) -> UIImage? {
            guard let filter = filter else {
                return nil
            }
            return applyFilter(to: image) {
                filter.setValue($0, forKey: kCIInputImageKey)
                return filter.outputImage
            }
        }
    }
}

// MARK: - ImageProcessor.GaussianBlur

extension ImageProcessor {
    /// Blurs image using CIGaussianBlur filter.
    public struct GaussianBlur: ImageProcessing, Hashable {

        private let radius: Int

        /// Initializes the receiver with a blur radius.
        public init(radius: Int = 8) {
            self.radius = radius
        }

        /// Applies `CIGaussianBlur` filter to the image.
        public func process(image: Image, context: ImageProcessingContext?) -> Image? {
            let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": radius])
            return CoreImageFilter.apply(filter: filter, to: image)
        }

        public var identifier: String {
            return "GaussianBlur\(radius)"
        }

        public var hashableIdentifier: AnyHashable {
            return self
        }
    }
}

#endif

// MARK: - ImageDecompression (Internal)

struct ImageDecompression {

    func decompress(image: Image) -> Image {
        let output = image.decompressed() ?? image
        ImageDecompression.setDecompressionNeeded(false, for: output)
        return output
    }

    // MARK: Managing Decompression State

    static var isDecompressionNeededAK = "ImageDecompressor.isDecompressionNeeded.AssociatedKey"

    static func setDecompressionNeeded(_ isDecompressionNeeded: Bool, for image: Image) {
        objc_setAssociatedObject(image, &isDecompressionNeededAK, isDecompressionNeeded, .OBJC_ASSOCIATION_RETAIN)
    }

    static func isDecompressionNeeded(for image: Image) -> Bool? {
        return objc_getAssociatedObject(image, &isDecompressionNeededAK) as? Bool
    }
}

// MARK: - Image Processing (Internal)

extension Image {
    /// Draws the image in a `CGContext` in a canvas with the given size using
    /// the specified draw rect.
    ///
    /// For example, if the canvas size is `CGSize(width: 10, height: 10)` and
    /// the draw rect is `CGRect(x: -5, y: 0, width: 20, height: 10)` it would
    /// draw the input image (which is horizonal based on the known draw rect)
    /// in a square by centering it in the canvas.
    ///
    /// - parameter drawRect: `nil` by default. If `nil` will use the canvas rect.
    func draw(inCanvasWithSize canvasSize: CGSize, drawRect: CGRect? = nil) -> UIImage? {
        guard let cgImage = cgImage else {
            return nil
        }

        // For more info see:
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        let alphaInfo: CGImageAlphaInfo = cgImage.isOpaque ? .noneSkipLast : .premultipliedLast

        guard let ctx = CGContext(
            data: nil,
            width: Int(canvasSize.width), height: Int(canvasSize.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue) else {
                return nil
        }
        ctx.draw(cgImage, in: drawRect ?? CGRect(origin: .zero, size: canvasSize))
        guard let outputCGImage = ctx.makeImage() else {
            return nil
        }
        return UIImage(cgImage: outputCGImage, scale: scale, orientation: imageOrientation)
    }

    /// Decompresses the input image by drawing in the the `CGContext`.
    func decompressed() -> Image? {
        guard let cgImage = cgImage else {
            return nil
        }
        return draw(inCanvasWithSize: cgImage.size, drawRect: CGRect(origin: .zero, size: cgImage.size))
    }
}

extension Image {
    var processed: ImageProcessingExtensions {
        return ImageProcessingExtensions(image: self)
    }
}

struct ImageProcessingExtensions {
    let image: Image

    func byResizing(to targetSize: CGSize,
                    contentMode: ImageProcessor.Resize.ContentMode,
                    upscale: Bool) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let scale = contentMode == .aspectFill ?
            cgImage.size.scaleToFill(targetSize) :
            cgImage.size.scaleToFit(targetSize)
        guard scale < 1 || upscale else {
            return image // The image doesn't require scaling
        }
        let size = cgImage.size.scaled(by: scale).rounded()
        return image.draw(inCanvasWithSize: size)
    }

    /// Crops the input image to the given size and resizes it if needed.
    /// - note: this method will always upscale.
    func byResizingAndCropping(to targetSize: CGSize) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let imageSize = cgImage.size
        let scaledSize = imageSize.scaled(by: cgImage.size.scaleToFill(targetSize))
        let drawRect = scaledSize.centeredInRectWithSize(targetSize)
        return image.draw(inCanvasWithSize: targetSize, drawRect: drawRect)
    }

    func byDrawingInCircle() -> UIImage? {
        guard let squared = byCroppingToSquare(), let cgImage = squared.cgImage else {
            return nil
        }
        let radius = CGFloat(cgImage.width) / 2.0 // Can use any dimenstion since image is a square
        return squared.processed.byAddingRoundedCorners(radius: radius)
    }

    /// Draws an image in square by preserving an aspect ratio and filling the
    /// square if needed. If the image is already a square, returns an original image.
    func byCroppingToSquare() -> UIImage? {
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
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Adds rounded corners with the given radius to the image.
    /// - parameter radius: Radius in pixels.
    func byAddingRoundedCorners(radius: CGFloat) -> Image? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let imageSize = cgImage.size

        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        let clippingPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint.zero, size: imageSize), cornerRadius: radius)
        clippingPath.addClip()

        image.draw(in: CGRect(origin: CGPoint.zero, size: imageSize))

        guard let roundedImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
            return nil
        }
        return UIImage(cgImage: roundedImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
#endif

// MARK: - UI(NS)Image and CGImage Extensions (Internal)

extension Image {
    #if os(macOS)
    var cgImage: CGImage? {
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    #endif
}

extension CGImage {
    /// Returns `true` if the image doesn't contain alpha channel.
    var isOpaque: Bool {
        let alpha = alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    }

    var size: CGSize {
        return CGSize(width: width, height: height)
    }
}

// MARK: - CoreGraphics Helpers (Internal)

extension CGSize: Hashable { // For some reason `CGSize` isn't `Hashable`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}

extension CGSize {
    #if os(iOS) || os(tvOS) || os(watchOS)
    /// Creates the size in pixels by scaling to the input size to the screen scale
    /// if needed.
    init(size: CGSize, unit: ImageProcessor.Unit) {
        switch unit {
        case .pixels: self = size // The size is already in pixels
        case .points: self = size.scaled(by: Screen.scale)
        }
    }
    #endif

    func scaled(by scale: CGFloat) -> CGSize {
        return CGSize(width: width * scale, height: height * scale)
    }

    func rounded() -> CGSize {
        return CGSize(width: CGFloat(round(width)), height: CGFloat(round(height)))
    }
}

extension CGSize {
    func scaleToFill(_ targetSize: CGSize) -> CGFloat {
        let scaleHor = targetSize.width / width
        let scaleVert = targetSize.height / height
        return max(scaleHor, scaleVert)
    }

    func scaleToFit(_ targetSize: CGSize) -> CGFloat {
        let scaleHor = targetSize.width / width
        let scaleVert = targetSize.height / height
        return min(scaleHor, scaleVert)
    }

    /// Caclulates a rect such that the ouput rect will be in the center of
    /// the rect of the input size (assuming origin: .zero)
    func centeredInRectWithSize(_ targetSize: CGSize) -> CGRect {
        // First we need to resize the original size to fill the target size.
        return CGRect(origin: .zero, size: self).offsetBy(
            dx: -(width - targetSize.width) / 2,
            dy: -(height - targetSize.height) / 2
        )
    }
}

// MARK: - ImageProcessing Extensions (Internal)

// A special version of `==` which is optimized to not create hashable identifiers
// when not necessary (e.g. one processor is `nil` and another one isn't.
func == (lhs: ImageProcessing?, rhs: ImageProcessing?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case let (.some(lhs), .some(rhs)): return lhs.hashableIdentifier == rhs.hashableIdentifier
    default: return false
    }
}

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

// MARK: - Misc (Internal)

struct Screen {
    #if os(iOS) || os(tvOS)
    /// Returns the current screen scale.
    static var scale: CGFloat {
        return UIScreen.main.scale
    }
    #elseif os(watchOS)
    /// Returns the current screen scale.
    static var scale: CGFloat {
        return WKInterfaceDevice.current().screenScale
    }
    #endif
}
