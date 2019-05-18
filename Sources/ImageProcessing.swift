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

/// Composes multiple processors.
struct ImageProcessorComposition: ImageProcessing, Hashable {
    private let processors: [ImageProcessing]

    /// Composes multiple processors.
    public init(_ processors: [ImageProcessing]) {
        self.processors = processors
    }

    /// Processes the given image by applying each processor in an order in
    /// which they were added. If one of the processors fails to produce
    /// an image the processing stops and `nil` is returned.
    func process(image: Image, context: ImageProcessingContext) -> Image? {
        return processors.reduce(image) { image, processor in
            return autoreleasepool {
                image.flatMap { processor.process(image: $0, context: context) }
            }
        }
    }

    var identifier: String {
        return processors.map({ $0.identifier }).joined()
    }

    var hashableIdentifier: AnyHashable {
        return self
    }

    func hash(into hasher: inout Hasher) {
        for processor in processors {
            hasher.combine(processor.hashableIdentifier)
        }
    }

    static func == (lhs: ImageProcessorComposition, rhs: ImageProcessorComposition) -> Bool {
        guard lhs.processors.count == rhs.processors.count else {
            return false
        }
        // Lazily creates `hashableIdentifiers` because for some processors the
        // identifiers might be expensive to compute.
        return zip(lhs.processors, rhs.processors).allSatisfy {
            $0.hashableIdentifier == $1.hashableIdentifier
        }
    }
}

struct AnonymousImageProcessor: ImageProcessing {
    public let identifier: String
    private let closure: (Image) -> Image?

    init(_ identifier: String, _ closure: @escaping (Image) -> Image?) {
        self.identifier = identifier
        self.closure = closure
    }

    func process(image: Image, context: ImageProcessingContext) -> Image? {
        return self.closure(image)
    }
}

#if !os(macOS)
import UIKit

#if os(watchOS)
import WatchKit
#endif

// MARK: - ImageProcessor

public enum ImageProcessor {

    public enum Unit {
        case points
        case pixels
    }
}

// MARK: - ImageProcessor.Scale

extension ImageProcessor {

    public struct Scale: ImageProcessing, Hashable {

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

        public init(size: CGSize, unit: Unit = .points, contentMode: ContentMode = .aspectFill, upscale: Bool = false) {
            self.size = CGSize(size: size, unit: unit)
            self.contentMode = contentMode
            self.upscale = upscale
        }

        public func process(image: Image, context: ImageProcessingContext) -> Image? {
            return ImageProcessor.scale(image, targetSize: size, contentMode: contentMode, upscale: upscale)
        }

        public var identifier: String {
            return "ImageProcessor.Scale(\(size)-\(contentMode)-\(upscale))"
        }

        public var hashableIdentifier: AnyHashable {
            return self
        }
    }
}

// MARK: - ImageProcessor.Resize

extension ImageProcessor {

    public struct Resize: ImageProcessing, Hashable {

        private let size: CGSize

        public init(size: CGSize, unit: Unit = .points) {
            self.size = CGSize(size: size, unit: unit)
        }

        public func process(image: Image, context: ImageProcessingContext) -> Image? {
            return ImageProcessor.resize(image, size: size)
        }

        public var identifier: String {
            return "ImageProcessor.Resize(\(size))"
        }

        public var hashableIdentifier: AnyHashable {
            return self
        }
    }
}

// MARK: - ImageDecompressor (Internal)

struct ImageDecompressor: ImageProcessing, Hashable {
    let identifier: String = "ImageDecompressor"

    var hashableIdentifier: AnyHashable {
        return self
    }

    func process(image: Image, context: ImageProcessingContext) -> Image? {
        guard ImageDecompressor.isDecompressionNeeded(for: image) ?? false else {
            return image // Image doesn't require decompression
        }
        let output = ImageProcessor.decompress(image)
        ImageDecompressor.setDecompressionNeeded(false, for: output)
        return output
    }

    public static func == (lhs: ImageDecompressor, rhs: ImageDecompressor) -> Bool {
        return true
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
    static func scale(_ image: UIImage,
                      targetSize: CGSize,
                      contentMode: ImageProcessor.Scale.ContentMode,
                      upscale: Bool) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
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
        let targetSize = CGSize(
            width: round(scale * CGFloat(cgImage.width)),
            height: round(scale * CGFloat(cgImage.height))
        )
        return draw(image, targetSize: targetSize)
    }

    static func resize(_ image: UIImage, size: CGSize) -> UIImage {
        return draw(image, targetSize: size)
    }

    /// Draws the input image in a new `CGContext` with a given size. If the target
    /// size is `nil`, uses the image's original size.
    private static func draw(_ image: UIImage, targetSize: CGSize? = nil) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }

        let size = targetSize ?? CGSize(width: cgImage.width, height: cgImage.height)

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
        ctx.draw(cgImage, in: CGRect(origin: CGPoint.zero, size: size))
        guard let decompressed = ctx.makeImage() else {
            return image
        }
        return UIImage(cgImage: decompressed, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Draws the image in a `CGContext` to force image data decompression.
    static func decompress(_ image: UIImage) -> UIImage {
        return draw(image)
    }

    static func isOpaque(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    }

    static func isTransparent(_ image: CGImage) -> Bool {
        return !isOpaque(image)
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
            #if os(watchOS)
            let scale = WKInterfaceDevice.current().screenScale
            #else
            let scale = UIScreen.main.scale
            #endif
            self = CGSize(width: size.width * scale, height: size.height * scale)
        }
    }
}

#endif

// A special version of `==` which is optimized to not create hashable identifiers
// when not necessary (e.g. one processor is `nil` and another one isn't.
func == (lhs: ImageProcessing?, rhs: ImageProcessing?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case let (.some(lhs), .some(rhs)): return lhs.hashableIdentifier == rhs.hashableIdentifier
    default: return false
    }
}
