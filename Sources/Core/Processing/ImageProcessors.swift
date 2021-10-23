// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A namespace for all processors that implement `ImageProcessing` protocol.
public enum ImageProcessors {}

#if swift(>=5.5)
extension ImageProcessing where Self == ImageProcessors.Resize {
    /// Scales an image to a specified size.
    ///
    /// - parameter size: The target size.
    /// - parameter unit: Unit of the target size, `.points` by default.
    /// - parameter contentMode: `.aspectFill` by default.
    /// - parameter crop: If `true` will crop the image to match the target size.
    /// Does nothing with content mode .aspectFill. `false` by default.
    /// - parameter upscale: `false` by default.
    public static func resize(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ImageProcessors.Resize.ContentMode = .aspectFill, crop: Bool = false, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(size: size, unit: unit, contentMode: contentMode, crop: crop, upscale: upscale)
    }
    
    /// Scales an image to the given width preserving aspect ratio.
    ///
    /// - parameter width: The target width.
    /// - parameter unit: Unit of the target size, `.points` by default.
    /// - parameter upscale: `false` by default.
    public static func resize(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(width: width, unit: unit, upscale: upscale)
    }

    /// Scales an image to the given height preserving aspect ratio.
    ///
    /// - parameter height: The target height.
    /// - parameter unit: Unit of the target size, `.points` by default.
    /// - parameter upscale: `false` by default.
    public static func resize(height: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(height: height, unit: unit, upscale: upscale)
    }
}
#endif
