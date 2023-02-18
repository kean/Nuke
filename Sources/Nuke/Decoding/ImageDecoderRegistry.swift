// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A registry of image codecs.
public final class ImageDecoderRegistry: @unchecked Sendable {
    /// A shared registry.
    public static let shared = ImageDecoderRegistry()

    private var matches = [(ImageDecodingContext) -> (any ImageDecoding)?]()
    private let lock = NSLock()

    /// Initializes a custom registry.
    public init() {
        register(ImageDecoders.Default.init)
    }

    /// Returns a decoder that matches the given context.
    public func decoder(for context: ImageDecodingContext) -> (any ImageDecoding)? {
        lock.lock()
        defer { lock.unlock() }

        for match in matches.reversed() {
            if let decoder = match(context) {
                return decoder
            }
        }
        return nil
    }

    /// Registers a decoder to be used in a given decoding context.
    ///
    /// **Progressive Decoding**
    ///
    /// The decoder is created once and is used for the entire decoding session,
    /// including progressively decoded images. If the decoder doesn't support
    /// progressive decoding, return `nil` when `isCompleted` is `false`.
    public func register(_ match: @escaping (ImageDecodingContext) -> (any ImageDecoding)?) {
        lock.lock()
        defer { lock.unlock() }

        matches.append(match)
    }

    /// Removes all registered decoders.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }

        matches = []
    }
}

/// Image decoding context used when selecting which decoder to use.
public struct ImageDecodingContext: @unchecked Sendable {
    public var request: ImageRequest
    public var data: Data
    /// Returns `true` if the download was completed.
    public var isCompleted: Bool
    public var urlResponse: URLResponse?
    public var cacheType: ImageResponse.CacheType?

    public init(request: ImageRequest, data: Data, isCompleted: Bool, urlResponse: URLResponse?, cacheType: ImageResponse.CacheType?) {
        self.request = request
        self.data = data
        self.isCompleted = isCompleted
        self.urlResponse = urlResponse
        self.cacheType = cacheType
    }
}
