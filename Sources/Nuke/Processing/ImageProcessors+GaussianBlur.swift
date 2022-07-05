// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

#if os(iOS) || os(tvOS) || os(macOS)

import Foundation
import CoreImage

extension ImageProcessors {
    /// Blurs an image using `CIGaussianBlur` filter.
    public struct GaussianBlur: ImageProcessing, Hashable, CustomStringConvertible {
        private let radius: Int

        /// Initializes the receiver with a blur radius.
        ///
        /// - parameter radius: `8` by default.
        public init(radius: Int = 8) {
            self.radius = radius
        }

        /// Applies `CIGaussianBlur` filter to the image.
        public func process(_ image: PlatformImage) -> PlatformImage? {
            try? _process(image)
        }

        /// Applies `CIGaussianBlur` filter to the image.
        public func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
            try container.map(_process(_:))
        }

        private func _process(_ image: PlatformImage) throws -> PlatformImage {
            try CoreImageFilter.applyFilter(named: "CIGaussianBlur", parameters: ["inputRadius": radius], to: image)
        }

        public var identifier: String {
            "com.github.kean/nuke/gaussian_blur?radius=\(radius)"
        }

        public var description: String {
            "GaussianBlur(radius: \(radius))"
        }
    }
}

#endif
