// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit
#else
import AppKit
#endif

extension ImageProcessors {
    /// Processed an image using a specified closure.
    public struct Anonymous: ImageProcessing, CustomStringConvertible {
        public let identifier: String
        private let closure: @Sendable (PlatformImage) -> PlatformImage?

        public init(id: String, _ closure: @Sendable @escaping (PlatformImage) -> PlatformImage?) {
            self.identifier = id
            self.closure = closure
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            closure(image)
        }

        public var description: String {
            "AnonymousProcessor(identifier: \(identifier)"
        }
    }
}
