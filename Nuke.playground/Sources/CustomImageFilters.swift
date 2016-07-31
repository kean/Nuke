import UIKit

public func cropImageToSquare(image: UIImage?) -> UIImage? {
    guard let image = image else {
        return nil
    }
    func cropRectForSize(size: CGSize) -> CGRect {
        let side = min(floor(size.width), floor(size.height))
        let origin = CGPoint(x: floor((size.width - side) / 2.0), y: floor((size.height - side) / 2.0))
        return CGRect(origin: origin, size: CGSize(width: side, height: side))
    }
    guard let cgImage = image.cgImage else {
        return nil
    }
    let bitmapSize = CGSize(width: cgImage.width, height: cgImage.height)
    guard let croppedImageRef = cgImage.cropping(to: cropRectForSize(size: bitmapSize)) else {
        return nil
    }
    return UIImage(cgImage: croppedImageRef, scale: image.scale, orientation: image.imageOrientation)
}

public func drawImageInCircle(image: UIImage?) -> UIImage? {
    guard let image = image else {
        return nil
    }
    UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
    let radius = min(image.size.width, image.size.height) / 2.0
    let rect = CGRect(origin: CGPoint.zero, size: image.size)
    UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
    image.draw(in: rect)
    let processedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return processedImage
}


// MARK - CoreImage

private let sharedContext = CIContext(options: [kCIContextPriorityRequestLow: true])

/// Core Image helper methods.
public extension UIImage {
    /**
     Applies closure with a filter to the image.
     
     Performance considerations. Chaining multiple CIFilter objects is much more efficient then using ProcessorComposition to combine multiple instances of CoreImageFilter class. Avoid unnecessary texture transfers between the CPU and GPU.
     
     - parameter context: Core Image context, uses shared context by default.
     - parameter filter: Closure for applying image filter.
     */
    public func applyFilter(context: CIContext = sharedContext, closure: (CIImage) -> CIImage?) -> UIImage? {
        func inputImage(for image: UIImage) -> CIImage? {
            if let image = image.cgImage {
                return CIImage(cgImage: image)
            }
            if let image = image.ciImage {
                return image
            }
            return nil
        }
        guard let inputImage = inputImage(for: self), let outputImage = closure(inputImage) else {
            return nil
        }
        guard let imageRef = context.createCGImage(outputImage, from: inputImage.extent) else {
            return nil
        }
        return UIImage(cgImage: imageRef, scale: scale, orientation: imageOrientation)
    }
    
    /**
     Applies filter to the image.
     
     - parameter context: Core Image context, uses shared context by default.
     - parameter filter: Image filter. Function automatically sets input image on the filter.
     */
    public func applyFilter(filter: CIFilter?, context: CIContext = sharedContext) -> UIImage? {
        guard let filter = filter else {
            return nil
        }
        return applyFilter(context: context) {
            filter.setValue($0, forKey: kCIInputImageKey)
            return filter.outputImage
        }
    }
}
