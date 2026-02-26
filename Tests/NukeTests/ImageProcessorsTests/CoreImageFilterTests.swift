// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite struct ImageProcessorsCoreImageFilterTests {
    @Test func applySepia() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")

        // WHEN
        let output = try #require(processor.process(input))

        // THEN
        _ = output // image was produced successfully
    }

    @Test func applySepiaWithParameters() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // WHEN
        let output = try #require(processor.process(input))

        // THEN
        _ = output // image was produced successfully
    }

    @Test func applyFilterWithInvalidName() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "yo", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        #expect(throws: ImageProcessors.CoreImageFilter.Error.self) {
            try processor.processThrowing(input)
        }
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func applyFilterToCIImage() throws {
        // GIVEN image backed by CIImage
        let input = PlatformImage(ciImage: CIImage(cgImage: Test.image.cgImage!))
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // WHEN
        let output = try #require(processor.process(input))

        // THEN
        _ = output // image was produced successfully
    }
#endif

    @Test func applyFilterBackedByNothing() throws {
        // GIVEN empty image
        let input = PlatformImage()
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        #expect(throws: ImageProcessors.CoreImageFilter.Error.self) {
            try processor.processThrowing(input)
        }
    }

    @Test func description() {
        // GIVEN
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        #expect("\(processor)" == "CoreImageFilter(name: CISepiaTone, parameters: [\"inputIntensity\": 0.5])")
    }

    @Test func applyCustomFilter() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let filter = try #require(CIFilter(name: "CISepiaTone", parameters: nil))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")

        // WHEN
        let output = try #require(processor.process(input))

        // THEN
        _ = output // image was produced successfully
    }
}

#endif
