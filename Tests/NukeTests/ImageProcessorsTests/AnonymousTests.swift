// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsAnonymousTests {

    @Test func anonymousProcessorReturnsNil() {
        let processor = ImageProcessors.Anonymous(id: "nil-processor") { _ in nil }
        let result = processor.process(Test.image)
        #expect(result == nil)
    }

    @Test func anonymousProcessorIsApplied() throws {
        // Given
        let processor = ImageProcessors.Anonymous(id: "1") {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }

        // When
        let image = try #require(processor.process(Test.image))

        // Then
        #expect(image.nk_test_processorIDs == ["1"])
    }

    @Test func anonymousProcessorReceivesTheInputAndReturnsTheClosureOutput() throws {
        // Given
        let input = Test.image
        let replacement = Test.rgbImage(width: 10, height: 10)
        let processor = ImageProcessors.Anonymous(id: "replace") { image in
            image === input ? replacement : nil
        }

        // When
        let output = try #require(processor.process(input))

        // Then
        #expect(output === replacement)
    }
}
