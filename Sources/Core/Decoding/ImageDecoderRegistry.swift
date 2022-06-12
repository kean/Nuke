// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageDecoderRegistry

/// A registry of image codecs.
public final class ImageDecoderRegistry {
    /// A shared registry.
    public static let shared = ImageDecoderRegistry()

    private var matches = [(ImageDecodingContext) -> ImageDecoding?]()

    /// Initializes a custom registry.
    init() {
        register(ImageDecoders.Default.init)
        #if !os(watchOS)
        register(ImageDecoders.Video.init)
        #endif
    }

    /// Returns a decoder that matches the given context.
    public func decoder(for context: ImageDecodingContext) -> ImageDecoding? {
        for match in matches.reversed() {
            if let decoder = match(context) {
                return decoder
            }
        }
        return nil
    }

    // MARK: - Registering

    /// Registers a decoder to be used in a given decoding context.
    ///
    /// **Progressive Decoding**
    ///
    /// The decoder is created once and is used for the entire decoding session,
    /// including progressively decoded images. If the decoder doesn't support
    /// progressive decoding, return `nil` when `isCompleted` is `false`.
    public func register(_ match: @escaping (ImageDecodingContext) -> ImageDecoding?) {
        matches.append(match)
    }

    /// Removes all registered decoders.
    public func clear() {
        matches = []
    }
}

/// Image decoding context used when selecting which decoder to use.
public struct ImageDecodingContext {
    public var request: ImageRequest
    public var data: Data
    /// Returns `true` if the download was completed.
    public var isCompleted: Bool
    public var urlResponse: URLResponse?

    public init(request: ImageRequest, data: Data, isCompleted: Bool, urlResponse: URLResponse?) {
        self.request = request
        self.data = data
        self.isCompleted = isCompleted
        self.urlResponse = urlResponse
    }
}
