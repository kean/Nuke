// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImagePreheaterTests: XCTestCase {
    var pipeline: MockImagePipeline!
    var preheater: ImagePreheater!

    override func setUp() {
        super.setUp()

        pipeline = MockImagePipeline()
        preheater = ImagePreheater(pipeline: pipeline)
    }
    
    // MARK: Starting and Stoping Preheating

    func testThatPreheatingRequestsAreStopped() {
        pipeline.queue.isSuspended = true

        let request = ImageRequest(url: defaultURL)
        _ = expectNotification(MockImagePipeline.DidStartTask, object: pipeline)
        preheater.startPreheating(with: [request])
        wait()

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        preheater.stopPreheating(with: [request])
        wait()
    }

    func testThatEquaivalentRequestsAreStoppedWithSingleStopCall() {
        pipeline.queue.isSuspended = true

        let request = ImageRequest(url: defaultURL)
        _ = expectNotification(MockImagePipeline.DidStartTask, object: pipeline)
        preheater.startPreheating(with: [request, request])
        preheater.startPreheating(with: [request])
        wait()

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        preheater.stopPreheating(with: [request])

        wait { _ in
            XCTAssertEqual(self.pipeline.createdTaskCount, 1, "")
        }
    }

    func testThatAllPreheatingRequestsAreStopped() {
        pipeline.queue.isSuspended = true

        let request = ImageRequest(url: defaultURL)
        _ = expectNotification(MockImagePipeline.DidStartTask, object: pipeline)
        preheater.startPreheating(with: [request])
        wait()

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        preheater.stopPreheating()
        wait()
    }
    
    // MARK: Thread Safety
    
    func testPreheatingThreadSafety() {
        func makeRequests() -> [ImageRequest] {
            return (0...rnd(30)).map { _ in
                return ImageRequest(url: URL(string: "http://\(rnd(15))")!)
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
