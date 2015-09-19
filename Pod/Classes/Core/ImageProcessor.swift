// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

public protocol ImageProcessing {
    func isEquivalentToProcessor(processor: ImageProcessing) -> Bool
    func processImage(image: UIImage) -> UIImage?
}

public class ImageDecompressor: ImageProcessing {
    public let targetSize: CGSize
    public let contentMode: ImageContentMode
    
    public init(targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .AspectFill) {
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
    
    public func isEquivalentToProcessor(processor: ImageProcessing) -> Bool {
        guard let other = processor as? ImageDecompressor else {
            return false
        }
        return self.targetSize == other.targetSize && self.contentMode == other.contentMode
    }
    
    public func processImage(image: UIImage) -> UIImage? {
        return decompressImage(image, targetSize: self.targetSize, contentMode: self.contentMode)
    }
}

public class ImageProcessorComposition: ImageProcessing {
    public let processors: [ImageProcessing]
    
    public init(processors: [ImageProcessing]) {
        assert(processors.count > 0)
        self.processors = processors
    }
    
    public func isEquivalentToProcessor(processor: ImageProcessing) -> Bool {
        guard let other = processor as? ImageProcessorComposition else {
            return false
        }
        guard self.processors.count == other.processors.count else {
            return false
        }
        for (lhs, rhs) in zip(self.processors, other.processors) {
            if !lhs.isEquivalentToProcessor(rhs) {
                return false
            }
        }
        return true
    }
    
    public func processImage(input: UIImage) -> UIImage? {
        return processors.reduce(input) { image, processor in
            return image != nil ? processor.processImage(image!) : nil
        }
    }
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
