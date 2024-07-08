// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
import NukeTestHelpers

@testable import Nuke

#if !os(macOS)
import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

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
        // GIVEN
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")
        
        // THEN
        XCTAssertEqual("\(processor)", "CoreImageFilter(name: CISepiaTone, parameters: [\"inputIntensity\": 0.5])")
    }

    func testApplyCustomFilter() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let filter = try XCTUnwrap(CIFilter(name: "CISepiaTone", parameters: nil))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")

        // WHEN
        let output = try XCTUnwrap(processor.process(input))

        // THEN
        XCTAssertNotNil(output)
    }
}

#endif
