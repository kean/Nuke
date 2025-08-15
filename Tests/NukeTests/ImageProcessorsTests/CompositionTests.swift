// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

@Suite struct ImageProcessorsCompositionTest {

    @Test func appliesAllProcessors() throws {
        // Given
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // When
        let image = try #require(processor.process(Test.image))

        // Then
        #expect(image.nk_test_processorIDs == ["1", "2"])
    }

    @Test func appliesAllProcessorsWithContext() throws {
        // Given
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // When
        let context = ImageProcessingContext(request: Test.request, response: ImageResponse(container: Test.container, request: Test.request), isCompleted: true)
        let output = try processor.process(Test.container, context: context)

        // Then
        #expect(output.image.nk_test_processorIDs == ["1", "2"])
    }

    @Test func identifiers() {
        // Given different processors
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "2")])

        // Then
        #expect(lhs != rhs)
        #expect(lhs.identifier != rhs.identifier)
        #expect(lhs.hashableIdentifier != rhs.hashableIdentifier)
    }

    @Test func identifiersDifferentProcessorCount() {
        // Given processors with different processor count
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        #expect(lhs != rhs)
        #expect(lhs.identifier != rhs.identifier)
        #expect(lhs.hashableIdentifier != rhs.hashableIdentifier)
    }

    @Test func identifiersEqualProcessors() {
        // Given processors with equal processors
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
        #expect(lhs.identifier == rhs.identifier)
        #expect(lhs.hashableIdentifier == rhs.hashableIdentifier)
    }

    @Test func identifiersWithSameProcessorsButInDifferentOrder() {
        // Given processors with equal processors but in different order
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "2"), MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        #expect(lhs != rhs)
        #expect(lhs.identifier != rhs.identifier)
        #expect(lhs.hashableIdentifier != rhs.hashableIdentifier)
    }

    @Test func identifiersEmptyProcessors() {
        // Given empty processors
        let lhs = ImageProcessors.Composition([])
        let rhs = ImageProcessors.Composition([])

        // Then
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

        // Then
        #expect(lhs.identifier == rhs.identifier)
    }

    @Test func description() {
        // Given
        let processor = ImageProcessors.Composition([
            ImageProcessors.Circle()
        ])

        // Then
        #expect("\(processor)" == "Composition(processors: [Circle(border: nil)])")
    }
}
