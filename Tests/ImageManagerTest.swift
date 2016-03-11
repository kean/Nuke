//
//  ImageManagerTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import XCTest
import Nuke

class ImageManagerTest: XCTestCase {
    var manager: ImageManager!
    var mockSessionManager: MockImageDataLoader!

    override func setUp() {
        super.setUp()

        self.mockSessionManager = MockImageDataLoader()
        var loaderConfiguration = ImageLoaderConfiguration(dataLoader: self.mockSessionManager)
        loaderConfiguration.congestionControlEnabled = false
        self.manager = ImageManager(configuration: ImageManagerConfiguration(loader: ImageLoader(configuration: loaderConfiguration), cache: nil))
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Basics

    func testThatRequestIsCompelted() {
        self.expect { fulfill in
            self.manager.taskWith(ImageRequest(URL: defaultURL)) {
                XCTAssertNotNil($0.image, "")
                fulfill()
            }.resume()
        }
        self.wait()
    }

    func testThatTaskChangesStateWhenCompleted() {
        let task = self.manager.taskWith(defaultURL)
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
            let task = self.manager.taskWith(defaultURL)
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
        let task = self.manager.taskWith(defaultURL)
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
        let task = self.manager.taskWith(defaultURL)
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

        let task = self.manager.taskWith(defaultURL)

        self.expect { fulfill in
            task.completion { response -> Void in
                switch response {
                case .Success(_, _): XCTFail()
                case let .Failure(error):
                    XCTAssertEqual((error as NSError).domain, ImageManagerErrorDomain, "")
                    XCTAssertEqual((error as NSError).code, ImageManagerErrorCode.Cancelled.rawValue, "")
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
        let task = self.manager.taskWith(defaultURL)
        self.expect { fulfill in
            task.completion { response -> Void in
                switch response {
                case .Success(_, _): XCTFail()
                case let .Failure(error):
                    XCTAssertEqual((error as NSError).domain, ImageManagerErrorDomain, "")
                    XCTAssertEqual((error as NSError).code, ImageManagerErrorCode.Cancelled.rawValue, "")
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
        let task = self.manager.taskWith(defaultURL).resume()
        self.wait()

        self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        task.cancel()
        self.wait()
    }

    // MARK: Data Tasks Reusing

    func testThatDataTasksAreReused() {
        let request1 = ImageRequest(URL: defaultURL)
        let request2 = ImageRequest(URL: defaultURL)

        self.expect { fulfill in
            self.manager.taskWith(request1) { _ in
                fulfill()
            }.resume()
        }

        self.expect { fulfill in
            self.manager.taskWith(request2) { _ in
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
        
        self.expect { fulfill in
            self.manager.taskWith(request1) { _ in
                fulfill()
            }.resume()
        }
        
        self.expect { fulfill in
            self.manager.taskWith(request2) { _ in
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
        let task1 = self.manager.taskWith(defaultURL).resume()
        let task2 = self.manager.taskWith(defaultURL).resume()
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

    // MARK: Progress

    func testThatProgressClosureIsCalled() {
        let task = self.manager.taskWith(defaultURL, completion: nil)
        XCTAssertEqual(task.progress.total, 0)
        XCTAssertEqual(task.progress.completed, 0)
        XCTAssertEqual(task.progress.fractionCompleted, 0.0)
        
        self.expect { fulfill in
            var fractionCompleted = 0.0
            var completedUnitCount: Int64 = 0
            task.progressHandler = { progress in
                fractionCompleted += 0.5
                completedUnitCount += 50
                XCTAssertEqual(completedUnitCount, progress.completed)
                XCTAssertEqual(100, progress.total)
                XCTAssertEqual(completedUnitCount, task.progress.completed)
                XCTAssertEqual(100, task.progress.total)
                XCTAssertEqual(fractionCompleted, task.progress.fractionCompleted)
                if task.progress.fractionCompleted == 1.0 {
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
        self.manager.taskWith(defaultURL, completion: nil).resume()
        self.manager.taskWith(NSURL(string: "http://test2.com")!, completion: nil).resume()
        var callbackCount = 0
        self.expectNotification(MockURLSessionDataTaskDidCancelNotification) { _ in
            callbackCount += 1
            return callbackCount == 2
        }
        self.manager.invalidateAndCancel()
        self.wait()
    }
    
    // MARK: Misc
    
    func testThatGetImageTasksMethodReturnsCorrectTasks() {
        self.mockSessionManager.enabled = false
        
        let task1 = self.manager.taskWith(NSURL(string: "http://test1.com")!, completion: nil)
        let task2 = self.manager.taskWith(NSURL(string: "http://test2.com")!, completion: nil)
        
        task1.resume()
        
        // task3 is not getting resumed
        
        self.expect { fulfill in
            let (executingTasks, _) = self.manager.tasks
            XCTAssertEqual(executingTasks.count, 1)
            XCTAssertTrue(executingTasks.contains(task1))
            XCTAssertEqual(task1.state, ImageTaskState.Running)
            XCTAssertFalse(executingTasks.contains(task2))
            XCTAssertEqual(task2.state, ImageTaskState.Suspended)
            fulfill()
        }
        self.wait()
    }
}
