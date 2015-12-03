// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

// MARK: - ImageProcessing

/** Performs image processing.

Types that implement `ImageProcessing` protocol should either use one of the default implementations of `isEquivalentToProcessor(_:)` method or provide their own implementation, which is required to cache processed images.
*/
public protocol ImageProcessing {
    /** Returns processed image.
     */
    func processImage(image: Image) -> Image?

    /** Compares two processors for equivalence. For more info see extensions that provide default implementation of this method.
     */
    func isEquivalentToProcessor(other: ImageProcessing) -> Bool
}

public extension ImageProcessing {
    /** Returns true if both processors are instances of the same class. Use this implementation when your filter doesn't have any parameters.
     */
    public func isEquivalentToProcessor(other: ImageProcessing) -> Bool {
        return other is Self
    }
}

public extension ImageProcessing where Self: Equatable {
    /** Compares processors using == function.
     */
    public func isEquivalentToProcessor(other: ImageProcessing) -> Bool {
        return (other as? Self) == self
    }
}

/** Compares processors if both are not nil, returns true if both are nil, returns false otherwise.
 */
public func equivalentProcessors(lhs: ImageProcessing?, rhs: ImageProcessing?) -> Bool {
    switch (lhs, rhs) {
    case (.Some(let lhs), .Some(let rhs)): return lhs.isEquivalentToProcessor(rhs)
    case (.None, .None): return true
    default: return false
    }
}

// MARK: - ImageProcessorComposition

/** Composes multiple image processors.

Processors are applied in an order in which they are present in the processors array. If one of the processors fails to produce an image the processing stops and nil is returned.
*/
public class ImageProcessorComposition: ImageProcessing, Equatable {
    public let processors: [ImageProcessing]

    /** Composes multiple image processors.
     */
    public init(processors: [ImageProcessing]) {
        self.processors = processors
    }
    
    public func processImage(input: Image) -> Image? {
        var image: Image? = input
        for processor in self.processors {
            if image == nil {
                return nil
            }
            autoreleasepool {
                image = processor.processImage(image!)
            }
        }
        return image
    }
}

public func ==(lhs: ImageProcessorComposition, rhs: ImageProcessorComposition) -> Bool {
    guard lhs.processors.count == rhs.processors.count else {
        return false
    }
    for (lhs, rhs) in zip(lhs.processors, rhs.processors) {
        if !lhs.isEquivalentToProcessor(rhs) {
            return false
        }
    }
    return true
}

#if !os(OSX)

    // MARK: - ImageDecompressor

    /** Decompresses and scales input images.
    
    If the image size is bigger then the given target size (in pixels) it is resized to either fit or fill target size (see ImageContentMode enum for more info). Image is scaled maintaining aspect ratio.
    
    Decompression and scaling are performed in a single pass which improves performance and reduces memory usage.
    */
    public class ImageDecompressor: ImageProcessing, Equatable {
        /** Target size in pixels. Default value is ImageMaximumSize.
         */
        public let targetSize: CGSize

        /** An option for how to resize the image to the target size. Default value is .AspectFill. See ImageContentMode enum for more info.
         */
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

        public func processImage(image: Image) -> Image? {
            return decompressImage(image, targetSize: self.targetSize, contentMode: self.contentMode)
        }
    }
    
    public func ==(lhs: ImageDecompressor, rhs: ImageDecompressor) -> Bool {
        return lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
    }

    private func decompressImage(image: UIImage, targetSize: CGSize, contentMode: ImageContentMode) -> UIImage {
        let bitmapSize = CGSize(width: CGImageGetWidth(image.CGImage), height: CGImageGetHeight(image.CGImage))
        let scaleWidth = targetSize.width / bitmapSize.width
        let scaleHeight = targetSize.height / bitmapSize.height
        let scale = contentMode == .AspectFill ? max(scaleWidth, scaleHeight) : min(scaleWidth, scaleHeight)
        return decompressImage(image, scale: Double(scale))
    }
    
    private func decompressImage(image: UIImage, scale: Double) -> UIImage {
        let imageRef = image.CGImage
        let minification = CGFloat(min(scale, 1))
        let imageSize = CGSize(width: round(minification * CGFloat(CGImageGetWidth(imageRef))), height: round(minification * CGFloat(CGImageGetHeight(imageRef))))
        // See Quartz 2D Programming Guide and https://github.com/kean/Nuke/issues/35 for more info
        guard let contextRef = CGBitmapContextCreate(nil, Int(imageSize.width), Int(imageSize.height), 8, 0, CGColorSpaceCreateDeviceRGB(), CGImageAlphaInfo.PremultipliedLast.rawValue) else {
            return image
        }
        CGContextDrawImage(contextRef, CGRect(origin: CGPointZero, size: imageSize), imageRef)
        guard let decompressedImageRef = CGBitmapContextCreateImage(contextRef) else {
            return image
        }
        return UIImage(CGImage: decompressedImageRef, scale: image.scale, orientation: image.imageOrientation)
    }
#endif
