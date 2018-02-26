// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ManagerTests: XCTestCase {
    var view: ImageView!
    var loader: MockImageLoader!
    var manager: Manager!

    override func setUp() {
        super.setUp()

        view = ImageView()
        loader = MockImageLoader()
        manager = Manager(loader: loader)
    }

    func testThatImageIsLoaded() {
        expect { fulfill in
            manager.loadImage(with: Request(url: defaultURL), into: view) {
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

            manager.loadImage(with: defaultURL, into: target)
        }
        wait()
    }

    func testThatPreviousTaskIsCancelledWhenNewOneIsCreated() {
        expect { fulfill in
            manager.loadImage(with: Request(url: URL(string: "http://test.com/1")!), into: view, handler: { result, isFromMemoryCache in
                XCTFail()
            })

            manager.loadImage(with: Request(url: URL(string: "http://test.com/2")!), into: view, handler: { result, isFromMemoryCache in
                if case .success = result {
                    fulfill()
                }
            })
        }
        wait()
    }

    func testThatRequestIsCancelledWhenTargetIsDeallocated() {
        loader.queue.isSuspended = true

        var target: ImageView! = ImageView()

        manager.loadImage(with: defaultURL, into: target)

        _ = expectNotification(MockImageLoader.DidCancelTask, object: loader)
        target = nil // deallocate target
        wait()
    }

    func testThatRequestIsCancelledWhenTargetIsDeallocatedWithHandler() {
        loader.queue.isSuspended = true

        var target: ImageView! = ImageView()

        manager.loadImage(with: defaultURL, into: target) { (_,_) in
            XCTFail()
        }

        _ = expectNotification(MockImageLoader.DidCancelTask, object: loader)
        target = nil // deallocate target
        wait()
    }
}
