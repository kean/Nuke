// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageProcessorsProtocolExtensionsTests: XCTestCase {
    
    func testPassingProcessorsUsingProtocolExtensionsResize() throws {
        let size = CGSize(width: 100, height: 100)
        let processor = ImageProcessors.Resize(size: size)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.resize(size: size)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsResizeWidthOnly() throws {
        let processor = ImageProcessors.Resize(width: 100)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.resize(width: 100)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsResizeHeightOnly() throws {
        let processor = ImageProcessors.Resize(height: 100)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.resize(height: 100)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsCircleEmpty() throws {
        let processor = ImageProcessors.Circle()
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.circle()]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsCircle() throws {
        let border = ImageProcessingOptions.Border.init(color: .red)
        let processor = ImageProcessors.Circle(border: border)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.circle(border: border)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsRoundedCorners() throws {
        let radius: CGFloat = 10
        let processor = ImageProcessors.RoundedCorners(radius: radius)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.roundedCorners(radius: radius)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsAnonymous() throws {
        let id = UUID().uuidString
        let closure: (@Sendable (PlatformImage) -> PlatformImage?) = { _ in nil }
        let processor = ImageProcessors.Anonymous(id: id, closure)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.process(id: id, closure)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
#if os(iOS) || os(tvOS) || os(macOS)
    func testPassingProcessorsUsingProtocolExtensionsCoreImageFilterWithNameOnly() throws {
        let name = "CISepiaTone"
        let processor = ImageProcessors.CoreImageFilter(name: name)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.coreImageFilter(name: name)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsCoreImageFilter() throws {
        let name = "CISepiaTone"
        let id = UUID().uuidString
        let processor = ImageProcessors.CoreImageFilter(name: name, parameters: [:], identifier: id)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.coreImageFilter(name: name, parameters: [:], identifier: id)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsGaussianBlurEmpty() throws {
        let processor = ImageProcessors.GaussianBlur()
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.gaussianBlur()]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
    
    func testPassingProcessorsUsingProtocolExtensionsGaussianBlur() throws {
        let radius = 10
        let processor = ImageProcessors.GaussianBlur(radius: radius)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.gaussianBlur(radius: radius)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
#endif
}
