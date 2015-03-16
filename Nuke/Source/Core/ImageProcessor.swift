// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

public protocol ImageProcessing {
    func isProcessingEquivalent(r1: ImageRequest, r2: ImageRequest) -> Bool
    func processedImage(image: UIImage, request: ImageRequest) -> UIImage
}

public class ImageProcessor: ImageProcessing {
    public init() {}
    
    public func isProcessingEquivalent(r1: ImageRequest, r2: ImageRequest) -> Bool {
        return r1.targetSize == r2.targetSize && r1.contentMode == r2.contentMode
    }
    
    public func processedImage(image: UIImage, request: ImageRequest) -> UIImage {
        return decompressedImage(image, request.targetSize, request.contentMode)
    }
}

private func decompressedImage(image: UIImage, targetSize: CGSize, contentMode: ImageContentMode) -> UIImage {
    let bitmapSize = CGSize(width: CGImageGetWidth(image.CGImage), height: CGImageGetHeight(image.CGImage))
    let scaleWidth = targetSize.width / bitmapSize.width;
    let scaleHeight = targetSize.height / bitmapSize.height;
    let scale = contentMode == .AspectFill ? max(scaleWidth, scaleHeight) : min(scaleWidth, scaleHeight)
    return decompressedImage(image, Double(scale))
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
        CGImageGetBitmapInfo(imageRef))
    
    if contextRef == nil {
        return image
    }
    
    CGContextDrawImage(contextRef, CGRect(origin: CGPointZero, size: imageSize), imageRef)
    let decompressedImageRef = CGBitmapContextCreateImage(contextRef);
    let decompressedImage = UIImage(CGImage: decompressedImageRef, scale: image.scale, orientation: image.imageOrientation)
    return decompressedImage ?? image
}
