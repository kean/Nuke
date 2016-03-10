// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

// MARK: - ImageProcessing

/**
Performs image processing.

Types that implement `ImageProcessing` protocol should either use one of the default implementations of `isEquivalent(_:)` method or provide their own implementation, which is required to cache processed images.
*/
public protocol ImageProcessing {
    /// Returns processed image.
    func process(image: Image) -> Image?

    /// Compares two processors for equivalence. Two processors are equivalent if they produce the same image for the same input. For more info see the extensions that provide default implementations of this method.
    func isEquivalent(other: ImageProcessing) -> Bool
}

public extension ImageProcessing {
    /// Returns true if both processors are instances of the same class. Use this implementation when your filter doesn't have any parameters.
    public func isEquivalent(other: ImageProcessing) -> Bool {
        return other is Self
    }
}

public extension ImageProcessing where Self: Equatable {
    /// Compares processors using == function.
    public func isEquivalent(other: ImageProcessing) -> Bool {
        return (other as? Self) == self
    }
}


// MARK: - ImageProcessorComposition

/// Composes multiple image processors.
public class ImageProcessorComposition: ImageProcessing, Equatable {
    /// Image processors that the receiver was initialized with.
    public let processors: [ImageProcessing]

    /// Composes multiple image processors.
    public init(processors: [ImageProcessing]) {
        self.processors = processors
    }

    /// Processes the given image by applying each processor in an order in which they are present in the processors array. If one of the processors fails to produce an image the processing stops and nil is returned.
    public func process(input: Image) -> Image? {
        var image: Image! = input
        for processor in processors {
            if image == nil {
                return nil
            }
            autoreleasepool {
                image = processor.process(image)
            }
        }
        return image
    }
}

/// Returns true if both compositions have the same number of processors, and the processors are pairwise-equivalent.
public func ==(lhs: ImageProcessorComposition, rhs: ImageProcessorComposition) -> Bool {
    guard lhs.processors.count == rhs.processors.count else {
        return false
    }
    for (lhs, rhs) in zip(lhs.processors, rhs.processors) {
        if !lhs.isEquivalent(rhs) {
            return false
        }
    }
    return true
}


/// The `ImageProcessorWithClosure` is used for creating anonymous image filters.
public class ImageProcessorWithClosure: ImageProcessing, Equatable {
    /// The identifier of the filter. Filters with equivalent closures should have the same identifiers.
    public let identifier: String

    /// A closure that performs image processing.
    public let closure: Image -> Image?

    /**
     Initializes the `ImageProcessorWithClosure` with the given identifier and closure.

     - parameter identifier: The identifier of the filter. Filters with equivalent closures should have the same identifiers.
     */
    public init(identifier: String, closure: Image -> Image?) {
        self.identifier = identifier
        self.closure = closure
    }

    /// Processors images using a closure that the receiver was initialized with.
    public func process(image: Image) -> Image? {
        return closure(image)
    }
}

/// Comapres two processors using their identifiers.
public func ==(lhs: ImageProcessorWithClosure, rhs: ImageProcessorWithClosure) -> Bool {
    return lhs.identifier == rhs.identifier
}

#if !os(OSX)

    // MARK: - ImageDecompressor

    /**
    Decompresses and scales input images.

    If the image size is bigger then the given target size (in pixels) it is resized to either fit or fill target size (see ImageContentMode enum for more info). Image is scaled maintaining aspect ratio.

    Decompression and scaling are performed in a single pass which improves performance and reduces memory usage.
    */
    public class ImageDecompressor: ImageProcessing, Equatable {
        /// Target size in pixels. Default value is ImageMaximumSize.
        public let targetSize: CGSize

        /// An option for how to resize the image to the target size. Default value is .AspectFill. See ImageContentMode enum for more info.
        public let contentMode: ImageContentMode

        /**
         Initializes the receiver with target size and content mode.

         - parameter targetSize: Target size in pixels. Default value is ImageMaximumSize.
         - parameter contentMode: An option for how to resize the image to the target size. Default value is .AspectFill. See ImageContentMode enum for more info.
         */
        public init(targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .AspectFill) {
            self.targetSize = targetSize
            self.contentMode = contentMode
        }

        /// Decompressed the input image.
        public func process(image: Image) -> Image? {
            return decompress(image, targetSize: targetSize, contentMode: contentMode)
        }
    }

    /// Returns true if both decompressors have the same `targetSize` and `contentMode`.
    public func ==(lhs: ImageDecompressor, rhs: ImageDecompressor) -> Bool {
        return lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
    }

    private func decompress(image: UIImage, targetSize: CGSize, contentMode: ImageContentMode) -> UIImage {
        let bitmapSize = CGSize(width: CGImageGetWidth(image.CGImage), height: CGImageGetHeight(image.CGImage))
        let scaleHor = targetSize.width / bitmapSize.width
        let scaleVert = targetSize.height / bitmapSize.height
        let scale = contentMode == .AspectFill ? max(scaleHor, scaleVert) : min(scaleHor, scaleVert)
        return decompress(image, scale: Double(scale))
    }

    private func decompress(image: UIImage, scale: Double) -> UIImage {
        guard let imageRef = image.CGImage else {
            return image
        }
        let minification = CGFloat(min(scale, 1))
        let size = CGSize(width: round(minification * CGFloat(CGImageGetWidth(imageRef))), height: round(minification * CGFloat(CGImageGetHeight(imageRef))))

        // For more info see:
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        let alphaInfo = isOpaque(imageRef) ? CGImageAlphaInfo.NoneSkipLast : CGImageAlphaInfo.PremultipliedLast
        let bitmapInfo = CGBitmapInfo(rawValue: alphaInfo.rawValue)

        guard let contextRef = CGBitmapContextCreate(nil, Int(size.width), Int(size.height), 8, 0, CGColorSpaceCreateDeviceRGB(), bitmapInfo.rawValue) else {
            return image
        }
        CGContextDrawImage(contextRef, CGRect(origin: CGPointZero, size: size), imageRef)
        guard let decompressedImageRef = CGBitmapContextCreateImage(contextRef) else {
            return image
        }
        return UIImage(CGImage: decompressedImageRef, scale: image.scale, orientation: image.imageOrientation)
    }

    private func isOpaque(image: CGImageRef) -> Bool {
        let alpha = CGImageGetAlphaInfo(image)
        return alpha == .None ||
            alpha == .NoneSkipFirst ||
            alpha == .NoneSkipLast
    }
#endif


#if os(iOS) || os(tvOS)

// MARK: - CoreImage
    
    private let sharedContext = CIContext(options: [kCIContextPriorityRequestLow: true])
    
    /// Core Image helper methods.
    public extension UIImage {
        /**
         Applies closure with a filter to the image.
         
         Performance considerations. Chaining multiple CIFilter objects is much more efficient then using ImageProcessorComposition to combine multiple instances of CoreImageFilter class. Avoid unnecessary texture transfers between the CPU and GPU.
         
         - parameter context: Core Image context, uses shared context by default.
         - parameter filter: Closure for applying image filter.
         */
        public func nk_filter(context context: CIContext = sharedContext, closure: CoreImage.CIImage -> CoreImage.CIImage?) -> UIImage? {
            func inputImageForImage(image: Image) -> CoreImage.CIImage? {
                if let image = image.CGImage {
                    return CoreImage.CIImage(CGImage: image)
                }
                if let image = image.CIImage {
                    return image
                }
                return nil
            }
            guard let inputImage = inputImageForImage(self), outputImage = closure(inputImage) else {
                return nil
            }
            let imageRef = context.createCGImage(outputImage, fromRect: inputImage.extent)
            return UIImage(CGImage: imageRef, scale: scale, orientation: imageOrientation)
        }
        
        /**
         Applies filter to the image.
         
         - parameter context: Core Image context, uses shared context by default.
         - parameter filter: Image filter. Function automatically sets input image on the filter.
         */
        public func nk_filter(filter: CIFilter?, context: CIContext = sharedContext) -> UIImage? {
            guard let filter = filter else {
                return nil
            }
            return nk_filter(context: context) {
                filter.setValue($0, forKey: kCIInputImageKey)
                return filter.outputImage
            }
        }
    }
    
    /// Blurs image using CIGaussianBlur filter.
    public struct ImageFilterGaussianBlur: ImageProcessing {
        /// Blur radius.
        public let radius: Int
        
        /**
         Initializes the receiver with a blur radius.
         
         - parameter radius: Blur radius, default value is 8.
         */
        public init(radius: Int = 8) {
            self.radius = radius
        }

        /// Applies CIGaussianBlur filter to the image.
        public func process(image: UIImage) -> UIImage? {
            return image.nk_filter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : radius]))
        }
    }

    /// Compares two filters based on their radius.
    public func ==(lhs: ImageFilterGaussianBlur, rhs: ImageFilterGaussianBlur) -> Bool {
        return lhs.radius == rhs.radius
    }
#endif
