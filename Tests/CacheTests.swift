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
        loader = Loader(loader: mockSessionManager, decoder: DataDecoder())
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatCacheWorks() {
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache.image(for: request))

        expect { fulfill in
            _ = loader.loadImage(with: request) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }
        wait()
        
        XCTAssertEqual(mockCache.images.count, 1)
        XCTAssertNotNil(mockCache.image(for: request))
        
        mockSessionManager.queue.isSuspended = true
        
        expect { fulfill in
            _ = loader.loadImage(with: request) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }
        wait()
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache.image(for: request))
        
        mockCache.setImage(Image(), for: request)
        
        XCTAssertEqual(mockCache.images.count, 1)
        let image = mockCache.image(for: request)
        XCTAssertNotNil(image)
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache.image(for: request))
        
        mockCache.setImage(Image(), for: request)
        
        XCTAssertEqual(mockCache.images.count, 1)
        let response = mockCache.image(for: request)
        XCTAssertNotNil(response)
        
        mockCache.removeImage(for: request)
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache.image(for: request))
    }
    
    func testThatCacheStorageCanBeDisabled() {
        let request = Request(url: defaultURL)
        XCTAssertTrue(options.memoryCacheStorageAllowed)
        options.memoryCacheStorageAllowed = false // Test default value
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache.image(for: request))
        
        expect { fulfill in
            _ = loader.loadImage(with: request) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }
        wait()
        
        XCTAssertEqual(mockCache.images.count, 0)
        XCTAssertNil(mockCache.image(for: request))
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
        loader = Loader(loader: mockSessionManager, decoder: DataDecoder(), memoryCache: cache)
    }
    
    func testThatImagesAreStoredInCache() {
        let request = Request(url: defaultURL)
        
        XCTAssertNil(cache.image(for: request))

        expect { fulfill in
            _ = loader.loadImage(with: request) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }
        wait()
        
        XCTAssertNotNil(cache.image(for: request))
        
        mockSessionManager.queue.isSuspended = true
        
        expect { fulfill in
            _ = loader.loadImage(with: request) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }
        wait()
    }
    
    #if os(iOS) || os(tvOS)
    func testThatImageAreRemovedOnMemoryWarnings() {
        let request = Request(url: defaultURL)
        cache.setImage(Image(), for: request)
        XCTAssertNotNil(cache.image(for: request))
        
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        
        XCTAssertNil(cache.image(for: request))
    }
    #endif
}
