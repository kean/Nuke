// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageTargetTests: XCTestCase {
    var pipeline: MockImagePipeline!
    var target: MockTarget!

    override func setUp() {
        super.setUp()

        pipeline = MockImagePipeline()
        target = MockTarget()
    }

    func testThatImageIsLoaded() {
        expect { fulfill in
            target.handler = { response, _, isFromMemoryCache in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(response)
                XCTAssertFalse(isFromMemoryCache)
                fulfill()
            }
            Nuke.loadImage(with: ImageRequest(url: defaultURL), pipeline: pipeline, into: target)
        }
        wait()
    }

    func testThatImageLoadedIntoTarget() {
        expect { fulfill in
            target.handler = { response, _, isFromMemoryCache in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(response)
                XCTAssertFalse(isFromMemoryCache)
                fulfill()

                // capture target in a closure
                self.target.handler = nil
            }
            Nuke.loadImage(with: defaultURL, pipeline: pipeline, into: target)
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
}
