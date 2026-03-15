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
            self.size = ImageTargetSize(size: size, unit: unit)
            self.contentMode = contentMode
            self.crop = crop
            self.upscale = upscale
        }

        /// Scales an image to the given width preserving aspect ratio.
        ///
        /// - parameters:
        ///   - width: The target width.
        ///   - unit: Unit of the target size.
        ///   - upscale: `false` by default.
        public init(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) {
            self.init(size: CGSize(width: width, height: 9999), unit: unit, contentMode: .aspectFit, crop: false, upscale: upscale)
        }

        /// Scales an image to the given height preserving aspect ratio.
        ///
        /// - parameters:
        ///   - height: The target height.
        ///   - unit: Unit of the target size.
        ///   - upscale: By default, upscaling is not allowed.
        public init(height: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) {
            self.init(size: CGSize(width: 9999, height: height), unit: unit, contentMode: .aspectFit, crop: false, upscale: upscale)
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            if crop && contentMode == .aspectFill {
                return image.processed.byResizingAndCropping(to: size.cgSize)
            }
            return image.processed.byResizing(to: size.cgSize, contentMode: contentMode, upscale: upscale)
        }

        public var identifier: String {
            "com.github.kean/nuke/resize?s=\(size.cgSize),cm=\(contentMode),crop=\(crop),upscale=\(upscale)"
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

    init(maxPixelSize: Float) {
        (width, height) = (maxPixelSize, 0)
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
