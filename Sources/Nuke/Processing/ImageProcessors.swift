// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

#if os(macOS)
import Cocoa
#endif

/// A namespace for all processors that implement ``ImageProcessing`` protocol.
public enum ImageProcessors {}

extension ImageProcessing where Self == ImageProcessors.Resize {
    /// Scales an image to a specified size.
    ///
    /// - parameters
    ///   - size: The target size.
    ///   - unit: Unit of the target size.
    ///   - contentMode: Target content mode.
    ///   - crop: If `true` will crop the image to match the target size. Does
    ///   nothing with content mode .aspectFill. `false` by default.
    ///   - upscale: Upscaling is not allowed by default.
    public static func resize(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ImageProcessors.Resize.ContentMode = .aspectFill, crop: Bool = false, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(size: size, unit: unit, contentMode: contentMode, crop: crop, upscale: upscale)
    }

    /// Scales an image to the given width preserving aspect ratio.
    ///
    /// - parameters:
    ///   - width: The target width.
    ///   - unit: Unit of the target size.
    ///   - upscale: `false` by default.
    public static func resize(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(width: width, unit: unit, upscale: upscale)
    }

    /// Scales an image to the given height preserving aspect ratio.
    ///
    /// - parameters:
    ///   - height: The target height.
    ///   - unit: Unit of the target size.
    ///   - upscale: `false` by default.
    public static func resize(height: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(height: height, unit: unit, upscale: upscale)
    }
}

extension ImageProcessing where Self == ImageProcessors.Circle {
    /// Rounds the corners of an image into a circle. If the image is not a square,
    /// crops it to a square first.
    ///
    /// - parameter border: `nil` by default.
    public static func circle(border: ImageProcessingOptions.Border? = nil) -> ImageProcessors.Circle {
        ImageProcessors.Circle(border: border)
    }
}

extension ImageProcessing where Self == ImageProcessors.RoundedCorners {
    /// Rounds the corners of an image to the specified radius.
    ///
    /// - parameters:
    ///   - radius: The radius of the corners.
    ///   - unit: Unit of the radius.
    ///   - border: An optional border drawn around the image.
    ///
    /// - important: In order for the corners to be displayed correctly, the image must exactly match the size
    /// of the image view in which it will be displayed. See ``ImageProcessors/Resize`` for more info.
    public static func roundedCorners(radius: CGFloat, unit: ImageProcessingOptions.Unit = .points, border: ImageProcessingOptions.Border? = nil) -> ImageProcessors.RoundedCorners {
        ImageProcessors.RoundedCorners(radius: radius, unit: unit, border: border)
    }
}

extension ImageProcessing where Self == ImageProcessors.Anonymous {
    /// Creates a custom processor with a given closure.
    ///
    /// - parameters:
    ///   - id: Uniquely identifies the operation performed by the processor.
    ///   - closure: A closure that transforms the images.
    public static func process(id: String, _ closure: @Sendable @escaping (PlatformImage) -> PlatformImage?) -> ImageProcessors.Anonymous {
        ImageProcessors.Anonymous(id: id, closure)
    }
}

#if os(iOS) || os(tvOS) || os(macOS)

extension ImageProcessing where Self == ImageProcessors.CoreImageFilter {
    /// Applies Core Image filter – `CIFilter` – to the image.
    ///
    /// - parameter identifier: Uniquely identifies the processor.
    public static func coreImageFilter(name: String, parameters: [String: Any], identifier: String) -> ImageProcessors.CoreImageFilter {
        ImageProcessors.CoreImageFilter(name: name, parameters: parameters, identifier: identifier)
    }

    /// Applies Core Image filter – `CIFilter` – to the image.
    ///
    public static func coreImageFilter(name: String) -> ImageProcessors.CoreImageFilter {
        ImageProcessors.CoreImageFilter(name: name)
    }
}

extension ImageProcessing where Self == ImageProcessors.GaussianBlur {
    /// Blurs an image using `CIGaussianBlur` filter.
    ///
    /// - parameter radius: `8` by default.
    public static func gaussianBlur(radius: Int = 8) -> ImageProcessors.GaussianBlur {
        ImageProcessors.GaussianBlur(radius: radius)
    }
}

#endif
