// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class NukeTests: XCTestCase {
    var view: ImageView!
    var pipeline: MockImagePipeline!

    override func setUp() {
        super.setUp()

        view = ImageView()
        pipeline = MockImagePipeline()
    }

    func testThatImageIsLoaded() {
        expect { fulfill in
            Nuke.loadImage(with: ImageRequest(url: defaultURL), pipeline: pipeline, into: view) {
                XCTAssertTrue(Thread.isMainThread)
                if case .success(_) = $0 {
                    fulfill()
                }
                XCTAssertFalse($1)
            }
        }
        wait()
    }

    func testThatImageLoadedIntoTarget() {
        expect { fulfill in
            let target = MockTarget()
            target.handler = { resolution, isFromMemoryCache in
                XCTAssertTrue(Thread.isMainThread)
                if case .success(_) = resolution {
                    fulfill()
                }
                XCTAssertFalse(isFromMemoryCache)

                // capture target in a closure
                target.handler = nil
            }

            Nuke.loadImage(with: defaultURL, pipeline: pipeline, into: target)
        }
        wait()
    }

    func testThatPreviousTaskIsCancelledWhenNewOneIsCreated() {
        expect { fulfill in
            Nuke.loadImage(with: ImageRequest(url: URL(string: "http://test.com/1")!), pipeline: pipeline, into: view, handler: { result, isFromMemoryCache in
                XCTFail()
            })

            Nuke.loadImage(with: ImageRequest(url: URL(string: "http://test.com/2")!), pipeline: pipeline, into: view, handler: { result, isFromMemoryCache in
                if case .success = result {
                    fulfill()
                }
            })
        }
        wait()
    }

    func testThatRequestIsCancelledWhenTargetIsDeallocated() {
        pipeline.queue.isSuspended = true

        var target: ImageView! = ImageView()

        Nuke.loadImage(with: defaultURL, pipeline: pipeline, into: target)

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        target = nil // deallocate target
        wait()
    }

    func testThatRequestIsCancelledWhenTargetIsDeallocatedWithHandler() {
        pipeline.queue.isSuspended = true

        var target: ImageView! = ImageView()

        Nuke.loadImage(with: defaultURL, pipeline: pipeline, into: target) { (_,_) in
            XCTFail()
        }

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        target = nil // deallocate target
        wait()
    }
}
