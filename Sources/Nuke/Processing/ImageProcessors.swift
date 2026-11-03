// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// A namespace for all processors that implement ``ImageProcessing`` protocol.
public enum ImageProcessors {}

extension ImageProcessing where Self == ImageProcessors.Resize {
    /// Scales an image to a specified size.
    ///
    /// - parameters:
    ///   - size: The target size.
    ///   - unit: Unit of the target size. By default, `.points`.
    ///   - contentMode: Target content mode.
    ///   - crop: If `true` will crop the image to match the target size. Has
    ///   no effect when `contentMode` is `.aspectFit`. `false` by default.
    ///   - upscale: Upscaling is not allowed by default.
    public static func resize(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ImageProcessingOptions.ContentMode = .aspectFill, crop: Bool = false, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(size: size, unit: unit, contentMode: contentMode, crop: crop, upscale: upscale)
    }

    /// Scales an image to the given width preserving aspect ratio.
    ///
    /// - parameters:
    ///   - width: The target width.
    ///   - unit: Unit of the target size. By default, `.points`.
    ///   - upscale: `false` by default.
    public static func resize(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(width: width, unit: unit, upscale: upscale)
    }

    /// Scales an image to the given height preserving aspect ratio.
    ///
    /// - parameters:
    ///   - height: The target height.
    ///   - unit: Unit of the target size. By default, `.points`.
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

extension ImageProcessing where Self == ImageProcessors.Crop {
    /// Crops an image to the given rectangle, measured from the top-left
    /// corner of the image as it's displayed.
    ///
    /// - parameters:
    ///   - rect: The rectangle to keep. The part of it outside of the image is
    ///   ignored, and the processor fails if nothing is left.
    ///   - unit: Unit of the rectangle. By default, `.points`.
    public static func crop(rect: CGRect, unit: ImageProcessingOptions.Unit = .points) -> ImageProcessors.Crop {
        ImageProcessors.Crop(rect: rect, unit: unit)
    }
}

extension ImageProcessing where Self == ImageProcessors.Flip {
    /// Mirrors an image as it's displayed.
    ///
    /// - parameter direction: `.horizontal` swaps left and right, and
    /// `.vertical` swaps top and bottom.
    public static func flip(_ direction: ImageProcessors.Flip.Direction) -> ImageProcessors.Flip {
        ImageProcessors.Flip(direction)
    }
}

extension ImageProcessing where Self == ImageProcessors.Rotate {
    /// Rotates an image as it's displayed.
    ///
    /// - parameter degrees: The angle, clockwise. A multiple of 90 degrees
    /// moves the pixels without resampling them. Any other angle grows the
    /// canvas to fit the image, and leaves the corners transparent.
    public static func rotate(degrees: CGFloat) -> ImageProcessors.Rotate {
        ImageProcessors.Rotate(degrees: degrees)
    }
}

extension ImageProcessing where Self == ImageProcessors.Tint {
    /// Paints a color over an image, keeping its alpha.
    ///
    /// - parameter color: An opaque color turns the image into a silhouette,
    /// and a translucent one is laid over it.
    public static func tint(color: PlatformColor) -> ImageProcessors.Tint {
        ImageProcessors.Tint(color: color)
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

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

extension ImageProcessing where Self == ImageProcessors.CoreImageFilter {
    /// Applies Core Image filter – `CIFilter` – to the image.
    ///
    /// - parameter name: The name of the `CIFilter` to apply.
    /// - parameter parameters: The parameters for the filter.
    /// - parameter identifier: Uniquely identifies the processor.
    public static func coreImageFilter(name: String, parameters: [String: any Sendable], identifier: String) -> ImageProcessors.CoreImageFilter {
        ImageProcessors.CoreImageFilter(name: name, parameters: parameters, identifier: identifier)
    }

    /// Applies Core Image filter – `CIFilter` – to the image.
    ///
    public static func coreImageFilter(name: String) -> ImageProcessors.CoreImageFilter {
        ImageProcessors.CoreImageFilter(name: name)
    }

    public static func coreImageFilter(_ filter: CIFilter, identifier: String) -> ImageProcessors.CoreImageFilter {
        ImageProcessors.CoreImageFilter(filter, identifier: identifier)
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
