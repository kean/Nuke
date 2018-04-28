// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageViewTests: XCTestCase {
    var pipeline: MockImagePipeline!
    var target: ImageView!

    override func setUp() {
        super.setUp()

        pipeline = MockImagePipeline()
        target = ImageView()
    }

    func testThatImageIsLoaded() {
        expect { fulfill in
            Nuke.loadImage(
                with: ImageRequest(url: defaultURL),
                options: ImageLoadingOptions(
                    pipeline: pipeline,
                    completion: { response, _, isFromMemoryCache in
                        XCTAssertTrue(Thread.isMainThread)
                        XCTAssertNotNil(response)
                        XCTAssertFalse(isFromMemoryCache)
                        fulfill()
                }),
                into: target
            )
        }
        wait()
    }

    func testThatRequestIsCancelledWhenTargetIsDeallocated() {
        pipeline.queue.isSuspended = true

        Nuke.loadImage(with: defaultURL, options: ImageLoadingOptions(pipeline: pipeline), into: target)

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        target = nil // deallocate target
        wait()
    }
}
