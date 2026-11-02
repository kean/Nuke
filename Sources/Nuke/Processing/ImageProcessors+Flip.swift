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
    /// Mirrors an image.
    ///
    /// It acts on the image as it's displayed, so the orientation of a photo
    /// is taken into account, and the output has it baked into the pixels. The
    /// pixels aren't resampled, and the output keeps the `scale` of the input.
    ///
    /// To flip in both directions, use ``ImageProcessors/Rotate`` with `180`.
    public struct Flip: ImageProcessing, Hashable, CustomStringConvertible {
        private let direction: Direction

        /// The direction to mirror an image in.
        @frozen public enum Direction: CustomStringConvertible, Sendable {
            /// Swaps the left and the right of the image.
            case horizontal
            /// Swaps the top and the bottom of the image.
            case vertical

            public var description: String {
                switch self {
                case .horizontal: return "horizontal"
                case .vertical: return "vertical"
                }
            }
        }

        /// Initializes the processor with the given direction.
        public init(_ direction: Direction) {
            self.direction = direction
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            image.processed.byFlipping(direction)
        }

        public var identifier: String {
            "com.github.kean/nuke/flip?direction=\(direction)"
        }

        public var description: String {
            "Flip(direction: \(direction))"
        }
    }
}
