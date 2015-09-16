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
    var mockSessionManager: MockImageDataLoader!
    
    override func setUp() {
        super.setUp()
        
        self.mockSessionManager = MockImageDataLoader()
        let configuration = ImageManagerConfiguration(dataLoader: self.mockSessionManager, cache: nil, processor: nil)
        self.manager = ImageManager(configuration: configuration)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatRequestIsCompelted() {
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask = self.manager.imageTaskWithRequest(request) { response -> Void in
            XCTAssertNotNil(response.image, "")
            expecation.fulfill()
        }
        imageTask.resume()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    // MARK: Cancellation
    
    func testThatResumedTaskIsCancelled() {
        self.mockSessionManager.enabled = false
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let task = self.manager.imageTaskWithRequest(request) { response -> Void in
            switch response {
            case .Success(_, _): XCTFail()
            case let .Failure(error):
                XCTAssertEqual(error.domain, ImageManagerErrorDomain, "")
                XCTAssertEqual(error.code, ImageManagerErrorCancelled, "")
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
        let task = self.manager.imageTaskWithRequest(request) { response -> Void in
            switch response {
            case .Success(_, _): XCTFail()
            case let .Failure(error):
                XCTAssertEqual(error.domain, ImageManagerErrorDomain, "")
                XCTAssertEqual(error.code, ImageManagerErrorCancelled, "")
            }
            expecation.fulfill()
        }
        task.cancel()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    func testThatResumedSessionDataTaskIsCancelled() {
        self.mockSessionManager.enabled = false
        self.expectationForNotification(MockURLSessionDataTaskDidResumeNotification, object: nil, handler: nil)
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let task = self.manager.imageTaskWithRequest(request, completion: nil)
        task.resume()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
        
        self.expectationForNotification(MockURLSessionDataTaskDidCancelNotification, object: nil, handler: nil)
        task.cancel()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    // MARK: Data Tasks Reuse
    
    func testThatDataTasksAreReused() {
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask = self.manager.imageTaskWithRequest(request) { (_) -> Void in
            expecation.fulfill()
        }
        imageTask.resume()
        
        let expectation2 = self.expectationWithDescription("Expectation2")
        let request2 = ImageRequest(URL: NSURL(string: "http://test.com")!)
        let imageTask2 = self.manager.imageTaskWithRequest(request2) { (_) -> Void in
            expectation2.fulfill()
        }
        imageTask2.resume()
        
        self.waitForExpectationsWithTimeout(3.0) { (_) -> Void in
            XCTAssertTrue(self.mockSessionManager.createdTaskCount == 1, "Error")
        }
    }
    
    // MARK: Progress
    
    func testThatProgressObjectCancelsTask() {
        self.mockSessionManager.enabled = false

        let task = self.manager.imageTaskWithURL(NSURL(string: "http://test.com")!, completion: nil)
        task.resume()
        self.expectationForNotification(MockURLSessionDataTaskDidCancelNotification, object: nil, handler: nil)
        
        let progress = task.progress
        XCTAssertNotNil(progress)
        XCTAssertTrue(progress.cancellable)
        progress.cancel()
        
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
    
    // MARK: Preheating
    
    func testThatPreheatingRequestsAreStopped() {
        self.mockSessionManager.enabled = false
        
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        self.expectationForNotification(MockURLSessionDataTaskDidResumeNotification, object: nil, handler: nil)
        
        self.manager.startPreheatingImages([request])
        // DFImageManager doesn't start preheating operations after a certain delay
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
        
        self.expectationForNotification(MockURLSessionDataTaskDidCancelNotification, object: nil, handler: nil)
        self.manager.stopPreheatingImages([request])
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    func testThatSimilarPreheatingRequestsAreStoppedWithSingleStopCall() {
        self.mockSessionManager.enabled = false
        
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        self.expectationForNotification(MockURLSessionDataTaskDidResumeNotification, object: nil, handler: nil)
        self.manager.startPreheatingImages([request, request])
        self.manager.startPreheatingImages([request])
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
        
        self.expectationForNotification(MockURLSessionDataTaskDidCancelNotification, object: nil, handler: nil)
        self.manager.stopPreheatingImages([request])
        
        self.waitForExpectationsWithTimeout(3.0) { (_) -> Void in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1, "")
        }
    }
    
    func testThatAllPreheatingRequests() {
        self.mockSessionManager.enabled = false
        
        let request = ImageRequest(URL: NSURL(string: "http://test.com")!)
        self.expectationForNotification(MockURLSessionDataTaskDidResumeNotification, object: nil, handler: nil)
        self.manager.startPreheatingImages([request])
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
        
        self.expectationForNotification(MockURLSessionDataTaskDidCancelNotification, object: nil, handler: nil)
        self.manager.stopPreheatingImages()
        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
    
    // MARK: Invalidation
    
    func testThatInvalidateAndCancelMethodCancelsOutstandingRequests() {
        self.mockSessionManager.enabled = false
        
        // More than 1 image task!
        self.manager.imageTaskWithURL(NSURL(string: "http://test.com")!, completion: nil).resume()
        self.manager.imageTaskWithURL(NSURL(string: "http://test2.com")!, completion: nil).resume()
        var callbackCount = 0
        self.expectationForNotification(MockURLSessionDataTaskDidCancelNotification, object: nil) { (_) -> Bool in
            callbackCount++
            return callbackCount == 2
        }
        self.manager.invalidateAndCancel()
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}
