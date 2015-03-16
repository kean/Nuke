//
//  ImageMemoryCacheTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/15/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import XCTest
import Nuke

class ImageMemoryCacheTest: XCTestCase {
    var manager: ImageManager!
    var mockSessionManager: MockURLSessionManager!
    
    override func setUp() {
        super.setUp()

        self.mockSessionManager = MockURLSessionManager()
        let configuration = ImageManagerConfiguration(sessionManager: self.mockSessionManager, cache: ImageMemoryCache())
        self.manager = ImageManager(configuration: configuration)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatImageIsReturnedFromMemoryCache() {
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask = self.manager.imageTaskWithRequest(request) { (response) -> Void in
            XCTAssertNotNil(response.image, "")
            expecation.fulfill()
        }
        imageTask.resume()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
        
        self.mockSessionManager.enabled = false
        
        let expecation2 = self.expectationWithDescription("Expectation")
        let request2 = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask2 = self.manager.imageTaskWithRequest(request2) { (response) -> Void in
            XCTAssertNotNil(response.image, "")
            expecation2.fulfill()
        }
        imageTask2.resume()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
}
