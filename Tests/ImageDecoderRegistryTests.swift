// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

final class ImageDecoderRegistryTests: XCTestCase {
    func testDefaultDecoderIsReturned() {
        let context = _mockImageDecodingContext()
        let decoder = ImageDecoderRegistry().decoder(for: context)
        XCTAssertTrue(decoder is ImageDecoder)
    }

    func testRegisterDecoder() {
        let register = ImageDecoderRegistry()

        register.register { context in
            return MockImageDecoder(name: "A")
        }

        let context = _mockImageDecodingContext()

        test("First registered closure is called") {
            let decoder = register.decoder(for: context)
            XCTAssertEqual((decoder as? MockImageDecoder)?.name, "A")
        }

        register.register { _ in
            return MockImageDecoder(name: "B")
        }

        test("Second registered closure is called first") {
            let decoder = register.decoder(for: context)
            XCTAssertEqual((decoder as? MockImageDecoder)?.name, "B")
        }
    }

    func testCustomDecoderReturnedNil() {
        let register = ImageDecoderRegistry()
        register.register { _ in
            return nil
        }
        let context = _mockImageDecodingContext()
        let decoder = ImageDecoderRegistry().decoder(for: context)
        XCTAssertTrue(decoder is ImageDecoder)
    }
}

private func _mockImageDecodingContext() -> ImageDecodingContext {
    return ImageDecodingContext(
        request: ImageRequest(url: defaultURL),
        urlResponse: nil,
        data: Test.data(name: "fixture", extension: "jpeg")
    )
}
