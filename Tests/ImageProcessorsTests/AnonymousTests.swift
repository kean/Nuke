// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

class ImageProcessorsAnonymousTests: XCTestCase {

    func testAnonymousProcessorsHaveDifferentIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier,
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier,
            ImageProcessors.Anonymous(id: "2", { $0 }).identifier
        )
    }

    func testAnonymousProcessorsHaveDifferentHashableIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier,
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier,
            ImageProcessors.Anonymous(id: "2", { $0 }).hashableIdentifier
        )
    }

    func testAnonymousProcessorIsApplied() {
        // Given
        let processor = ImageProcessors.Anonymous(id: "1") {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }

        // When
        let image = processor.process(Test.image)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }
}
