// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

final class ImageDecoderRegistryTests: XCTestCase {
    func testDefaultDecoderIsReturned() {
        // Given
        let context = ImageDecodingContext.mock

        // Then
        let decoder = ImageDecoderRegistry().decoder(for: context)
        XCTAssertTrue(decoder is ImageDecoders.Default)
    }

    func testRegisterDecoder() {
        // Given
        let registry = ImageDecoderRegistry()
        let context = ImageDecodingContext.mock

        // When
        registry.register { _ in
            return MockImageDecoder(name: "A")
        }

        // Then
        let decoder1 = registry.decoder(for: context) as? MockImageDecoder
        XCTAssertEqual(decoder1?.name, "A")

        // When
        registry.register { _ in
            return MockImageDecoder(name: "B")
        }

        // Then
        let decoder2 = registry.decoder(for: context) as? MockImageDecoder
        XCTAssertEqual(decoder2?.name, "B")
    }
    
    func testClearDecoders() {
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
        XCTAssertNil(noDecoder)
    }

    func testWhenReturningNextDecoderIsEvaluated() {
        // Given
        let registry = ImageDecoderRegistry()
        registry.register { _ in
            return nil
        }

        // When
        let context = ImageDecodingContext.mock
        let decoder = ImageDecoderRegistry().decoder(for: context)

        // Then
        XCTAssertTrue(decoder is ImageDecoders.Default)
    }
}
