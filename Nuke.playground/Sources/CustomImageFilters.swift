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

public func blurredImage(image: UIImage) -> UIImage? {
    // !WARNING!
    // This is just a raw example! Don't use this code!
    let filter = CIFilter(name:"CIGaussianBlur")!
    filter.setValue(6.0, forKey:"inputRadius")
    let inputImage = CIImage(image: image)!
    filter.setValue(inputImage, forKey:"inputImage")
    let context = CIContext(options: nil)
    let outputImage = context.createCGImage(filter.outputImage!, fromRect: inputImage.extent)
    return UIImage(CGImage: outputImage, scale: image.scale, orientation: image.imageOrientation)
}
