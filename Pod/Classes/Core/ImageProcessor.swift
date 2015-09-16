// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public protocol ImageProcessing {
    func isRequestProcessingEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool
    func shouldProcessImage(image: UIImage, forRequest request: ImageRequest) -> Bool
    func processedImage(image: UIImage, forRequest request: ImageRequest) -> UIImage?
}

public class ImageProcessor: ImageProcessing {
    public init() {}
    
    public func isRequestProcessingEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool {
        return lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
    }
    
    public func shouldProcessImage(image: UIImage, forRequest request: ImageRequest) -> Bool {
         return true
    }
    
    public func processedImage(image: UIImage, forRequest request: ImageRequest) -> UIImage? {
        return decompressedImage(image, targetSize: request.targetSize, contentMode: request.contentMode)
    }
}

private func decompressedImage(image: UIImage, targetSize: CGSize, contentMode: ImageContentMode) -> UIImage {
    let bitmapSize = CGSize(width: CGImageGetWidth(image.CGImage), height: CGImageGetHeight(image.CGImage))
    let scaleWidth = targetSize.width / bitmapSize.width;
    let scaleHeight = targetSize.height / bitmapSize.height;
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
