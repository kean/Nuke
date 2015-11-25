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

public protocol ImageProcessing {
    func processImage(image: Image) -> Image?
    func isEquivalentToProcessor(other: ImageProcessing) -> Bool
}

public extension ImageProcessing {
    public func isEquivalentToProcessor(other: ImageProcessing) -> Bool {
        return other is Self
    }
}

public extension ImageProcessing where Self: Equatable {
    public func isEquivalentToProcessor(other: ImageProcessing) -> Bool {
        return (other as? Self) == self
    }
}

public func equivalentProcessors(lhs: ImageProcessing?, rhs: ImageProcessing?) -> Bool {
    switch (lhs, rhs) {
    case (.Some(let lhs), .Some(let rhs)): return lhs.isEquivalentToProcessor(rhs)
    case (.None, .None): return true
    default: return false
    }
}

// MARK: - ImageProcessorComposition

public class ImageProcessorComposition: ImageProcessing, Equatable {
    public let processors: [ImageProcessing]
    
    public init(processors: [ImageProcessing]) {
        self.processors = processors
    }
    
    public func processImage(input: Image) -> Image? {
        return processors.reduce(input) { image, processor in
            return image != nil ? processor.processImage(image!) : nil
        }
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
    
    public class ImageDecompressor: ImageProcessing, Equatable {
        public let targetSize: CGSize
        public let targetScale: CGFloat
        public let contentMode: ImageContentMode
        
        public init(targetSize: CGSize = ImageMaximumSize, targetScale: CGFloat = 1, contentMode: ImageContentMode = .AspectFill) {
            self.targetSize = targetSize
            self.targetScale = targetScale
            self.contentMode = contentMode
        }
        
        public func processImage(image: Image) -> Image? {
            return decompressImage(image, targetSize: self.targetSize, targetScale: self.targetScale, contentMode: self.contentMode)
        }
    }
    
    public func ==(lhs: ImageDecompressor, rhs: ImageDecompressor) -> Bool {
        return lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
    }
    
    // MARK: - Misc
    
    private func decompressImage(image: UIImage, targetSize: CGSize, targetScale: CGFloat, contentMode: ImageContentMode) -> UIImage {
        let imageRef = image.CGImage
        let bitmapSize = CGSize(width: CGImageGetWidth(imageRef), height: CGImageGetHeight(imageRef))
        let scaleWidth = targetScale * targetSize.width / bitmapSize.width
        let scaleHeight = targetScale * targetSize.height / bitmapSize.height
        let minification = min(1, contentMode == .AspectFill ? max(scaleWidth, scaleHeight) : min(scaleWidth, scaleHeight))
        let imageSize = CGSize(width: round(CGFloat(CGImageGetWidth(imageRef)) * minification),
                               height: round(CGFloat(CGImageGetHeight(imageRef)) * minification))
        // See Quartz 2D Programming Guide and https://github.com/kean/Nuke/issues/35 for more info
        guard let contextRef = CGBitmapContextCreate(nil, Int(imageSize.width), Int(imageSize.height), 8, 0, CGColorSpaceCreateDeviceRGB(), CGImageAlphaInfo.PremultipliedLast.rawValue) else {
            return image
        }
        CGContextDrawImage(contextRef, CGRect(origin: CGPointZero, size: imageSize), imageRef)
        guard let decompressedImageRef = CGBitmapContextCreateImage(contextRef) else {
            return image
        }
        return UIImage(CGImage: decompressedImageRef, scale: targetScale, orientation: image.imageOrientation)
    }

#endif
