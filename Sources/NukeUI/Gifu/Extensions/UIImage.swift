#if os(iOS) || os(tvOS)
import UIKit
/// A `UIImage` extension that makes it easier to resize the image and inspect its size.
extension UIImage {
  /// Resizes an image instance.
  ///
  /// - parameter size: The new size of the image.
  /// - returns: A new resized image instance.
  func resized(to size: CGSize) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    self.draw(in: CGRect(origin: CGPoint.zero, size: size))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return newImage ?? self
  }

  /// Resizes an image instance to fit inside a constraining size while keeping the aspect ratio.
  ///
  /// - parameter size: The constraining size of the image.
  /// - returns: A new resized image instance.
  func constrained(by constrainingSize: CGSize) -> UIImage {
    let newSize = size.constrained(by: constrainingSize)
    return resized(to: newSize)
  }

  /// Resizes an image instance to fill a constraining size while keeping the aspect ratio.
  ///
  /// - parameter size: The constraining size of the image.
  /// - returns: A new resized image instance.
  func filling(size fillingSize: CGSize) -> UIImage {
    let newSize = size.filling(fillingSize)
    return resized(to: newSize)
  }

  /// Returns a new `UIImage` instance using raw image data and a size.
  ///
  /// - parameter data: Raw image data.
  /// - parameter size: The size to be used to resize the new image instance.
  /// - returns: A new image instance from the passed in data.
  class func image(with data: Data, size: CGSize) -> UIImage? {
    return UIImage(data: data)?.resized(to: size)
  }

  /// Returns an image size from raw image data.
  ///
  /// - parameter data: Raw image data.
  /// - returns: The size of the image contained in the data.
  class func size(withImageData data: Data) -> CGSize? {
    return UIImage(data: data)?.size
  }
}
#endif
