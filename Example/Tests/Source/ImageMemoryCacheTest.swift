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
    var mockSessionManager: MockImageDataLoader!
    
    override func setUp() {
        super.setUp()

        self.mockSessionManager = MockImageDataLoader()
        let configuration = ImageManagerConfiguration(dataLoader: self.mockSessionManager, cache: ImageMemoryCache())
        self.manager = ImageManager(configuration: configuration)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatImageIsReturnedFromMemoryCache() {
        let expecation = self.expectation()
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask = self.manager.taskWithRequest(request) { (response) -> Void in
            XCTAssertNotNil(response.image, "")
            expecation.fulfill()
        }
        imageTask.resume()
        self.wait()
        
        self.mockSessionManager.enabled = false
        
        let request2 = ImageRequest(URL: NSURL(string: "http://test.com")!)
        var isCompletionCalled = false
        let imageTask2 = self.manager.taskWithRequest(request2) { (response) -> Void in
            XCTAssertNotNil(response.image, "")
            // Comletion block should be called on the main thread
            isCompletionCalled = true
        }
        imageTask2.resume()
        XCTAssertTrue(isCompletionCalled, "")
    }
}
