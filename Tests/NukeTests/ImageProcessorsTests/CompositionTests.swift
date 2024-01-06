// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

// MARK: - ImageProcessors.Composition

class ImageProcessorsCompositionTest: XCTestCase {

    func testAppliesAllProcessors() throws {
        // GIVEN
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // WHEN
        let image = try XCTUnwrap(processor.process(Test.image))

        // THEN
        XCTAssertEqual(image.nk_test_processorIDs, ["1", "2"])
    }

    func testAppliesAllProcessorsWithContext() throws {
        // GIVEN
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // WHEN
        let context = ImageProcessingContext(request: Test.request, response: ImageResponse(container: Test.container, request: Test.request), isCompleted: true)
        let output = try processor.process(Test.container, context: context)

        // THEN
        XCTAssertEqual(output.image.nk_test_processorIDs, ["1", "2"])
    }

    func testIdenfitiers() {
        // Given different processors
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdentifiersDifferentProcessorCount() {
        // Given processors with different processor count
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdenfitiersEqualProcessors() {
        // Given processors with equal processors
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        XCTAssertEqual(lhs.identifier, rhs.identifier)
        XCTAssertEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdentifiersWithSameProcessorsButInDifferentOrder() {
        // Given processors with equal processors but in different order
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "2"), MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdenfitiersEmptyProcessors() {
        // Given empty processors
        let lhs = ImageProcessors.Composition([])
        let rhs = ImageProcessors.Composition([])

        // Then
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        XCTAssertEqual(lhs.identifier, rhs.identifier)
        XCTAssertEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testThatIdentifiesAreFlattened() {
        let lhs = ImageProcessors.Composition([
            ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")]),
            ImageProcessors.Composition([MockImageProcessor(id: "3"), MockImageProcessor(id: "4")])]
        )
        let rhs = ImageProcessors.Composition([
            MockImageProcessor(id: "1"), MockImageProcessor(id: "2"),
            MockImageProcessor(id: "3"), MockImageProcessor(id: "4")]
        )

        // Then
        XCTAssertEqual(lhs.identifier, rhs.identifier)
    }

    func testDescription() {
        // GIVEN
        let processor = ImageProcessors.Composition([
            ImageProcessors.Circle()
        ])

        // THEN
        XCTAssertEqual("\(processor)", "Composition(processors: [Circle(border: nil)])")
    }
}
