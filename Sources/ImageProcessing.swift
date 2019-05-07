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

struct ImageDecompression: ImageProcessing, Hashable {
    let identifier: String = "ImageDecompressor"

    var hashableIdentifier: AnyHashable {
        return self
    }

    func process(image: Image, context: ImageProcessingContext) -> Image? {
        guard ImageDecompression.isDecompressionNeeded(for: image) ?? false else {
            return image // Image doesn't require decompression
        }
        let output = ImageUlitities.decompress(image)
        ImageDecompression.setDecompressionNeeded(false, for: output)
        return output
    }

    public static func == (lhs: ImageDecompression, rhs: ImageDecompression) -> Bool {
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

// Deprecated in Nuke 8.0. Remove by January 2020.
@available(*, deprecated, message: "Please use ImageScalingProcessor to resize images and ImagePipeline.Configuration.isDecompressionEnabled to control decompression (enabled by default)")
public typealias ImageDecompressor = ImageScalingProcessor

/// Scales down the input images. Maintains original aspect ratio.
public struct ImageScalingProcessor: ImageProcessing, Hashable {

    public var identifier: String {
        return "ImageScalingProcessor\(targetSize)\(contentMode)\(upscale)"
    }

    public var hashableIdentifier: AnyHashable {
        return self
    }

    /// An option for how to resize the image.
    public enum ContentMode {
        /// Scales the image so that it completely fills the target size.
        /// Doesn't clip images.
        case aspectFill

        /// Scales the image so that it fits the target size.
        case aspectFit
    }

    /// Size to pass to disable resizing.
    public static let MaximumSize = CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )

    private let targetSize: CGSize
    private let contentMode: ContentMode
    private let upscale: Bool

    /// Initializes `Decompressor` with the given parameters.
    /// - parameter targetSize: Size in pixels. `MaximumSize` by default.
    /// - parameter contentMode: An option for how to resize the image to the
    /// target size. `.aspectFill` by default.
    /// - parameter upscale: If disabled, will never upscale the input images.
    /// `false` by default.
    public init(targetSize: CGSize = MaximumSize, contentMode: ContentMode = .aspectFill, upscale: Bool = false) {
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.upscale = upscale
    }

    /// Decompresses and scales the image.
    public func process(image: Image, context: ImageProcessingContext) -> Image? {
        return ImageUlitities.scale(image, targetSize: targetSize, contentMode: contentMode, upscale: upscale)
    }

    #if !os(watchOS)
    /// Returns target size in pixels for the given view. Takes main screen
    /// scale into the account.
    public static func targetSize(for view: UIView) -> CGSize { // in pixels
        let scale = UIScreen.main.scale
        let size = view.bounds.size
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    #endif
}

extension CGSize: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}

enum ImageUlitities {
    static func scale(_ image: UIImage,
                      targetSize: CGSize,
                      contentMode: ImageScalingProcessor.ContentMode,
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

    private static func isOpaque(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
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
