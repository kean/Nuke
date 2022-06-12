#if os(iOS) || os(tvOS)
import ImageIO
import MobileCoreServices
import UIKit

typealias GIFProperties = [String: Double]

/// Most GIFs run between 15 and 24 Frames per second.
///
/// If a GIF does not have (frame-)durations stored in its metadata,
/// this default framerate is used to calculate the GIFs duration.
private let defaultFrameRate: Double = 15.0

/// Default Fallback Frame-Duration based on `defaultFrameRate`
private let defaultFrameDuration: Double = 1 / defaultFrameRate

/// Threshold used in `capDuration` for a FrameDuration
private let capDurationThreshold: Double = 0.02 - Double.ulpOfOne

/// Frameduration used, if a frame-duration is below `capDurationThreshold`
private let minFrameDuration: Double = 0.1

/// Retruns the duration of a frame at a specific index using an image source (an `CGImageSource` instance).
///
/// - returns: A frame duration.
func CGImageFrameDuration(with imageSource: CGImageSource, atIndex index: Int) -> TimeInterval {
  guard imageSource.isAnimatedGIF else { return 0.0 }
  
  // Return nil, if the properties do not store a FrameDuration or FrameDuration <= 0
  guard let GIFProperties = imageSource.properties(at: index),
        let duration = frameDuration(with: GIFProperties),
        duration > 0 else { return defaultFrameDuration }
  
  return capDuration(with: duration)
}

/// Ensures that a duration is never smaller than a threshold value.
///
/// - returns: A capped frame duration.
func capDuration(with duration: Double) -> Double {
  let cappedDuration = duration < capDurationThreshold ? 0.1 : duration
  return cappedDuration
}

/// Returns a frame duration from a `GIFProperties` dictionary.
///
/// - returns: A frame duration.
func frameDuration(with properties: GIFProperties) -> Double? {
  guard let unclampedDelayTime = properties[String(kCGImagePropertyGIFUnclampedDelayTime)],
        let delayTime = properties[String(kCGImagePropertyGIFDelayTime)]
  else { return nil }
  
  return duration(withUnclampedTime: unclampedDelayTime, andClampedTime: delayTime)
}

/// Calculates frame duration based on both clamped and unclamped times.
///
/// - returns: A frame duration.
func duration(withUnclampedTime unclampedDelayTime: Double, andClampedTime delayTime: Double) -> Double? {
  let delayArray = [unclampedDelayTime, delayTime]
  return delayArray.filter({ $0 >= 0 }).first
}

/// An extension of `CGImageSourceRef` that adds GIF introspection and easier property retrieval.
extension CGImageSource {
  /// Returns whether the image source contains an animated GIF.
  ///
  /// - returns: A boolean value that is `true` if the image source contains animated GIF data.
  var isAnimatedGIF: Bool {
    let isTypeGIF = UTTypeConformsTo(CGImageSourceGetType(self) ?? "" as CFString, kUTTypeGIF)
    let imageCount = CGImageSourceGetCount(self)
    return isTypeGIF != false && imageCount > 1
  }
  
  /// Returns the GIF properties at a specific index.
  ///
  /// - parameter index: The index of the GIF properties to retrieve.
  /// - returns: A dictionary containing the GIF properties at the passed in index.
  func properties(at index: Int) -> GIFProperties? {
    guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [String: AnyObject] else { return nil }
    return imageProperties[String(kCGImagePropertyGIFDictionary)] as? GIFProperties
  }
}

#endif
