// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

// MARK: - ImageProcessors.Composition

@Suite struct ImageProcessorsCompositionTests {

    @Test func appliesAllProcessors() throws {
        // GIVEN
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // WHEN
        let image = try #require(processor.process(Test.image))

        // THEN
        #expect(image.nk_test_processorIDs == ["1", "2"])
    }

    @Test func appliesAllProcessorsWithContext() throws {
        // GIVEN
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // WHEN
        let context = ImageProcessingContext(request: Test.request, response: ImageResponse(container: Test.container, request: Test.request), isCompleted: true)
        let output = try processor.process(Test.container, context: context)

        // THEN
        #expect(output.image.nk_test_processorIDs == ["1", "2"])
    }

    @Test func identifiers() {
        // GIVEN different processors
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "2")])

        // THEN
        #expect(lhs != rhs)
        #expect(lhs.identifier != rhs.identifier)
        #expect(lhs.hashableIdentifier != rhs.hashableIdentifier)
    }

    @Test func identifiersDifferentProcessorCount() {
        // GIVEN processors with different processor count
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // THEN
        #expect(lhs != rhs)
        #expect(lhs.identifier != rhs.identifier)
        #expect(lhs.hashableIdentifier != rhs.hashableIdentifier)
    }

    @Test func identifiersEqualProcessors() {
        // GIVEN processors with equal processors
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // THEN
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
        #expect(lhs.identifier == rhs.identifier)
        #expect(lhs.hashableIdentifier == rhs.hashableIdentifier)
    }

    @Test func identifiersWithSameProcessorsButInDifferentOrder() {
        // GIVEN processors with equal processors but in different order
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "2"), MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // THEN
        #expect(lhs != rhs)
        #expect(lhs.identifier != rhs.identifier)
        #expect(lhs.hashableIdentifier != rhs.hashableIdentifier)
    }

    @Test func identifiersEmptyProcessors() {
        // GIVEN empty processors
        let lhs = ImageProcessors.Composition([])
        let rhs = ImageProcessors.Composition([])

        // THEN
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
        #expect(lhs.identifier == rhs.identifier)
        #expect(lhs.hashableIdentifier == rhs.hashableIdentifier)
    }

    @Test func thatIdentifiesAreFlattened() {
        let lhs = ImageProcessors.Composition([
            ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")]),
            ImageProcessors.Composition([MockImageProcessor(id: "3"), MockImageProcessor(id: "4")])]
        )
        let rhs = ImageProcessors.Composition([
            MockImageProcessor(id: "1"), MockImageProcessor(id: "2"),
            MockImageProcessor(id: "3"), MockImageProcessor(id: "4")]
        )

        // THEN
        #expect(lhs.identifier == rhs.identifier)
    }

    @Test func description() {
        // GIVEN
        let processor = ImageProcessors.Composition([
            ImageProcessors.Circle()
        ])

        // THEN
        #expect("\(processor)" == "Composition(processors: [Circle(border: nil)])")
    }
}
