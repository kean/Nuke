// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS)

class ImageProcessorsCoreImageFilterTests: XCTestCase {
    func testApplySepia() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")

        // WHEN
        let output = try XCTUnwrap(processor.process(input))

        // THEN
        XCTAssertNotNil(output)

        // TODO: The comparison doesn't work for some reason
        // XCTAssertEqualImages(output, Test.image(named: "s-sepia.png"))
    }

    func testApplySepiaWithParameters() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // WHEN
        let output = try XCTUnwrap(processor.process(input))

        // THEN
        XCTAssertNotNil(output)

        // TODO: The comparison doesn't work for some reason
        // XCTAssertEqualImages(output, Test.image(named: "s-sepia-less-intense.png"))
    }

    func testApplyFilterWithInvalidName() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "yo", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        XCTAssertNil(processor.process(input))
    }

    #if os(iOS) || os(tvOS)
    func testApplyFilterToCIImage() throws {
        // GIVEN image backed by CIImage
        let input = PlatformImage(ciImage: CIImage(cgImage: Test.image.cgImage!))
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // WHEN
        let output = try XCTUnwrap(processor.process(input))

        // THEN
        XCTAssertNotNil(output)
    }
    #endif

    func testApplyFilterBackedByNothing() throws {
        // GIVEN empty image
        let input = PlatformImage()
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        XCTAssertNil(processor.process(input))
    }

    func testDescription() {
        // GIVEN
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        XCTAssertEqual("\(processor)", "CoreImageFilter(name: CISepiaTone, parameters: [\"inputIntensity\": 0.5])")
    }
}

#endif
