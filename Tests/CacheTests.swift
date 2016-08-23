// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class MockCacheTests: XCTestCase {
    var mockCache: MockCache!
    var mockSessionManager: MockDataLoader!
    var loader: Loader!
    
    override func setUp() {
        super.setUp()

        mockCache = MockCache()
        mockSessionManager = MockDataLoader()
        loader = Loader(loader: mockSessionManager, decoder: DataDecoder(), cache: mockCache)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatCacheWorks() {
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])

        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
        
        XCTAssertEqual(mockCache.images.count, 1)
        XCTAssertNotNil(mockCache[request])
        
        mockSessionManager.queue.isSuspended = true
        
        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
        
        mockCache[request] = Image()
        
        XCTAssertEqual(mockCache.images.count, 1)
        let image = mockCache[request]
        XCTAssertNotNil(image)
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
        
        mockCache[request] = Image()
        
        XCTAssertEqual(mockCache.images.count, 1)
        let image = mockCache[request]
        XCTAssertNotNil(image)
        
        mockCache[request] = nil
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
    }
    
    func testThatCacheStorageCanBeDisabled() {
        var request = Request(url: defaultURL)
        XCTAssertTrue(request.memoryCacheOptions.writeAllowed)
        request.memoryCacheOptions.writeAllowed = false // Test default value
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
        
        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache[request])
    }
}

class CacheTests: XCTestCase {
    var cache: Nuke.Cache!
    var mockSessionManager: MockDataLoader!
    var loader: Loader!
    
    override func setUp() {
        super.setUp()
        
        cache = Cache()
        mockSessionManager = MockDataLoader()
        loader = Loader(loader: mockSessionManager, decoder: DataDecoder(), cache: cache)
    }
    
    func testThatImagesAreStoredInCache() {
        let request = Request(url: defaultURL)
        
        XCTAssertNil(cache[request])

        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
        
        XCTAssertNotNil(cache[request])
        
        mockSessionManager.queue.isSuspended = true
        
        expect { fulfill in
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()
    }
    
    #if os(iOS) || os(tvOS)
    func testThatImageAreRemovedOnMemoryWarnings() {
        let request = Request(url: defaultURL)
        cache[request] = Image()
        XCTAssertNotNil(cache[request])
        
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        
        XCTAssertNil(cache[request])
    }
    #endif
}
