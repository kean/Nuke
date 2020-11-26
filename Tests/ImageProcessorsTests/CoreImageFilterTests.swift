// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS)

class ImageProcessorsCoreImageFilterTests: XCTestCase {
    func _testApplySepia() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")

        // When
        let output = try XCTUnwrap(processor.process(input))

        // Then
        XCTAssertEqualImages(output, Test.image(named: "s-sepia.png"))
    }

    func _testApplySepiaWithParameters() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // When
        let output = try XCTUnwrap(processor.process(input))

        // Then
        XCTAssertEqualImages(output, Test.image(named: "s-sepia-less-intense.png"))
    }
}

#endif
