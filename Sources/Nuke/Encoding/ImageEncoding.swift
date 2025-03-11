// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

import ImageIO

// MARK: - ImageEncoding

/// An image encoder.
public protocol ImageEncoding: Sendable {
    /// Encodes the given image.
    func encode(_ image: PlatformImage) -> Data?

    /// An optional method which encodes the given image container.
    func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data?
}

extension ImageEncoding {
    public func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? {
        if container.type == .gif {
            return container.data
        }
        return self.encode(container.image)
    }
}

// note: @unchecked was added to surpress build errors with NSImage on macOS

/// Image encoding context used when selecting which encoder to use.
public struct ImageEncodingContext: @unchecked Sendable {
    public let request: ImageRequest
    public let image: PlatformImage
    public let urlResponse: URLResponse?
}
