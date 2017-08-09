// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

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
                // we don't expect this to be called
                if case .success = result {
                    fulfill()
                }
            })
            
            manager.loadImage(with: Request(url: URL(string: "http://test.com/2")!), into: view, handler: { result, isFromMemoryCache in
                if case .success = result {
                    fulfill()
                }
            })
        }
        wait()
    }
}

class ManagerLoadingWithoutTargetTests: XCTestCase {
    var loader: MockImageLoader!
    var cache: MockCache!
    var manager: Manager!
    
    override func setUp() {
        super.setUp()

        loader = MockImageLoader()
        cache = MockCache()
        manager = Manager(loader: loader, cache: cache)
    }
    
    func testThatImageIsLoaded() {
        waitLoadedImage(with: Request(url: defaultURL))
    }
    
    // MARK: Caching
    
    func testCacheWrite() {
        waitLoadedImage(with: Request(url: defaultURL))
        
        XCTAssertEqual(loader.createdTaskCount, 1)
        XCTAssertNotNil(self.cache[Request(url: defaultURL)])
    }
    
    func testCacheRead() {
        cache[Request(url: defaultURL)] = defaultImage
        
        waitLoadedImage(with: Request(url: defaultURL))
        
        XCTAssertEqual(loader.createdTaskCount, 0)
        XCTAssertNotNil(self.cache[Request(url: defaultURL)])
    }
    
    func testCacheWriteDisabled() {
        let request = Request(url: defaultURL).mutated {
            $0.memoryCacheOptions.writeAllowed = false
        }
        
        waitLoadedImage(with: request)
        
        XCTAssertEqual(loader.createdTaskCount, 1)
        XCTAssertNil(self.cache[Request(url: defaultURL)])
    }
    
    func testCacheReadDisabled() {
        cache[Request(url: defaultURL)] = defaultImage
        
        let request = Request(url: defaultURL).mutated {
            $0.memoryCacheOptions.readAllowed = false
        }

        waitLoadedImage(with: request)
        
        XCTAssertEqual(loader.createdTaskCount, 1)
        XCTAssertNotNil(self.cache[Request(url: defaultURL)])
    }
    
    // MARK: Completion Behavior
    
    func testCompletionDispatch() {
        _testCompletionDispatch()
    }
    
    func testCompletionDispatchWhenImageCached() {
        cache[Request(url: defaultURL)] = defaultImage
        _testCompletionDispatch()
    }
    
    func _testCompletionDispatch() {
        var isCompleted = false
        expect { fulfill in
            manager.loadImage(with: Request(url: defaultURL), token: nil) { _ in
                XCTAssert(Thread.isMainThread)
                isCompleted = true
                fulfill()
            }
        }
        XCTAssertFalse(isCompleted) // must be asynchronous
        wait()
        XCTAssertTrue(isCompleted)
    }
    
    // MARK: Cancellation
    
    func testCancellation() {
        // Manager itself doesn't make any gurantees regarding cancellation
        // (it does have preflight token.isCancelling checks though).
        // But it MUST pass the cancellation token to the underlying loader.
        
        let cts = CancellationTokenSource()
        
        loader.queue.isSuspended = true
        
        _ = expectNotification(MockImageLoader.DidStartTask, object: loader)
        manager.loadImage(with: Request(url: defaultURL), token: cts.token) { _ in
            XCTFail()
        }
        wait()
        
        _ = expectNotification(MockImageLoader.DidCancelTask, object: loader)
        cts.cancel()
        wait()
    }
    
    // MARK: Misc
    
    func testThreadSafety() {
        runThreadSafetyTests(for: manager)
    }
    
    // MARK: Helpers
    
    func waitLoadedImage(with request: Nuke.Request) {
        expect { fulfill in
            manager.loadImage(with: request, token: nil) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }
        wait()
    }
}
