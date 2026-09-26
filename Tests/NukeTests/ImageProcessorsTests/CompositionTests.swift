// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

// MARK: - ImageProcessors.Composition

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsCompositionTests {

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
        assertHashableEqual(lhs, rhs)
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

    // MARK: Edge Cases

    @Test func singleProcessorInCompositionIsApplied() throws {
        // GIVEN - composition wrapping a single processor
        let processor = ImageProcessors.Composition([MockImageProcessor(id: "solo")])

        // WHEN
        let image = try #require(processor.process(Test.image))

        // THEN - the sole processor is still applied
        #expect(image.nk_test_processorIDs == ["solo"])
    }

    @Test func emptyCompositionPassesThroughImage() throws {
        // GIVEN - composition with no processors
        let processor = ImageProcessors.Composition([])

        // WHEN
        let image = try #require(processor.process(Test.image))

        // THEN - original image passes through with no processor IDs
        #expect(image.nk_test_processorIDs == [])
    }

    @Test func whenOneProcessorReturnsNilCompositionReturnsNil() {
        // GIVEN - a composition where the second step fails
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockFailingProcessor()
        ])

        // WHEN/THEN - the entire composition yields nil
        #expect(processor.process(Test.image) == nil)
    }

    @Test func remainingProcessorsSkippedAfterFailure() {
        // GIVEN - a composition where the first step fails
        let factory = MockProcessorFactory()
        let processor = ImageProcessors.Composition([
            MockFailingProcessor(),
            factory.make(id: "shouldNotRun")
        ])

        // WHEN/THEN - composition short-circuits at the first failure
        #expect(processor.process(Test.image) == nil)
        _ = try? processor.process(Test.container, context: .mock)
        #expect(factory.numberOfProcessorsApplied == 0)
    }

    @Test func errorThrownByAProcessorIsPropagated() {
        // GIVEN a composition with a processor that throws a specific error
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockThrowingProcessor(),
            MockImageProcessor(id: "2")
        ])

        // THEN the error isn't replaced with a generic one
        #expect(throws: MockError.self) {
            try processor.process(Test.container, context: .mock)
        }
    }

    /// Composition doesn't drop the data itself – whether it survives is up to
    /// each processor it runs.
    @Test func dataIsKeptWhenEveryProcessorKeepsIt() throws {
        // GIVEN
        let data = Test.animatedGIF()
        let container = ImageContainer(image: Test.image, type: .gif, data: data)
        let processor = ImageProcessors.Composition([MockDataPreservingProcessor(id: "1"), MockDataPreservingProcessor(id: "2")])

        // WHEN
        let output = try processor.process(container, context: .mock)

        // THEN
        #expect(output.data == data)
    }

    @Test func dataIsDroppedWhenAnyProcessorProducesANewImage() throws {
        // GIVEN
        let container = ImageContainer(image: Test.image, type: .gif, data: Test.animatedGIF())
        let processor = ImageProcessors.Composition([MockDataPreservingProcessor(id: "1"), MockImageProcessor(id: "2")])

        // WHEN
        let output = try processor.process(container, context: .mock)

        // THEN
        #expect(output.data == nil)
        #expect(output.image.nk_test_processorIDs == ["1", "2"])
    }

    @Test func emptyCompositionKeepsDataAndAnimation() throws {
        // GIVEN an animated image and a composition with nothing in it
        let source = Test.animatedGIFSource()
        let container = ImageContainer(image: Test.image, type: .gif, data: source.data, animation: source)
        let processor = ImageProcessors.Composition([])

        // WHEN
        let output = try processor.process(container, context: .mock)

        // THEN no processor produced a new image, so the animation still
        // describes the one that comes out
        #expect(output.image === container.image)
        #expect(output.data == source.data)
        #expect(output.animation === source)
    }

    @Test func compositionOfBuiltInProcessors() throws {
        // GIVEN an avatar: crop to a square, then mask with a circle
        let processor = ImageProcessors.Composition([
            ImageProcessors.Resize(size: CGSize(width: 100, height: 100), unit: .pixels, crop: true),
            ImageProcessors.Circle()
        ])

        // WHEN
        let image = try #require(processor.process(Test.image))
        let container = try processor.process(Test.container, context: .mock)

        // THEN both methods produce the same image
        #expect(image.sizeInPixels == CGSize(width: 100, height: 100))
        #expect(image.cgImage?.isOpaque == false)
        #expect(isEqualImages(image, container.image))
    }

    @Test func compositionIdentifierConcatenatesTheIdentifiersInOrder() {
        // GIVEN
        let processor = ImageProcessors.Composition([MockImageProcessor(id: "a"), MockImageProcessor(id: "b")])

        // THEN
        #expect(processor.identifier == "ab")
    }

    @Test func descriptionListsEveryProcessor() {
        // GIVEN
        let processor = ImageProcessors.Composition([
            ImageProcessors.Circle(),
            ImageProcessors.RoundedCorners(radius: 4, unit: .pixels)
        ])

        // THEN
        #expect(processor.description == "Composition(processors: [Circle(border: nil), RoundedCorners(radius: 4.0 pixels, border: nil)])")
    }
}
