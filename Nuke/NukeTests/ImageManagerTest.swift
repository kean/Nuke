//
//  ImageManagerTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import XCTest
import Nuke

class ImageManagerTest: XCTestCase {
    var manager: ImageManager!
    var mockSessionManager: MockURLSessionManager!
    
    override func setUp() {
        super.setUp()
        
        self.mockSessionManager = MockURLSessionManager()
        self.manager = ImageManager(sessionManager: mockSessionManager)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatRequestIsCompelted() {
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask = self.manager.imageTaskWithRequest(request) { (response) -> Void in
            expecation.fulfill()
        }
        imageTask.resume()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    func testThatResumedTaskIsCancelled() {
        self.mockSessionManager.enabled = false
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let task = self.manager.imageTaskWithRequest(request) { (response) -> Void in
            if let error = response.error {
                XCTAssertEqual(error.domain, ImageManagerErrorDomain, "")
                XCTAssertEqual(error.code, ImageManagerErrorCancelled, "")
            } else {
                XCTFail("")
            }
            expecation.fulfill()
        }
        task.resume()
        task.cancel()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    func testThatNeverResumedTaskIsCancelled() {
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let task = self.manager.imageTaskWithRequest(request) { (response) -> Void in
            if let error = response.error {
                XCTAssertEqual(error.domain, ImageManagerErrorDomain, "")
                XCTAssertEqual(error.code, ImageManagerErrorCancelled, "")
            } else {
                XCTFail("")
            }
            expecation.fulfill()
        }
        task.cancel()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    func testThatResumedSessionDataTaskIsCancelled() {
        self.mockSessionManager.enabled = false
        self.expectationForNotification(MockURLSsessionDataTaskDidResumeNotification, object: nil, handler: nil)
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let task = self.manager.imageTaskWithRequest(request, completionHandler: nil)
        task.resume()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
        
        self.expectationForNotification(MockURLSsessionDataTaskDidCancelNotification, object: nil, handler: nil)
        task.cancel()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    
    
    func testThatDataTasksAreReused() {
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask = self.manager.imageTaskWithRequest(request) { (response) -> Void in
            expecation.fulfill()
        }
        imageTask.resume()
        
        let expectation2 = self.expectationWithDescription("Expectation2")
        let request2 = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask2 = self.manager.imageTaskWithRequest(request) { (response) -> Void in
            expectation2.fulfill()
        }
        imageTask2.resume()
        
        self.waitForExpectationsWithTimeout(3.0, handler: { (error: NSError!) -> Void in
            XCTAssertTrue(self.mockSessionManager.createdTaskCount == 1, "Error")
        })
    }
}
