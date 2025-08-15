// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite struct ImageProcessorsCoreImageFilterTests {
    @Test func applySepia() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")

        // When
        let output = try #require(processor.process(input))

        // Then
        #expect(output != nil)

        // TODO: The comparison doesn't work for some reason
        // #expect(isEqual(output, Test.image(named: "s-sepia.png")))
    }

    @Test func applySepiaWithParameters() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // When
        let output = try #require(processor.process(input))

        // Then
        #expect(output != nil)

        // TODO: The comparison doesn't work for some reason
        // #expect(isEqual(output, Test.image(named: "s-sepia-less-intense.png")))
    }

    @Test func applyFilterWithInvalidName() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "yo", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // Then
        #expect(performing: {
            try processor.processThrowing(input)
        }, throws: { error in
            guard let error = error as? ImageProcessors.CoreImageFilter.Error else {
                return false
            }
            switch error {
            case let .failedToCreateFilter(name, parameters):
                #expect(name == "yo")
                #expect(parameters["inputIntensity"] != nil)
                return true
            default:
                return false
            }
        })
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func applyFilterToCIImage() throws {
        // Given image backed by CIImage
        let input = PlatformImage(ciImage: CIImage(cgImage: Test.image.cgImage!))
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // When
        let output = try #require(processor.process(input))

        // Then
        #expect(output != nil)
    }
#endif

    @Test func applyFilterBackedByNothing() throws {
        // Given empty image
        let input = PlatformImage()
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        #expect(performing: {
            try processor.processThrowing(input)
        }, throws: { error in
            guard let error = error as? ImageProcessors.CoreImageFilter.Error else {
                return false
            }
            switch error {
            case .inputImageIsEmpty:
                return true
            default:
                return false
            }
        })
    }

    @Test func description() {
        // Given
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // Then
        #expect("\(processor)" == "CoreImageFilter(name: CISepiaTone, parameters: [\"inputIntensity\": 0.5])")
    }

    @Test func applyCustomFilter() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let filter = try #require(CIFilter(name: "CISepiaTone", parameters: nil))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")

        // When
        let output = try #require(processor.process(input))

        // Then
        #expect(output != nil)
    }
}

#endif
