// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

class ImageProcessorsCoreImageFilterTests: XCTestCase {
    func testApplySepia() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")
        
        // When
        let output = try XCTUnwrap(processor.process(input))
        
        // Then
        XCTAssertNotNil(output)
        
        // TODO: The comparison doesn't work for some reason
        // XCTAssertEqualImages(output, Test.image(named: "s-sepia.png"))
    }
    
    func testApplySepiaWithParameters() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")
        
        // When
        let output = try XCTUnwrap(processor.process(input))
        
        // Then
        XCTAssertNotNil(output)
        
        // TODO: The comparison doesn't work for some reason
        // XCTAssertEqualImages(output, Test.image(named: "s-sepia-less-intense.png"))
    }
    
    func testApplyFilterWithInvalidName() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "yo", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")
        
        // Then
        XCTAssertThrowsError(try processor.processThrowing(input)) { error in
            guard let error = error as? ImageProcessors.CoreImageFilter.Error else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch error {
            case let .failedToCreateFilter(name, parameters):
                XCTAssertEqual(name, "yo")
                XCTAssertNotNil(parameters["inputIntensity"])
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
#if os(iOS) || os(tvOS) || os(visionOS)
    func testApplyFilterToCIImage() throws {
        // Given image backed by CIImage
        let input = PlatformImage(ciImage: CIImage(cgImage: Test.image.cgImage!))
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")
        
        // When
        let output = try XCTUnwrap(processor.process(input))
        
        // Then
        XCTAssertNotNil(output)
    }
#endif
    
    func testApplyFilterBackedByNothing() throws {
        // Given empty image
        let input = PlatformImage()
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")
        
        // Then
        XCTAssertThrowsError(try processor.processThrowing(input)) { error in
            guard let error = error as? ImageProcessors.CoreImageFilter.Error else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch error {
            case .inputImageIsEmpty:
                break // Do nothing
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    func testDescription() {
        // Given
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")
        
        // Then
        XCTAssertEqual("\(processor)", "CoreImageFilter(name: CISepiaTone, parameters: [\"inputIntensity\": 0.5])")
    }

    func testApplyCustomFilter() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let filter = try XCTUnwrap(CIFilter(name: "CISepiaTone", parameters: nil))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")

        // When
        let output = try XCTUnwrap(processor.process(input))

        // Then
        XCTAssertNotNil(output)
    }
}

#endif
