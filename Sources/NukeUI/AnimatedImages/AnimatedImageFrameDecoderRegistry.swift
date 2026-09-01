// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import os

/// The frame decoders the players pick from.
///
/// A player asks the shared registry which ``AnimatedImageFrameDecoding`` to
/// produce the frames of an animation with, and falls back to
/// ``AnimatedImageFrameDecoder`` – Image I/O – when nothing matches. Register
/// one to plug in a codec of your own:
///
/// ```swift
/// AnimatedImageFrameDecoderRegistry.shared.register { context in
///     guard AssetType(context.source.data) == .webp else { return nil } // Pass
///     return WebPFrameDecoder(source: context.source, maxPixelSize: context.maxPixelSize)
/// }
/// ```
///
/// The decoder is chosen once per animation and size, when the first player
/// asks for its frames, so registering at startup is the way to do it: a
/// registration made later doesn't change the frames already being produced.
public final class AnimatedImageFrameDecoderRegistry: Sendable {
    /// The registry every player consults.
    public static let shared = AnimatedImageFrameDecoderRegistry()

    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var registrations: [Registration] = []
        var nextID = 0
    }

    private struct Registration {
        let token: RegistrationToken
        let match: @Sendable (AnimatedImageFrameDecodingContext) -> (any AnimatedImageFrameDecoding)?
    }

    /// An opaque token that identifies a registered decoder.
    public struct RegistrationToken: Hashable, Sendable {
        fileprivate let id: Int
    }

    /// Creates an empty registry.
    public init() {}

    /// Returns the decoder to produce the frames of the given animation with:
    /// the most recently registered one that matches it, or
    /// ``AnimatedImageFrameDecoder`` when none does.
    public func decoder(for context: AnimatedImageFrameDecodingContext) -> any AnimatedImageFrameDecoding {
        // Iterate over a snapshot: the closures are provided by the user and
        // must never be called while holding the lock.
        for registration in state.withLock({ $0.registrations }).reversed() {
            if let decoder = registration.match(context) {
                return decoder
            }
        }
        return AnimatedImageFrameDecoder(source: context.source, maxPixelSize: context.maxPixelSize)
    }

    /// Registers a decoder to produce the frames of the animations it matches.
    ///
    /// The decoders are evaluated in the reverse order of registration: the
    /// most recently registered one is asked first, and returning `nil` passes
    /// the animation to the next one.
    ///
    /// - returns: A token that can be passed to ``unregister(_:)``. Can be
    /// safely ignored.
    @discardableResult
    public func register(
        _ match: @escaping @Sendable (AnimatedImageFrameDecodingContext) -> (any AnimatedImageFrameDecoding)?
    ) -> RegistrationToken {
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
        state.withLock { $0.registrations.removeAll { $0.token == token } }
    }

    /// Removes every registered decoder, leaving Image I/O.
    public func clear() {
        state.withLock { $0.registrations.removeAll() }
    }
}

/// What a frame decoder is picked for.
public struct AnimatedImageFrameDecodingContext: Sendable {
    /// The animation whose frames are to be produced. Its
    /// ``Nuke/AnimatedImageSource/data`` is the encoded image.
    public let source: AnimatedImageSource

    /// The longest side, in pixels, the frames should have, or `nil` for the
    /// size the animation is stored at.
    ///
    /// It comes from ``AnimatedImagePlayer/Options/maxPixelSize``, and a
    /// decoder is expected to honor it: the player has budgeted the memory for
    /// frames of that size.
    public let maxPixelSize: CGFloat?

    /// Creates a context.
    public init(source: AnimatedImageSource, maxPixelSize: CGFloat? = nil) {
        self.source = source
        self.maxPixelSize = maxPixelSize
    }
}
