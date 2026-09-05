// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// A registry of image codecs.
public final class ImageDecoderRegistry: Sendable {
    /// A shared registry.
    public static let shared = ImageDecoderRegistry()

    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var registrations: [Registration] = []
        var nextID = 0
    }

    private struct Registration {
        let token: RegistrationToken
        let match: @Sendable (ImageDecodingContext) -> (any ImageDecoding)?
    }

    /// An opaque token that identifies a registered decoder.
    public struct RegistrationToken: Hashable, Sendable {
        fileprivate let id: Int
    }

    /// Initializes a custom registry.
    public init() {
        register(ImageDecoders.Default.init)
    }

    /// Returns a decoder that matches the given context.
    public func decoder(for context: ImageDecodingContext) -> (any ImageDecoding)? {
        // Iterate over a snapshot: the closures are provided by the user and
        // must never be called while holding the lock.
        for registration in state.withLock({ $0.registrations }).reversed() {
            if let decoder = registration.match(context) {
                return decoder
            }
        }
        return nil
    }

    /// Registers a decoder to be used in a given decoding context.
    ///
    /// The decoders are evaluated in the reverse order of registration: the
    /// most recently registered decoder is asked first.
    ///
    /// **Progressive Decoding**
    ///
    /// The decoder is created once and is used for the entire decoding session,
    /// including progressively decoded images. If the decoder doesn't support
    /// progressive decoding, return `nil` when `isCompleted` is `false`.
    ///
    /// - returns: A token that can be passed to ``unregister(_:)`` to remove
    /// the decoder. Can be safely ignored.
    @discardableResult
    public func register(_ match: @escaping @Sendable (ImageDecodingContext) -> (any ImageDecoding)?) -> RegistrationToken {
        state.withLock {
            let token = RegistrationToken(id: $0.nextID)
            $0.nextID += 1
            $0.registrations.append(Registration(token: token, match: match))
            return token
        }
    }

    /// Removes the decoder registered with the given token. Does nothing if the
    /// decoder is no longer registered.
    public func unregister(_ token: RegistrationToken) {
        state.withLock { state in
            state.registrations.removeAll { $0.token == token }
        }
    }

    /// Removes all registered decoders, including the default one.
    public func clear() {
        state.withLock { $0.registrations.removeAll() }
    }
}

/// Image decoding context used when selecting which decoder to use.
public struct ImageDecodingContext: Sendable {
    public var request: ImageRequest
    public var data: Data
    /// Returns `true` if the download was completed.
    public var isCompleted: Bool
    public var urlResponse: URLResponse?
    public var cacheType: ImageResponse.CacheType?
    /// The strategy a decoder uses to produce previews from the partially
    /// downloaded data.
    ///
    /// The pipeline resolves it with
    /// ``ImagePipeline/Delegate/previewPolicy(for:pipeline:)`` and only for
    /// the contexts where ``isCompleted`` is `false`.
    public var previewPolicy: ImagePipeline.PreviewPolicy
    /// Whether a decoder parses the metadata of the animated images it
    /// recognizes and attaches it to ``ImageContainer/animation``.
    ///
    /// The pipeline resolves it from
    /// ``ImagePipeline/Configuration-swift.struct/isAnimatedImageParsingEnabled``.
    public var isAnimatedImageParsingEnabled: Bool

    public init(request: ImageRequest, data: Data, isCompleted: Bool = true, urlResponse: URLResponse? = nil, cacheType: ImageResponse.CacheType? = nil, previewPolicy: ImagePipeline.PreviewPolicy = .incremental, isAnimatedImageParsingEnabled: Bool = true) {
        self.request = request
        self.data = data
        self.isCompleted = isCompleted
        self.urlResponse = urlResponse
        self.cacheType = cacheType
        self.previewPolicy = previewPolicy
        self.isAnimatedImageParsingEnabled = isAnimatedImageParsingEnabled
    }
}
