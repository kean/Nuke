// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

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

        @available(*, deprecated, message: "Renamed to `ImageProcessingOptions.ContentMode")
        public typealias ContentMode = ImageProcessingOptions.ContentMode

        /// Initializes the processor with the given size.
        ///
        /// - parameters:
        ///   - size: The target size.
        ///   - unit: Unit of the target size.
        ///   - contentMode: A target content mode.
        ///   - crop: If `true` will crop the image to match the target size.
        ///   Does nothing with content mode .aspectFill.
        ///  - upscale: By default, upscaling is not allowed.
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

// Adds Hashable without making changes to public CGSize API
struct ImageTargetSize: Hashable {
    let cgSize: CGSize

    /// Creates the size in pixels by scaling to the input size to the screen scale
    /// if needed.
    init(size: CGSize, unit: ImageProcessingOptions.Unit) {
        switch unit {
        case .pixels: self.cgSize = size // The size is already in pixels
        case .points: self.cgSize = size.scaled(by: Screen.scale)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cgSize.width)
        hasher.combine(cgSize.height)
    }
}
