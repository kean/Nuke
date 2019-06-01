// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Performs image processing.
public protocol ImageProcessing {
    /// Returns processed image.
    func process(image: Image, context: ImageProcessingContext) -> Image?

    /// Returns a string which uniquely identifies the processor.
    var identifier: String { get }

    /// Returns a unique processor identifier.
    ///
    /// The default implementation simply returns `var identifier: String` but
    /// can be overridden as a performance optimization - creating and comparing
    /// strings is _expensive_ so you can opt-in to return something which is
    /// fast to create and to compare. See `ImageDecompressor` to example.
    var hashableIdentifier: AnyHashable { get }
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

        init(id: String, _ closure: @escaping (Image) -> Image?) {
            self.identifier = id
            self.closure = closure
        }

        public func process(image: Image, context: ImageProcessingContext) -> Image? {
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
        public func process(image: Image, context: ImageProcessingContext) -> Image? {
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

#if !os(macOS)
import UIKit

#if os(watchOS)
import WatchKit
#endif

// MARK: - ImageProcessor.Resize

extension ImageProcessor {

    public enum Unit {
        case points
        case pixels
    }

    public struct Resize: ImageProcessing, Hashable {

        private let size: CGSize
        private let contentMode: ContentMode
        private let crop: Bool
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
        /// - parameter unit:
        public init(size: CGSize, unit: Unit = .points, contentMode: ContentMode = .aspectFill, crop: Bool = false, upscale: Bool = false) {
            self.size = CGSize(size: size, unit: unit)
            self.contentMode = contentMode
            self.crop = crop
            self.upscale = upscale
        }

        public func process(image: Image, context: ImageProcessingContext) -> Image? {
            return ImageProcessor.resize(image, targetSize: size, contentMode: contentMode, crop: crop, upscale: upscale)
        }

        public var identifier: String {
            return "ImageProcessor.Resize(\(size)\(contentMode)\(crop)\(upscale))"
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

        public func process(image: Image, context: ImageProcessingContext) -> Image? {
            return ImageProcessor.drawInCircle(image)
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
                self.radius = radius * ImageProcessor.screenScale
            }
        }

        public func process(image: Image, context: ImageProcessingContext) -> Image? {
            return ImageProcessor.addRoundedCorners(image, radius: radius)
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

        public func process(image: Image, context: ImageProcessingContext) -> Image? {
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
        public func process(image: Image, context: ImageProcessingContext) -> Image? {
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

// MARK: - ImageDecompressor (Internal)

struct ImageDecompressor {

    func decompress(image: Image) -> Image {
        let output = ImageProcessor.decompress(image)
        ImageDecompressor.setDecompressionNeeded(false, for: output)
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

// MARK: - ImageProcessor Utilities

extension ImageProcessor {
    static func resize(_ image: UIImage,
                       targetSize: CGSize,
                       contentMode: ImageProcessor.Resize.ContentMode,
                       crop: Bool,
                       upscale: Bool) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        // A special case in which scaling is irrelevant, we just fill and crop
        if crop && contentMode == .aspectFill {
            return ImageProcessor.crop(image: image, size: targetSize)
        }

        let scale: CGFloat = {
            let bitmapSize = CGSize(width: cgImage.width, height: cgImage.height)
            let scaleHor = targetSize.width / bitmapSize.width
            let scaleVert = targetSize.height / bitmapSize.height
            return contentMode == .aspectFill ? max(scaleHor, scaleVert) : min(scaleHor, scaleVert)
        }()
        guard scale < 1 || upscale else {
            return image // The image doesn't require scaling
        }
        let size = CGSize(
            width: round(scale * CGFloat(cgImage.width)),
            height: round(scale * CGFloat(cgImage.height))
        )
        return draw(image, targetSize: size)
    }

    private static func crop(image: UIImage, size targetSize: CGSize) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        // Example:
        //
        // target size: 40 x 40 (square cell)
        // image sise: 120 x 80 (horizontal image)
        // draw size: 40 x 40 (square context)
        // draw rect: x: -20, y: 0, width: 80, height: 40 (to draw cropped)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let drawRect = CGRect(origin: .zero, size: imageSize).offsetBy(
            dx: min(0, -(imageSize.width - targetSize.width) / 2),
            dy: min(0, -(imageSize.height - targetSize.height) / 2)
        )
        return draw(image, size: targetSize, in: drawRect)
    }

    /// Draws the input image in a new `CGContext` with a given size. If the target
    /// size is `nil`, uses the image's original size.
    private static func draw(_ image: UIImage, targetSize: CGSize? = nil) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }
        let size = targetSize ?? CGSize(width: cgImage.width, height: cgImage.height)
        return draw(image, size: size, in: CGRect(origin: CGPoint.zero, size: size))
    }

    /// Draws the input image in a new `CGContext` with a given size. If the target
    /// size is `nil`, uses the image's original size.
    private static func draw(_ image: UIImage, size: CGSize, in rect: CGRect) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }

        // For more info see:
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        let alphaInfo: CGImageAlphaInfo = isOpaque(cgImage) ? .noneSkipLast : .premultipliedLast

        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue) else {
                return image
        }
        ctx.draw(cgImage, in: rect)
        guard let decompressed = ctx.makeImage() else {
            return image
        }
        return UIImage(cgImage: decompressed, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Draws the image in a `CGContext` to force image data decompression.
    static func decompress(_ image: UIImage) -> UIImage {
        return draw(image)
    }

    static func drawInCircle(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let input: UIImage
        if cgImage.width == cgImage.height {
            input = image // Already is a square
        } else {
            // Need to crop first
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            let side = min(cgImage.width, cgImage.height)
            let targetSize = CGSize(width: side, height: side)
            let drawRect = CGRect(origin: .zero, size: targetSize).offsetBy(
                dx: max(0, (imageSize.width - targetSize.width) / 2),
                dy: max(0, (imageSize.height - targetSize.height) / 2)
            )
            guard let cropped = cgImage.cropping(to: drawRect) else {
                return nil
            }
            input = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        }
        return addRoundedCorners(input, radius: CGFloat(cgImage.width) / 2.0)
    }

    static func addRoundedCorners(_ image: UIImage, radius: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)

        let clippingPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint.zero, size: imageSize), cornerRadius: radius)
        clippingPath.addClip()

        image.draw(in: CGRect(origin: CGPoint.zero, size: imageSize))

        guard let roundedImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
            return image
        }
        UIGraphicsEndImageContext()
        return UIImage(cgImage: roundedImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

extension CGSize: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}

extension CGSize {
    init(size: CGSize, unit: ImageProcessor.Unit) {
        switch unit {
        case .pixels:
            self = size
        case .points:
            let scale = ImageProcessor.screenScale
            self = CGSize(width: size.width * scale, height: size.height * scale)
        }
    }
}

extension ImageProcessor {
    static var screenScale: CGFloat {
        #if os(watchOS)
        return WKInterfaceDevice.current().screenScale
        #else
        return UIScreen.main.scale
        #endif
    }
}

#endif

extension ImageProcessor {
    static func isOpaque(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    }

    static func isTransparent(_ image: CGImage) -> Bool {
        return !isOpaque(image)
    }
}

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
