// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

final class ImageDecoderRegistryTests: XCTestCase {
    func testDefaultDecoderIsReturned() {
        // Given
        let context = _mockImageDecodingContext()

        // Then
        let decoder = ImageDecoderRegistry().decoder(for: context)
        XCTAssertTrue(decoder is ImageDecoder)
    }

    func testRegisterDecoder() {
        // Given
        let registry = ImageDecoderRegistry()
        let context = _mockImageDecodingContext()

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

    func testWhenReturningNextDecoderIsEvaluated() {
        // Given
        let registry = ImageDecoderRegistry()
        registry.register { _ in
            return nil
        }

        // When
        let context = _mockImageDecodingContext()
        let decoder = ImageDecoderRegistry().decoder(for: context)

        // Then
        XCTAssertTrue(decoder is ImageDecoder)
    }
}

private func _mockImageDecodingContext() -> ImageDecodingContext {
    return ImageDecodingContext(
        request: Test.request,
        data: Test.data(name: "fixture", extension: "jpeg"),
        urlResponse: nil
    )
}
