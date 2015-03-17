//
//  NukeTests.swift
//  NukeTests
//
//  Created by Alexander Grebenyuk on 3/12/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import Nuke
import UIKit
import XCTest

class NukeTests: XCTestCase {
    func testExample() {
        let configuration = ImageManagerConfiguration(sessionManager: URLSessionManager(), cache: ImageMemoryCache(), processor: ImageProcessor())
        let manager = ImageManager(configuration: configuration)
        let request = ImageRequest(URL: NSURL(string: "https://raw.githubusercontent.com/kean/DFImageManager/master/DFImageManager/Tests/Resources/Image.jpg")!)
        let expectation = self.expectationWithDescription("Desc")
        let task = manager.imageTaskWithRequest(request) { (image, error) -> Void in
            XCTAssertNotNil(image, "")
            expectation.fulfill()
        }
        task.resume()
        self.waitForExpectationsWithTimeout(10.0, handler: nil)
    }
}
