// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

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
    /// The default implementation returns the original data of an animated
    /// image, and calls ``encode(_:)`` with ``ImageContainer/image`` for
    /// everything else, a processed animation and a thumbnail of one included.
    ///
    /// An encoder writes a single image, so going through it would leave only
    /// the first frame of an animation. Implement this method to do otherwise.
    public func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? {
        if let animation = container.animation {
            return animation.data
        }
        // Without `isAnimatedImageParsingEnabled`, the decoder attaches the data
        // but no animation. The data alone doesn't say that it's an animation:
        // a decoder of your own can attach it to any image.
        if let data = container.data, AssetType.isAnimated(data, type: container.type) {
            return data
        }
        return self.encode(container.image)
    }
}

/// Image encoding context used when selecting which encoder to use.
public struct ImageEncodingContext: Sendable {
    public let request: ImageRequest
    public let image: PlatformImage
    public let urlResponse: URLResponse?
}
