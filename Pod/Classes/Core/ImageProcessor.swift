// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public protocol ImageProcessing {
    func isEquivalentToProcessor(other: ImageProcessing) -> Bool
    func processedImage(image: UIImage, forRequest request: ImageRequest) -> UIImage?
}

public class ImageDecompressor: ImageProcessing {
    public let targetSize: CGSize
    public let contentMode: ImageContentMode
    
    public init(targetSize: CGSize, contentMode: ImageContentMode) {
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
    
    public func isEquivalentToProcessor(processor: ImageProcessing) -> Bool {
        guard let other = processor as? ImageDecompressor else {
            return false
        }
        return self.targetSize == other.targetSize && self.contentMode == other.contentMode
    }
    
    public func processedImage(image: UIImage, forRequest request: ImageRequest) -> UIImage? {
        return decompressedImage(image, targetSize: request.targetSize, contentMode: request.contentMode)
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
        var equal = true
        zip(self.processors, other.processors).forEach {
            if equal {
                equal = $0.isEquivalentToProcessor($1)
            }
        }
        return true
    }
    
    public func processedImage(image: UIImage, forRequest request: ImageRequest) -> UIImage? {
        return processedImage(image, forRequest: request, processors: self.processors)
    }
    
    public func processedImage(image: UIImage?, forRequest request: ImageRequest, processors: [ImageProcessing]) -> UIImage? {
        return processors.reduce(image) {
            if let input = $0 {
                return $1.processedImage(input, forRequest: request)
            }
            return $0
        }
    }
}

private func decompressedImage(image: UIImage, targetSize: CGSize, contentMode: ImageContentMode) -> UIImage {
    let bitmapSize = CGSize(width: CGImageGetWidth(image.CGImage), height: CGImageGetHeight(image.CGImage))
    let scaleWidth = targetSize.width / bitmapSize.width
    let scaleHeight = targetSize.height / bitmapSize.height
    let scale = contentMode == .AspectFill ? max(scaleWidth, scaleHeight) : min(scaleWidth, scaleHeight)
    return decompressedImage(image, scale: Double(scale))
}

private func decompressedImage(image: UIImage, scale: Double) -> UIImage {
    let imageRef = image.CGImage
    var imageSize = CGSize(width: CGImageGetWidth(imageRef), height: CGImageGetHeight(imageRef))
    if scale < 1.0 {
        imageSize = CGSize(width: Double(imageSize.width) * scale, height: Double(imageSize.height) * scale)
    }
    
    let contextRef = CGBitmapContextCreate(nil,
        Int(imageSize.width),
        Int(imageSize.height),
        CGImageGetBitsPerComponent(imageRef),
        0,
        CGColorSpaceCreateDeviceRGB(),
        CGImageGetBitmapInfo(imageRef).rawValue)
    
    if contextRef == nil {
        return image
    }
    
    CGContextDrawImage(contextRef, CGRect(origin: CGPointZero, size: imageSize), imageRef)
    if let decompressedImageRef = CGBitmapContextCreateImage(contextRef) {
        return UIImage(CGImage: decompressedImageRef, scale: image.scale, orientation: image.imageOrientation)
    }
    return image
}
