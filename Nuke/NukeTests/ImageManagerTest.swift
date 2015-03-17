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
        let configuration = ImageManagerConfiguration(sessionManager: self.mockSessionManager, cache: nil, processor: nil)
        self.manager = ImageManager(configuration: configuration)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatRequestIsCompelted() {
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask = self.manager.imageTaskWithRequest(request) { (image, error) -> Void in
            XCTAssertNotNil(image, "")
            expecation.fulfill()
        }
        imageTask.resume()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
        XCTAssertNotNil(imageTask.image, "")
    }
    
    func testThatResumedTaskIsCancelled() {
        self.mockSessionManager.enabled = false
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let task = self.manager.imageTaskWithRequest(request) { (image, error) -> Void in
            if error != nil {
                XCTAssertEqual(error!.domain, ImageManagerErrorDomain, "")
                XCTAssertEqual(error!.code, ImageManagerErrorCancelled, "")
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
        let task = self.manager.imageTaskWithRequest(request) { (image, error) -> Void in
            if error != nil {
                XCTAssertEqual(error!.domain, ImageManagerErrorDomain, "")
                XCTAssertEqual(error!.code, ImageManagerErrorCancelled, "")
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
        let imageTask = self.manager.imageTaskWithRequest(request) { (image, error) -> Void in
            expecation.fulfill()
        }
        imageTask.resume()
        
        let expectation2 = self.expectationWithDescription("Expectation2")
        let request2 = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask2 = self.manager.imageTaskWithRequest(request) { (image, error) -> Void in
            expectation2.fulfill()
        }
        imageTask2.resume()
        
        self.waitForExpectationsWithTimeout(3.0, handler: { (error: NSError!) -> Void in
            XCTAssertTrue(self.mockSessionManager.createdTaskCount == 1, "Error")
        })
    }
    
    // MARK :Preheating
    
    func testThatPreheatingRequestsAreStopped() {
        self.mockSessionManager.enabled = false

        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        self.expectationForNotification(MockURLSsessionDataTaskDidResumeNotification, object: nil, handler: nil)
        
        self.manager.startPreheatingImages([request])
        // DFImageManager doesn't start preheating operations after a certain delay
        self.waitForExpectationsWithTimeout(3.0, handler: nil)

        self.expectationForNotification(MockURLSsessionDataTaskDidCancelNotification, object: nil, handler: nil)
        self.manager.stopPreheatingImages([request])
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    func testThatSimilarPreheatingRequestsAreStoppedWithSingleStopCall() {
        self.mockSessionManager.enabled = false
        
        var request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        self.expectationForNotification(MockURLSsessionDataTaskDidResumeNotification, object: nil, handler: nil)
        self.manager.startPreheatingImages([request, request])
        self.manager.startPreheatingImages([request])
        self.waitForExpectationsWithTimeout(3.0, handler: nil)

        self.expectationForNotification(MockURLSsessionDataTaskDidCancelNotification, object: nil, handler: nil)
        self.manager.stopPreheatingImages([request])
        self.waitForExpectationsWithTimeout(3.0) { (error: NSError!) -> Void in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1, "")
        }
    }
    
    func testThatAllPreheatingRequests() {
        self.mockSessionManager.enabled = false
        
        var request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        self.expectationForNotification(MockURLSsessionDataTaskDidResumeNotification, object: nil, handler: nil)
        self.manager.startPreheatingImages([request])
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
        
        self.expectationForNotification(MockURLSsessionDataTaskDidCancelNotification, object: nil, handler: nil)
        self.manager.stopPreheatingImages()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
}
