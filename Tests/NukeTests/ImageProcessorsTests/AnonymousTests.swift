// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

@Suite struct ImageProcessorsAnonymousTests {

    @Test func anonymousProcessorsHaveDifferentIdentifiers() {
        #expect(
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier == ImageProcessors.Anonymous(id: "1", { $0 }).identifier
        )
        #expect(
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier != ImageProcessors.Anonymous(id: "2", { $0 }).identifier
        )
    }

    @Test func anonymousProcessorsHaveDifferentHashableIdentifiers() {
        #expect(
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier == ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier
        )
        #expect(
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier != ImageProcessors.Anonymous(id: "2", { $0 }).hashableIdentifier
        )
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
}
