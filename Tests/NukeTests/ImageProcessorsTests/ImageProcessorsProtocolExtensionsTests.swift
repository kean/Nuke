// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

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
    
    func testPassingProcessorsUsingProtocolExtensionsHeightOnly() throws {
        let processor = ImageProcessors.Resize(height: 100)
        
        let request = try XCTUnwrap(ImageRequest(url: nil, processors: [.resize(height: 100)]))
        
        XCTAssertEqual(request.processors.first?.identifier, processor.identifier)
    }
}
