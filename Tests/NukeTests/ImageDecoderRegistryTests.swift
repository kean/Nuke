// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite struct ImageDecoderRegistryTests {
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
}
