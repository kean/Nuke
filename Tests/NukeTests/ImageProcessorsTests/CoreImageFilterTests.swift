// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
import UIKit
#else
import CoreImage
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsCoreImageFilterTests {
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

    // MARK: - Composition

    @Test func compositionOfTwoCIFiltersProducesOutput() throws {
        // GIVEN two CoreImage filters composed in sequence
        let input = Test.image(named: "fixture-tiny.jpeg")
        let filter1 = ImageProcessors.CoreImageFilter(name: "CISepiaTone")
        let filter2 = ImageProcessors.CoreImageFilter(name: "CIColorInvert")
        let composition = ImageProcessors.Composition([filter1, filter2])

        // WHEN
        let output = try #require(composition.process(input))

        // THEN a valid image is produced
        _ = output
    }

    // MARK: - Identifiers

    @Test func identifiersAreDistinctForDifferentFilterNames() {
        // GIVEN two filters with different names (using the name-only initializer)
        let sepia = ImageProcessors.CoreImageFilter(name: "CISepiaTone")
        let bloom = ImageProcessors.CoreImageFilter(name: "CIBloom")

        // THEN their identifiers differ
        #expect(sepia.identifier != bloom.identifier)
    }

    @Test func identifiersAreEqualForSameFilterAndParameters() {
        // GIVEN two identically-configured filters
        let a = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.8], identifier: "sepia-80")
        let b = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.8], identifier: "sepia-80")

        // THEN their identifiers are equal
        #expect(a.identifier == b.identifier)
    }
}

#endif
