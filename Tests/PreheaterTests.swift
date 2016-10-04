// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class PreheaterTests: XCTestCase {
    var loader: MockImageLoader!
    var preheater: Preheater!

    override func setUp() {
        super.setUp()

        loader = MockImageLoader()
        preheater = Preheater(loader: loader)
    }
    
    // MARK: Starting and Stoping Preheating

    func testThatPreheatingRequestsAreStopped() {
        loader.queue.isSuspended = true

        let request = Request(url: defaultURL)
        _ = expectNotification(MockImageLoader.DidStartTask, object: loader)
        preheater.startPreheating(with: [request])
        wait()

        _ = expectNotification(MockImageLoader.DidCancelTask, object: loader)
        preheater.stopPreheating(with: [request])
        wait()
    }

    func testThatEquaivalentRequestsAreStoppedWithSingleStopCall() {
        loader.queue.isSuspended = true

        let request = Request(url: defaultURL)
        _ = expectNotification(MockImageLoader.DidStartTask, object: loader)
        preheater.startPreheating(with: [request, request])
        preheater.startPreheating(with: [request])
        wait()

        _ = expectNotification(MockImageLoader.DidCancelTask, object: loader)
        preheater.stopPreheating(with: [request])

        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 1, "")
        }
    }

    func testThatAllPreheatingRequestsAreStopped() {
        loader.queue.isSuspended = true

        let request = Request(url: defaultURL)
        _ = expectNotification(MockImageLoader.DidStartTask, object: loader)
        preheater.startPreheating(with: [request])
        wait(2)

        _ = expectNotification(MockImageLoader.DidCancelTask, object: loader)
        preheater.stopPreheating()
        wait(2)
    }
    
    // MARK: Thread Safety
    
    func testPreheatingThreadSafety() {
        func makeRequests() -> [Request] {
            return (0...rnd(30)).map { _ in
                return Request(url: URL(string: "http://\(rnd(15))")!)
            }
        }
        for _ in 0...1000 {
            expect { fulfill in
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(rnd(1))) {
                    self.preheater.stopPreheating(with: makeRequests())
                    self.preheater.startPreheating(with: makeRequests())
                    fulfill()
                }
            }
        }
        
        wait(10)
    }
}
