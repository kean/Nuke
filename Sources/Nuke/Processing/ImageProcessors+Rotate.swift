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
    /// Rotates an image clockwise by an angle in degrees.
    ///
    /// It acts on the image as it's displayed, so the orientation of a photo
    /// is taken into account, and the output has it baked into the pixels. The
    /// output keeps the `scale` of the input.
    ///
    /// A multiple of 90 degrees moves the pixels without resampling them, and
    /// an opaque image stays opaque.
    ///
    /// Any other angle resamples the image and grows the canvas to the bounding
    /// box of the rotated image, leaving the corners transparent, so the output
    /// has an alpha channel even if the input was opaque.
    public struct Rotate: ImageProcessing, Hashable, CustomStringConvertible {
        /// In `0..<360`, so that the same rotation has the same identifier.
        private let degrees: CGFloat

        /// Initializes the processor with the given angle.
        ///
        /// - parameter degrees: The angle, clockwise. Negative angles and the
        /// angles over a full turn are allowed.
        public init(degrees: CGFloat) {
            // Adding zero turns the `-0.0` of a negative multiple of 360 into
            // `0.0`: they are equal but they don't print the same.
            let remainder = degrees.truncatingRemainder(dividingBy: 360) + 0
            let positive = remainder < 0 ? remainder + 360 : remainder
            // The sum rounds to 360 for a tiny negative remainder. An angle
            // that isn't finite stays NaN, which fails the request.
            self.degrees = positive >= 360 ? 0 : positive
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            image.processed.byRotating(degrees: degrees)
        }

        public var identifier: String {
            "com.github.kean/nuke/rotate?degrees=\(degrees)"
        }

        public var description: String {
            "Rotate(degrees: \(degrees))"
        }
    }
}
