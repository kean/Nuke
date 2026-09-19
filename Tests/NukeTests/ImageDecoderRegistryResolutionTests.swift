// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// How ``ImageDecoderRegistry`` walks the registered closures: what they are
/// given, when the walk stops, and what the closures may do to the registry
/// while it is walking.
@Suite(.timeLimit(.minutes(5)))
struct ImageDecoderRegistryResolutionTests {

    // MARK: Context

    @Test func matchClosureReceivesTheContextUnchanged() throws {
        // Given
        let registry = ImageDecoderRegistry()
        let received = ResolutionBox<ImageDecodingContext>()
        registry.register { context in
            received.value = context
            return nil
        }
        var request = Test.request
        request.scale = 2
        let context = ImageDecodingContext(
            request: request,
            data: Test.data,
            isCompleted: false,
            urlResponse: Test.urlResponse,
            cacheType: .disk,
            previewPolicy: .thumbnail,
            isAnimatedImageParsingEnabled: false
        )

        // When
        _ = registry.decoder(for: context)

        // Then
        let value = try #require(received.value)
        #expect(value.request.url == Test.url)
        #expect(value.request.scale == 2)
        #expect(value.data == Test.data)
        #expect(value.isCompleted == false)
        #expect(value.urlResponse === Test.urlResponse)
        #expect(value.cacheType == .disk)
        #expect(value.previewPolicy == .thumbnail)
        #expect(value.isAnimatedImageParsingEnabled == false)
    }

    @Test func defaultDecoderIsConfiguredFromTheContext() throws {
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 64)
        let context = ImageDecodingContext(request: request, data: Test.data, previewPolicy: .disabled, isAnimatedImageParsingEnabled: false)

        let decoder = try #require(ImageDecoderRegistry().decoder(for: context) as? ImageDecoders.Default)

        #expect(decoder.previewPolicy == .disabled)
        #expect(decoder.isAnimatedImageParsingEnabled == false)
        // A thumbnail request reads the image dimensions from the data, which
        // is why it moves to the decoding queue.
        #expect(decoder.isAsynchronous)
    }

    @Test func defaultDecoderIsSynchronousUnlessAThumbnailIsRequested() throws {
        #expect(ImageDecoders.Default().isAsynchronous == false)
        let decoder = try #require(ImageDecoderRegistry().decoder(for: .mock))
        #expect(decoder.isAsynchronous == false)
    }

    // MARK: Order

    @Test func resolutionAsksTheNewestFirstAndStopsAtTheFirstMatch() {
        // Given
        let registry = ImageDecoderRegistry()
        let log = LockedArray<String>()
        registry.register { _ in
            log.append("oldest")
            return MockImageDecoder(name: "oldest")
        }
        registry.register { _ in
            log.append("middle")
            return MockImageDecoder(name: "middle")
        }
        registry.register { _ in
            log.append("newest")
            return nil
        }

        // When
        let decoder = registry.decoder(for: .mock) as? MockImageDecoder

        // Then the older closures are never asked, not even to be ignored
        #expect(decoder?.name == "middle")
        #expect(log.values == ["newest", "middle"])
    }

    @Test func sameClosureRegisteredTwiceGetsTwoTokens() {
        // Given
        let registry = ImageDecoderRegistry()
        let match: @Sendable (ImageDecodingContext) -> (any ImageDecoding)? = { _ in MockImageDecoder(name: "A") }
        let first = registry.register(match)
        let second = registry.register(match)

        // When
        registry.unregister(first)

        // Then
        #expect(first != second)
        #expect(registry.decoder(for: .mock) is MockImageDecoder)
        registry.unregister(second)
        #expect(registry.decoder(for: .mock) is ImageDecoders.Default)
    }

    // MARK: Clear

    @Test func tokenFromBeforeClearDoesNotRemoveADecoderRegisteredAfterIt() {
        // The tokens are counters: if `clear()` reset the counter, the stale
        // token would name the first decoder registered after it.
        let registry = ImageDecoderRegistry()
        let stale = registry.register { _ in MockImageDecoder(name: "stale") }
        registry.clear()
        let fresh = registry.register { _ in MockImageDecoder(name: "fresh") }

        registry.unregister(stale)

        #expect(stale != fresh)
        #expect((registry.decoder(for: .mock) as? MockImageDecoder)?.name == "fresh")
    }

    @Test func defaultDecoderCanBeRegisteredAgainAfterClear() {
        let registry = ImageDecoderRegistry()
        registry.clear()
        #expect(registry.decoder(for: .mock) == nil)

        registry.register(ImageDecoders.Default.init)

        #expect(registry.decoder(for: .mock) is ImageDecoders.Default)
    }

    @Test func registriesAreIndependent() {
        let registry = ImageDecoderRegistry()
        registry.register { _ in MockImageDecoder(name: "A") }
        registry.clear()

        #expect(ImageDecoderRegistry().decoder(for: .mock) is ImageDecoders.Default)
    }

    // MARK: Concurrency

    @Test func concurrentRegistrationsAndRemovalsAreNotLost() async {
        // Every task takes out what it put in. A lost update – two writers
        // appending to, or filtering, the same snapshot – would leave a
        // decoder behind or take the default one with it.
        let registry = ImageDecoderRegistry()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    let token = registry.register { _ in MockImageDecoder(name: "\(index)") }
                    _ = registry.decoder(for: .mock)
                    registry.unregister(token)
                }
            }
        }

        #expect(registry.decoder(for: .mock) is ImageDecoders.Default)
    }

    // MARK: Re-entrancy

    @Test func matchClosureCanRegisterAndResolveReentrantly() {
        // The closures are called outside of the lock, so a closure that
        // calls back into the registry must neither deadlock nor change the
        // walk it is part of.
        let registry = ImageDecoderRegistry()
        let didRegister = ResolutionBox<Bool>(false)
        registry.register { [weak registry] context in
            if let registry, didRegister.value == false {
                didRegister.value = true
                registry.register { _ in MockImageDecoder(name: "registered-during-resolution") }
                // A nested resolution sees the registration.
                #expect((registry.decoder(for: context) as? MockImageDecoder)?.name == "registered-during-resolution")
            }
            return nil
        }

        // The walk in progress is over a snapshot: the default decoder answers.
        #expect(registry.decoder(for: .mock) is ImageDecoders.Default)
        // The next one starts with the decoder registered during the first.
        #expect((registry.decoder(for: .mock) as? MockImageDecoder)?.name == "registered-during-resolution")
    }

    @Test func matchClosureCanUnregisterItself() {
        // A one-shot decoder: it matches once and takes itself out.
        let registry = ImageDecoderRegistry()
        let token = ResolutionBox<ImageDecoderRegistry.RegistrationToken>()
        token.value = registry.register { [weak registry] _ in
            if let value = token.value {
                registry?.unregister(value)
            }
            return MockImageDecoder(name: "one-shot")
        }

        #expect(registry.decoder(for: .mock) is MockImageDecoder)
        #expect(registry.decoder(for: .mock) is ImageDecoders.Default)
    }

    @Test func matchClosureCanClearTheRegistry() {
        let registry = ImageDecoderRegistry()
        registry.register { [weak registry] _ in
            registry?.clear()
            return nil
        }

        // The snapshot still ends with the default decoder...
        #expect(registry.decoder(for: .mock) is ImageDecoders.Default)
        // ...which is gone for the next resolution.
        #expect(registry.decoder(for: .mock) == nil)
    }
}

/// A lock-protected value the `@Sendable` match closures can write to.
private final class ResolutionBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value?

    init(_ value: Value? = nil) {
        self._value = value
    }

    var value: Value? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
