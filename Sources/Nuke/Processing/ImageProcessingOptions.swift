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

/// A namespace with shared image processing options.
public enum ImageProcessingOptions: Sendable {

    /// A unit for size and radius values used in image processors.
    @frozen public enum Unit: CustomStringConvertible, Sendable {
        /// Points, automatically scaled to the screen's pixel density.
        case points
        /// Pixels, used as-is without any scaling.
        case pixels

        public var description: String {
            switch self {
            case .points: return "points"
            case .pixels: return "pixels"
            }
        }
    }

    /// Draws a border.
    ///
    /// - important: To make sure that the border looks the way you expect,
    /// make sure that the images you display exactly match the size of the
    /// views in which they get displayed. If you can't guarantee that, please
    /// consider adding border to a view layer. This should be your primary
    /// option regardless.
    public struct Border: Hashable, CustomStringConvertible, Sendable {
        /// The border width in pixels.
        ///
        /// The initializer converts the given width to pixels using the unit
        /// you pass, so this is not necessarily the value you passed in.
        public let widthInPixels: CGFloat

        @available(*, deprecated, renamed: "widthInPixels", message: "Deprecated in Nuke 14.0. Renamed to `widthInPixels` to reflect what it returns: the width converted to pixels, not the value passed to the initializer.")
        public var width: CGFloat { widthInPixels }

#if canImport(UIKit)
        public let color: UIColor

        /// - parameters:
        ///   - color: Border color.
        ///   - width: Border width, in the given unit.
        ///   - unit: Unit of the width. The width is converted to pixels and
        ///   is available as ``widthInPixels``.
        public init(color: UIColor, width: CGFloat = 1, unit: Unit = .points) {
            self.color = color
            self.widthInPixels = width.converted(to: unit)
        }
#else
        public let color: NSColor

        /// - parameters:
        ///   - color: Border color.
        ///   - width: Border width, in the given unit.
        ///   - unit: Unit of the width. The width is converted to pixels and
        ///   is available as ``widthInPixels``.
        public init(color: NSColor, width: CGFloat = 1, unit: Unit = .points) {
            self.color = color
            self.widthInPixels = width.converted(to: unit)
        }
#endif

        public var description: String {
            // `hex` is `nil` for the colors with no sRGB representation, e.g.
            // pattern colors. The description is part of the identifiers of the
            // processors that draw borders, so the fallback has to stay
            // distinct per color instead of collapsing every such color onto
            // the same – and, in the case of "#00000000", already taken – value.
            "Border(color: \(color.hex ?? String(describing: color)), width: \(widthInPixels) pixels)"
        }
    }

    /// An option for how to resize the image.
    @frozen public enum ContentMode: CustomStringConvertible, Sendable {
        /// Scales the image so that it completely fills the target area.
        /// Maintains the aspect ratio of the original image.
        case aspectFill

        /// Scales the image so that it fits the target size. Maintains the
        /// aspect ratio of the original image.
        case aspectFit

        public var description: String {
            switch self {
            case .aspectFill: return ".aspectFill"
            case .aspectFit: return ".aspectFit"
            }
        }
    }
}
