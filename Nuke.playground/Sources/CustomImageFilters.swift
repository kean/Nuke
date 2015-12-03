import UIKit

public func cropImageToSquare(image: UIImage?) -> UIImage? {
    guard let image = image else {
        return nil
    }
    func cropRectForSize(size: CGSize) -> CGRect {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2.0, y: (size.height - side) / 2.0)
        return CGRect(origin: origin, size: CGSize(width: side, height: side))
    }
    let bitmapSize = CGSize(width: CGImageGetWidth(image.CGImage), height: CGImageGetHeight(image.CGImage))
    guard let croppedImageRef = CGImageCreateWithImageInRect(image.CGImage, cropRectForSize(bitmapSize)) else {
        return nil
    }
    return UIImage(CGImage: croppedImageRef, scale: image.scale, orientation: image.imageOrientation)
}

public func drawImageInCircle(image: UIImage?) -> UIImage? {
    guard let image = image else {
        return nil
    }
    UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
    let radius = min(image.size.width, image.size.height) / 2.0
    let rect = CGRect(origin: CGPointZero, size: image.size)
    UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
    image.drawInRect(rect)
    let processedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return processedImage
}

// MARK: - Core Image

// For more info see Core Image Integration Guide https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide

private let sharedCIContext = CIContext(options: [kCIContextPriorityRequestLow: true])

import CoreImage

public extension UIImage {
    /**
     Applies closure with a filter to the image.

     Performance considerations Chaining multiple CIFilter objects is much more efficient then using ImageProcessorComposition to combine multiple instances of CoreImageFilter class. Avoid unnecessary texture transfers between the CPU and GPU.

     - parameter context: Core Image context, uses shared context by default.
     - parameter filter: Closure for applying image filter.
     */
    public func nk_filter(context context: CIContext = sharedCIContext, closure: CoreImage.CIImage -> CoreImage.CIImage?) -> UIImage? {
        func inputImageForImage(image: UIImage) -> CoreImage.CIImage? {
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
        return UIImage(CGImage: imageRef, scale: self.scale, orientation: self.imageOrientation)
    }

    /**
     Applies filter to the image.

     - parameter context: Core Image context, uses shared context by default.
     - parameter filter: Image filter. Function automatically sets input image on the filter.
     */
    public func nk_filter(filter: CIFilter?, context: CIContext = sharedCIContext) -> UIImage? {
        guard let filter = filter else {
            return nil
        }
        return nk_filter(context: context) {
            filter.setValue($0, forKey: kCIInputImageKey)
            return filter.outputImage
        }
    }

}
