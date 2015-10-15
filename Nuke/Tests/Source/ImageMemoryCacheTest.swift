//
//  ImageMemoryCacheTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/15/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import XCTest
import Nuke

class ImageMemoryCacheTest: XCTestCase {
    var manager: ImageManager!
    var mockMemoryCache: MockImageMemoryCache!
    var mockSessionManager: MockImageDataLoader!
    
    override func setUp() {
        super.setUp()

        self.mockMemoryCache = MockImageMemoryCache()
        self.mockSessionManager = MockImageDataLoader()
        self.manager = ImageManager(configuration: ImageManagerConfiguration(dataLoader: self.mockSessionManager, cache: self.mockMemoryCache))
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatMemoryCacheWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.cachedResponseForRequest(request))

        self.expect { fulfill in
            self.manager.taskWithRequest(request) {
                switch $0 {
                case .Success(_, let info):
                    XCTAssertFalse(info.fastResponse)
                default: XCTFail()
                }
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        XCTAssertNotNil(self.manager.cachedResponseForRequest(request))
        
        self.mockSessionManager.enabled = false
        
        var isCompletionCalled = false
        self.manager.taskWithRequest(request) {
            switch $0 {
            case .Success(_, let info):
                XCTAssertTrue(info.fastResponse)
            default: XCTFail()
            }
            // Comletion block should be called synchronously on the main thread
            isCompletionCalled = true
        }.resume()
        XCTAssertTrue(isCompletionCalled, "")
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.cachedResponseForRequest(request))
        
        self.manager.storeResponse(ImageCachedResponse(image: Image(), userInfo: "info"), forRequest: request)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        let response = self.manager.cachedResponseForRequest(request)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.userInfo as? String, "info")
        
        var isCompletionCalled = false
        self.manager.taskWithRequest(request) {
            switch $0 {
            case .Success(_, let info):
                XCTAssertTrue(info.fastResponse)
            default: XCTFail()
            }
            // Comletion block should be called synchronously on the main thread
            isCompletionCalled = true
        }.resume()
        XCTAssertTrue(isCompletionCalled, "")
    }
    
    func testThatImageManagerHonorsURLRequestCachePolicy() {
        self.manager.storeResponse(ImageCachedResponse(image: Image(), userInfo: "info"), forRequest: ImageRequest(URL: defaultURL))
        
        let request1 = ImageRequest(URLRequest: NSURLRequest(URL: defaultURL, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 100))
        let request2 = ImageRequest(URLRequest: NSURLRequest(URL: defaultURL, cachePolicy: .ReloadIgnoringLocalCacheData, timeoutInterval: 100))
        
        // cachedResponseForRequest should ignore NSURLRequestCachePolicy
        XCTAssertNotNil(self.manager.cachedResponseForRequest(request1))
        XCTAssertNotNil(self.manager.cachedResponseForRequest(request2))
        
        var isCompletionCalled = false
        self.manager.taskWithRequest(request1) {
            switch $0 {
            case .Success(_, let info):
                XCTAssertTrue(info.fastResponse)
            default: XCTFail()
            }
            // Comletion block should be called synchronously on the main thread
            isCompletionCalled = true
            }.resume()
        XCTAssertTrue(isCompletionCalled, "")
        
        self.expect { fulfill in
            self.manager.taskWithRequest(request2) {
                switch $0 {
                case .Success(_, let info):
                    XCTAssertFalse(info.fastResponse)
                default: XCTFail()
                }
                fulfill()
                }.resume()
        }
        self.wait()
    }
}
