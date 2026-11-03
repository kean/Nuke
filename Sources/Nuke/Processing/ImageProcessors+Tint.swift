// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit
#else
import AppKit
#endif

extension ImageProcessors {
    /// Paints a color over an image with the `sourceAtop` blend mode.
    ///
    /// The alpha of the image is always kept, whatever the color. An opaque
    /// color replaces every pixel, which turns the image into a silhouette in
    /// that color: the way to color a template icon. A translucent color is laid
    /// over the image: the way to darken a photo under some text. A monochrome
    /// image gets the color as well. The orientation and `scale` of the input
    /// are kept.
    ///
    /// - note: A dynamic color is resolved once, when the image is processed,
    /// so the output doesn't follow a change of appearance. To get one for each
    /// appearance, pass a color resolved for it, which also gives each its own
    /// cache entries.
    public struct Tint: ImageProcessing, Hashable, CustomStringConvertible {
        private let color: PlatformColor

        /// Initializes the processor with the given color.
        public init(color: PlatformColor) {
            self.color = color
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            image.processed.byTinting(with: color)
        }

        public var identifier: String {
            "com.github.kean/nuke/tint?color=\(colorDescription)"
        }

        public var description: String {
            "Tint(color: \(colorDescription))"
        }

        // The same form as `ImageProcessingOptions.Border`: it's part of the
        // disk cache keys, and the fallback keeps a color with no sRGB
        // representation distinct.
        private var colorDescription: String {
            color.hex ?? String(describing: color)
        }
    }
}
