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
    /// Crops an image to a rectangle.
    ///
    /// The rectangle is measured from the top-left corner of the image as it's
    /// displayed, so the orientation of a photo is taken into account, and the
    /// output has it baked into the pixels. The output keeps the `scale` of the
    /// input.
    ///
    /// The part of the rectangle outside of the image is ignored, and the
    /// output is what is left: the processor fails if nothing is, which fails
    /// the request. A fractional rectangle is rounded out to whole pixels.
    ///
    /// Processors run in order, so the rectangle applies to the image the
    /// previous one produced. To crop to a size around the center of an image,
    /// use ``ImageProcessors/Resize`` with `crop: true`.
    public struct Crop: ImageProcessing, Hashable, CustomStringConvertible {
        // In pixels. `Float`, as in `ImageTargetSize`, fits the processor in the
        // inline storage of an `any ImageProcessing`, which a `CGRect` wouldn't.
        private let x: Float
        private let y: Float
        private let width: Float
        private let height: Float

        /// Initializes the processor with the given rectangle.
        ///
        /// - parameters:
        ///   - rect: The rectangle to keep.
        ///   - unit: Unit of the rectangle. As with the other processors,
        ///   `.points` are converted with the scale of the screen, not of the
        ///   image, which matches an image the size of its view. Use `.pixels`
        ///   for a rectangle in the coordinates of the image file.
        public init(rect: CGRect, unit: ImageProcessingOptions.Unit = .points) {
            let rect = rect.standardized
            let scale = CGFloat(1).converted(to: unit)
            self.x = Float(rect.minX * scale)
            self.y = Float(rect.minY * scale)
            self.width = Float(rect.width * scale)
            self.height = Float(rect.height * scale)
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            image.processed.byCropping(to: CGRect(x: Double(x), y: Double(y), width: Double(width), height: Double(height)))
        }

        public var identifier: String {
            "com.github.kean/nuke/crop?x=\(x),y=\(y),width=\(width),height=\(height)"
        }

        public var description: String {
            "Crop(rect: (\(x), \(y), \(width), \(height)) pixels)"
        }
    }
}
