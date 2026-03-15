// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite(.timeLimit(.minutes(1)))
struct ImageDecoderRegistryTests {
    @Test func defaultDecoderIsReturned() {
        // Given
        let context = ImageDecodingContext.mock

        // Then
        let decoder = ImageDecoderRegistry().decoder(for: context)
        #expect(decoder is ImageDecoders.Default)
    }

    @Test func registerDecoder() {
        // Given
        let registry = ImageDecoderRegistry()
        let context = ImageDecodingContext.mock

        // When
        registry.register { _ in
            return MockImageDecoder(name: "A")
        }

        // Then
        let decoder1 = registry.decoder(for: context) as? MockImageDecoder
        #expect(decoder1?.name == "A")

        // When
        registry.register { _ in
            return MockImageDecoder(name: "B")
        }

        // Then
        let decoder2 = registry.decoder(for: context) as? MockImageDecoder
        #expect(decoder2?.name == "B")
    }

    @Test func clearDecoders() {
        // Given
        let registry = ImageDecoderRegistry()
        let context = ImageDecodingContext.mock

        registry.register { _ in
            return MockImageDecoder(name: "A")
        }

        // When
        registry.clear()

        // Then
        let noDecoder = registry.decoder(for: context)
        #expect(noDecoder == nil)
    }

    @Test func whenReturningNextDecoderIsEvaluated() {
        // Given
        let registry = ImageDecoderRegistry()
        registry.register { _ in
            return nil
        }

        // When
        let context = ImageDecodingContext.mock
        let decoder = ImageDecoderRegistry().decoder(for: context)

        // Then
        #expect(decoder is ImageDecoders.Default)
    }

    // MARK: - Fallthrough and Ordering

    @Test func whenRegisteredDecoderReturnsNilFallsToBuiltIn() {
        // GIVEN a registry with one decoder that always declines
        let registry = ImageDecoderRegistry()
        registry.register { _ in nil }

        // WHEN
        let context = ImageDecodingContext.mock
        let decoder = registry.decoder(for: context)

        // THEN the built-in default decoder is returned
        #expect(decoder is ImageDecoders.Default)
    }

    @Test func decodersEvaluatedInLIFOOrder() {
        // GIVEN a registry with two custom decoders registered in sequence
        let registry = ImageDecoderRegistry()
        registry.register { _ in MockImageDecoder(name: "first") }
        registry.register { _ in MockImageDecoder(name: "second") }

        // WHEN
        let context = ImageDecodingContext.mock
        let decoder = registry.decoder(for: context) as? MockImageDecoder

        // THEN the most-recently registered decoder wins (LIFO)
        #expect(decoder?.name == "second")
    }

    @Test func whenAllCustomDecodersDeclineBuiltInIsReturned() {
        // GIVEN a registry where every custom decoder returns nil
        let registry = ImageDecoderRegistry()
        registry.register { _ in nil }
        registry.register { _ in nil }
        registry.register { _ in nil }

        // WHEN
        let context = ImageDecodingContext.mock
        let decoder = registry.decoder(for: context)

        // THEN falls through to the built-in Default decoder
        #expect(decoder is ImageDecoders.Default)
    }
}
