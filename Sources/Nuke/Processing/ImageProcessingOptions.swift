// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// A namespace with shared image processing options.
public enum ImageProcessingOptions: Sendable {

    public enum Unit: CustomStringConvertible, Sendable {
        case points
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
    /// views in which they get displayed. If you can't guarantee that, pleasee
    /// consider adding border to a view layer. This should be your primary
    /// option regardless.
    public struct Border: Hashable, CustomStringConvertible, Sendable {
        public let width: CGFloat

#if canImport(UIKit)
        public let color: UIColor

        /// - parameters:
        ///   - color: Border color.
        ///   - width: Border width.
        ///   - unit: Unit of the width.
        public init(color: UIColor, width: CGFloat = 1, unit: Unit = .points) {
            self.color = color
            self.width = width.converted(to: unit)
        }
#else
        public let color: NSColor

        /// - parameters:
        ///   - color: Border color.
        ///   - width: Border width.
        ///   - unit: Unit of the width.
        public init(color: NSColor, width: CGFloat = 1, unit: Unit = .points) {
            self.color = color
            self.width = width.converted(to: unit)
        }
#endif

        public var description: String {
            "Border(color: \(color.hex), width: \(width) pixels)"
        }
    }

    /// An option for how to resize the image.
    public enum ContentMode: CustomStringConvertible, Sendable {
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
