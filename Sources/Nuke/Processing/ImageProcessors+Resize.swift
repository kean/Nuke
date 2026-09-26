// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics

#if !os(macOS)
import UIKit
#else
import AppKit
#endif

extension ImageProcessors {
    /// Scales an image to a specified size.
    public struct Resize: ImageProcessing, Hashable, CustomStringConvertible {
        private let size: ImageTargetSize
        private let contentMode: ImageProcessingOptions.ContentMode
        private let crop: Bool
        private let upscale: Bool
        private let fit: Fit

        /// Which dimensions of ``size`` constrain the output. `init(width:)`
        /// and `init(height:)` fix one dimension and leave the other one to
        /// follow the aspect ratio of the image.
        private enum Fit {
            case size, width, height
        }

        /// Initializes the processor with the given size.
        ///
        /// - parameters:
        ///   - size: The target size.
        ///   - unit: Unit of the target size.
        ///   - contentMode: A target content mode.
        ///   - crop: If `true`, crops the image to exactly match the target size.
        ///   Has no effect when `contentMode` is `.aspectFill`.
        ///   - upscale: By default, upscaling is not allowed.
        public init(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ImageProcessingOptions.ContentMode = .aspectFill, crop: Bool = false, upscale: Bool = false) {
            self.init(size: size, unit: unit, contentMode: contentMode, crop: crop, upscale: upscale, fit: .size)
        }

        private init(size: CGSize, unit: ImageProcessingOptions.Unit, contentMode: ImageProcessingOptions.ContentMode, crop: Bool, upscale: Bool, fit: Fit) {
            self.size = ImageTargetSize(size: size, unit: unit)
            self.contentMode = contentMode
            self.crop = crop
            self.upscale = upscale
            self.fit = fit
        }

        /// Scales an image to the given width preserving aspect ratio.
        ///
        /// - parameters:
        ///   - width: The target width.
        ///   - unit: Unit of the target size.
        ///   - upscale: `false` by default.
        public init(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) {
            // The placeholder height is part of the identifier, and with it of
            // the disk cache keys. `fit` keeps it from constraining the output.
            self.init(size: CGSize(width: width, height: 9999), unit: unit, contentMode: .aspectFit, crop: false, upscale: upscale, fit: .width)
        }

        /// Scales an image to the given height preserving aspect ratio.
        ///
        /// - parameters:
        ///   - height: The target height.
        ///   - unit: Unit of the target size.
        ///   - upscale: By default, upscaling is not allowed.
        public init(height: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) {
            self.init(size: CGSize(width: 9999, height: height), unit: unit, contentMode: .aspectFit, crop: false, upscale: upscale, fit: .height)
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            if crop && contentMode == .aspectFill {
                return image.processed.byResizingAndCropping(to: size.cgSize, upscale: upscale)
            }
            return image.processed.byResizing(to: targetSize(for: image), contentMode: contentMode, upscale: upscale)
        }

        /// Returns the target size in pixels, as the image is oriented for
        /// display. For `.width` and `.height`, the other dimension follows
        /// the aspect ratio of the image instead of the placeholder in `size`,
        /// which used to cap it and shrink tall or wide images below the
        /// requested size.
        private func targetSize(for image: PlatformImage) -> CGSize {
            guard fit != .size, let cgImage = image.cgImage else {
                return size.cgSize
            }
            var imageSize = cgImage.size
#if canImport(UIKit)
            imageSize = imageSize.rotatedForOrientation(CGImagePropertyOrientation(image.imageOrientation))
#endif
            switch fit {
            case .width:
                let width = CGFloat(size.width)
                return CGSize(width: width, height: width * imageSize.height / imageSize.width)
            case .height:
                let height = CGFloat(size.height)
                return CGSize(width: height * imageSize.width / imageSize.height, height: height)
            case .size:
                return size.cgSize
            }
        }

        public var identifier: String {
            // Appended piece by piece instead of interpolated: interpolating a
            // `CGSize` looks up its conformances at runtime and builds its
            // `debugDescription`, "(width, height)", as an intermediate string.
            // The output is the same byte for byte – it's part of the disk cache key.
            let size = self.size.cgSize
            var identifier = "com.github.kean/nuke/resize?s=("
            identifier.reserveCapacity(96)
            identifier += size.width.description
            identifier += ", "
            identifier += size.height.description
            identifier += "),cm="
            identifier += contentMode.description
            identifier += crop ? ",crop=true" : ",crop=false"
            identifier += upscale ? ",upscale=true" : ",upscale=false"
            return identifier
        }

        public var description: String {
            "Resize(size: \(size.cgSize) pixels, contentMode: \(contentMode), crop: \(crop), upscale: \(upscale))"
        }
    }
}

// Adds Hashable without making changes to public CGSize API. It uses `Float`
// to reduce memory size.
struct ImageTargetSize: Hashable {
    let width: Float
    let height: Float

    var cgSize: CGSize { CGSize(width: Double(width), height: Double(height)) }

    init(maxPixelSize: CGFloat) {
        (width, height) = (Float(maxPixelSize), 0)
    }

    /// Creates the size in pixels by scaling to the input size to the screen scale
    /// if needed.
    init(size: CGSize, unit: ImageProcessingOptions.Unit) {
        switch unit {
        case .pixels:
            (width, height) = (Float(size.width), Float(size.height))
        case .points:
            let scaled = size.scaled(by: Screen.scale)
            (width, height) = (Float(scaled.width), Float(scaled.height))
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}
