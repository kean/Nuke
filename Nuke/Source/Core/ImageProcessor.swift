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
        public let contentMode: ImageContentMode
        
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
    
    // MARK: - Misc
    
    private func decompressImage(image: UIImage, targetSize: CGSize, contentMode: ImageContentMode) -> UIImage {
        let bitmapSize = CGSize(width: CGImageGetWidth(image.CGImage), height: CGImageGetHeight(image.CGImage))
        let scaleWidth = targetSize.width / bitmapSize.width
        let scaleHeight = targetSize.height / bitmapSize.height
        let scale = contentMode == .AspectFill ? max(scaleWidth, scaleHeight) : min(scaleWidth, scaleHeight)
        return decompressImage(image, scale: Double(scale))
    }
    
    private func decompressImage(image: UIImage, scale: Double) -> UIImage {
        let imageRef = image.CGImage
        var imageSize = CGSize(width: CGImageGetWidth(imageRef), height: CGImageGetHeight(imageRef))
        if scale < 1.0 {
            imageSize = CGSize(width: Double(imageSize.width) * scale, height: Double(imageSize.height) * scale)
        }
        guard let contextRef = CGBitmapContextCreate(nil,
            Int(imageSize.width),
            Int(imageSize.height),
            CGImageGetBitsPerComponent(imageRef),
            0,
            CGColorSpaceCreateDeviceRGB(),
            CGImageGetBitmapInfo(imageRef).rawValue) else {
                return image
        }
        CGContextDrawImage(contextRef, CGRect(origin: CGPointZero, size: imageSize), imageRef)
        guard let decompressedImageRef = CGBitmapContextCreateImage(contextRef) else {
            return image
        }
        return UIImage(CGImage: decompressedImageRef, scale: image.scale, orientation: image.imageOrientation)
    }

#endif
