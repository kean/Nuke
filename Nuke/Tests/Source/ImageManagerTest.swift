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
        let configuration = ImageManagerConfiguration(dataLoader: self.mockSessionManager, cache: nil)
        self.manager = ImageManager(configuration: configuration)
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Basics

    func testThatRequestIsCompelted() {
        self.expect { fulfill in
            self.manager.taskWithRequest(ImageRequest(URL: defaultURL)) {
                XCTAssertNotNil($0.image, "")
                fulfill()
            }.resume()
        }
        self.wait()
    }

    func testThatTaskChangesStateWhenCompleted() {
        let task = self.manager.taskWithURL(defaultURL)
        XCTAssertEqual(task.state, ImageTaskState.Suspended)
        self.expect { fulfill in
            task.completion { _ in
                XCTAssertEqual(task.state, ImageTaskState.Completed)
                fulfill()
            }
        }
        task.resume()
        XCTAssertEqual(task.state, ImageTaskState.Running)
        self.wait()
    }

    func testThatTaskChangesStateOnCallersThreadWhenCompleted() {
        let expectation = self.expectation()
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            let task = self.manager.taskWithURL(defaultURL)
            XCTAssertEqual(task.state, ImageTaskState.Suspended)
            task.completion { _ in
                XCTAssertEqual(task.state, ImageTaskState.Completed)
                expectation.fulfill()
            }
            task.resume()
            XCTAssertEqual(task.state, ImageTaskState.Running)
        }
        self.wait()
    }

    func testThatMultipleCompletionsCanBeAdded() {
        let task = self.manager.taskWithURL(defaultURL)
        self.expect { fulfill in
            task.completion {
                XCTAssertNotNil($0.image, "")
                fulfill()
            }
        }
        self.expect { fulfill in
            task.completion {
                XCTAssertNotNil($0.image, "")
                fulfill()
            }
        }
        task.resume()
        self.wait()
    }

    func testThatCompletionsCanBeAddedForResumedAndCompletedTask() {
        let task = self.manager.taskWithURL(defaultURL)
        self.expect { fulfill in
            task.completion {
                XCTAssertNotNil($0.image, "")
                fulfill()
            }
        }
        task.resume()

        self.expect { fulfill in
            task.completion {
                XCTAssertNotNil($0.image, "")
                fulfill()
            }
        }
        self.wait()

        XCTAssertEqual(task.state, ImageTaskState.Completed)

        self.expect { fulfill in
            task.completion {
                XCTAssertNotNil($0.image, "")
                fulfill()
            }
        }
        self.wait()
    }

    // MARK: Cancellation

    func testThatResumedTaskIsCancelled() {
        self.mockSessionManager.enabled = false

        let task = self.manager.taskWithURL(defaultURL)

        self.expect { fulfill in
            task.completion { response -> Void in
                switch response {
                case .Success(_, _): XCTFail()
                case let .Failure(error):
                    XCTAssertEqual((error as NSError).domain, ImageManagerErrorDomain, "")
                    XCTAssertEqual((error as NSError).code, ImageManagerErrorCancelled, "")
                }
                XCTAssertEqual(task.state, ImageTaskState.Cancelled)
                fulfill()
            }
        }

        XCTAssertEqual(task.state, ImageTaskState.Suspended)
        task.resume()
        XCTAssertEqual(task.state, ImageTaskState.Running)
        task.cancel()
        XCTAssertEqual(task.state, ImageTaskState.Cancelled)

        self.wait()
    }

    func testThatSuspendedTaskIsCancelled() {
        let task = self.manager.taskWithURL(defaultURL)
        self.expect { fulfill in
            task.completion { response -> Void in
                switch response {
                case .Success(_, _): XCTFail()
                case let .Failure(error):
                    XCTAssertEqual((error as NSError).domain, ImageManagerErrorDomain, "")
                    XCTAssertEqual((error as NSError).code, ImageManagerErrorCancelled, "")
                }
                XCTAssertEqual(task.state, ImageTaskState.Cancelled)
                fulfill()
            }
        }
        XCTAssertEqual(task.state, ImageTaskState.Suspended)
        task.cancel()
        XCTAssertEqual(task.state, ImageTaskState.Cancelled)
        self.wait()
    }

    func testThatSessionDataTaskIsCancelled() {
        self.mockSessionManager.enabled = false

        self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        let task = self.manager.taskWithURL(defaultURL).resume()
        self.wait()

        self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        task.cancel()
        self.wait()
    }

    // MARK: Data Tasks Reusing

    func testThatDataTasksAreReused() {
        let request1 = ImageRequest(URL: defaultURL)
        let request2 = ImageRequest(URL: defaultURL)
        XCTAssertTrue(self.mockSessionManager.isRequestLoadEquivalent(request1, toRequest: request2))

        self.expect { fulfill in
            self.manager.taskWithRequest(request1) { _ in
                fulfill()
            }.resume()
        }

        self.expect { fulfill in
            self.manager.taskWithRequest(request2) { _ in
                fulfill()
            }.resume()
        }

        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1)
        }
    }
    
    func testThatDataTasksWithDifferentCachePolicyAreNotReused() {
        let request1 = ImageRequest(URLRequest: NSURLRequest(URL: defaultURL, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(URLRequest: NSURLRequest(URL: defaultURL, cachePolicy: .ReturnCacheDataDontLoad, timeoutInterval: 0))
        XCTAssertTrue(self.mockSessionManager.isRequestCacheEquivalent(request1, toRequest: request2))
        XCTAssertFalse(self.mockSessionManager.isRequestLoadEquivalent(request1, toRequest: request2))
        
        self.expect { fulfill in
            self.manager.taskWithRequest(request1) { _ in
                fulfill()
                }.resume()
        }
        
        self.expect { fulfill in
            self.manager.taskWithRequest(request2) { _ in
                fulfill()
                }.resume()
        }
        
        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 2)
        }
    }
    
    func testThatDataTaskWithRemainingTasksDoesntGetCancelled() {
        self.mockSessionManager.enabled = false
        
        self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        let task1 = self.manager.taskWithURL(defaultURL).resume()
        let task2 = self.manager.taskWithURL(defaultURL).resume()
        self.wait()
        
        self.expect { fulfill in
            task1.completion {
                XCTAssertEqual(task1.state, ImageTaskState.Cancelled)
                XCTAssertNil($0.image)
                fulfill()
            }
        }
        
        self.expect { fulfill in
            task2.completion {
                XCTAssertEqual(task2.state, ImageTaskState.Completed)
                XCTAssertNotNil($0.image)
                fulfill()
            }
        }
        
        task1.cancel()
        self.mockSessionManager.enabled = true
        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1)
        }
    }

    // MARK: Suspending

    func testThatDataTaskIsSuspended() {
        self.mockSessionManager.enabled = false

        let task = self.manager.taskWithURL(defaultURL).resume()
        XCTAssertEqual(task.state, ImageTaskState.Running)

        self.expectNotification(MockURLSessionDataTaskDidSuspendNotification)
        task.suspend()
        XCTAssertEqual(task.state, ImageTaskState.Suspended)

        self.wait()
    }

    func testThatSuspendedDataTaskIsResumed() {
        self.mockSessionManager.enabled = false

        let task = self.manager.taskWithURL(defaultURL).resume()
        self.expectNotification(MockURLSessionDataTaskDidSuspendNotification)
        task.suspend()
        self.wait()

        self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        self.expect { fulfill in
            task.completion {
                XCTAssertEqual(task.state, ImageTaskState.Completed)
                XCTAssertNotNil($0.image)
                fulfill()
            }
        }
        self.mockSessionManager.enabled = true
        task.resume()
        self.wait()
    }

    func testThatDataTaskIsNotSuspendedWhenAtLeastOneExecutingTaskIsRegistered() {
        self.mockSessionManager.enabled = false

        self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        let task1 = self.manager.taskWithURL(defaultURL).resume()
        let task2 = self.manager.taskWithURL(defaultURL).resume()
        self.wait()

        self.expect { fulfill in
            task1.completion {
                XCTAssertEqual(task1.state, ImageTaskState.Completed)
                XCTAssertNotNil($0.image)
                fulfill()
            }
        }

        self.expect { fulfill in
            task2.completion {
                XCTAssertEqual(task2.state, ImageTaskState.Completed)
                XCTAssertNotNil($0.image)
                fulfill()
            }
        }

        task2.suspend()

        self.mockSessionManager.enabled = true
        self.wait()
    }

    func testThatDataTaskIsSuspendedWithTwoSuspendedTasksRegisteredWithIt() {
        self.mockSessionManager.enabled = false

        self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        let task1 = self.manager.taskWithURL(defaultURL).resume()
        let task2 = self.manager.taskWithURL(defaultURL).resume()
        self.wait()

        self.expectNotification(MockURLSessionDataTaskDidSuspendNotification)
        task1.suspend()
        task2.suspend()
        self.wait()
    }

    // MARK: Progress

    func testThatProgressClosureIsCalled() {
        let task = self.manager.taskWithURL(defaultURL, completion: nil)
        XCTAssertEqual(task.totalUnitCount, 0)
        XCTAssertEqual(task.completedUnitCount, 0)
        XCTAssertEqual(task.fractionCompleted, 0.0)
        
        self.expect { fulfill in
            var fractionCompleted = 0.0
            var completedUnitCount: Int64 = 0
            task.progress = { completed, total in
                fractionCompleted += 0.5
                completedUnitCount += 50
                XCTAssertEqual(completedUnitCount, completed)
                XCTAssertEqual(100, total)
                XCTAssertEqual(completedUnitCount, task.completedUnitCount)
                XCTAssertEqual(100, task.totalUnitCount)
                XCTAssertEqual(fractionCompleted, task.fractionCompleted)
                if task.fractionCompleted == 1.0 {
                    fulfill()
                }
            }
        }
        task.resume()
        self.wait()
    }

    // MARK: Preheating

    func testThatPreheatingRequestsAreStopped() {
        self.mockSessionManager.enabled = false

        let request = ImageRequest(URL: defaultURL)
        self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        self.manager.startPreheatingImages([request])
        self.wait()

        self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        self.manager.stopPreheatingImages([request])
        self.wait()
    }

    func testThatSimilarPreheatingRequestsAreStoppedWithSingleStopCall() {
        self.mockSessionManager.enabled = false

        let request = ImageRequest(URL: defaultURL)
        self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        self.manager.startPreheatingImages([request, request])
        self.manager.startPreheatingImages([request])
        self.wait()

        self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        self.manager.stopPreheatingImages([request])

        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1, "")
        }
    }

    func testThatAllPreheatingRequestsAreStopped() {
        self.mockSessionManager.enabled = false

        let request = ImageRequest(URL: defaultURL)
        self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        self.manager.startPreheatingImages([request])
        self.wait(2)

        self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        self.manager.stopPreheatingImages()
        self.wait(2)
    }

    // MARK: Invalidation

    func testThatInvalidateAndCancelMethodCancelsOutstandingRequests() {
        self.mockSessionManager.enabled = false

        // More than 1 image task!
        self.manager.taskWithURL(defaultURL, completion: nil).resume()
        self.manager.taskWithURL(NSURL(string: "http://test2.com")!, completion: nil).resume()
        var callbackCount = 0
        self.expectNotification(MockURLSessionDataTaskDidCancelNotification) { _ in
            callbackCount++
            return callbackCount == 2
        }
        self.manager.invalidateAndCancel()
        self.wait()
    }
}
