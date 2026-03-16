// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

@Suite(.timeLimit(.minutes(2)))
struct ImageProcessorsAnonymousTests {

    @Test func anonymousProcessorsHaveDifferentIdentifiers() {
        #expect(
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier ==
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier
        )
        #expect(
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier !=
            ImageProcessors.Anonymous(id: "2", { $0 }).identifier
        )
    }

    @Test func anonymousProcessorsHaveDifferentHashableIdentifiers() {
        #expect(
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier ==
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier
        )
        #expect(
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier !=
            ImageProcessors.Anonymous(id: "2", { $0 }).hashableIdentifier
        )
    }

    @Test func anonymousProcessorDescription() {
        let processor = ImageProcessors.Anonymous(id: "my-processor", { $0 })
        #expect(processor.description.contains("my-processor"))
    }

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
}
