//
//  ImageMemoryCacheTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/15/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
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
        XCTAssertNil(self.manager.responseForRequest(request))

        self.expect { fulfill in
            self.manager.taskWith(request) {
                switch $0 {
                case .Success(_, let info):
                    XCTAssertFalse(info.isFastResponse)
                default: XCTFail()
                }
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        XCTAssertNotNil(self.manager.responseForRequest(request))
        
        self.mockSessionManager.enabled = false
        
        var isCompletionCalled = false
        self.manager.taskWith(request) {
            switch $0 {
            case .Success(_, let info):
                XCTAssertTrue(info.isFastResponse)
            default: XCTFail()
            }
            // Completion closure should be called synchronously on the main thread
            isCompletionCalled = true
        }.resume()
        XCTAssertTrue(isCompletionCalled, "")
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
        
        self.manager.setResponse(ImageCachedResponse(image: Image(), userInfo: "info"), forRequest: request)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        let response = self.manager.responseForRequest(request)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.userInfo as? String, "info")
        
        var isCompletionCalled = false
        self.manager.taskWith(request) {
            switch $0 {
            case .Success(_, let info):
                XCTAssertTrue(info.isFastResponse)
            default: XCTFail()
            }
            // Completion closure should be called synchronously on the main thread
            isCompletionCalled = true
        }.resume()
        XCTAssertTrue(isCompletionCalled, "")
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
        
        self.manager.setResponse(ImageCachedResponse(image: Image(), userInfo: "info"), forRequest: request)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        let response = self.manager.responseForRequest(request)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.userInfo as? String, "info")
        
        self.manager.removeResponseForRequest(request)
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
    }
    
    func testThatRequestMemoryCachePolicyIsHonored() {
        self.manager.setResponse(ImageCachedResponse(image: Image(), userInfo: "info"), forRequest: ImageRequest(URL: defaultURL))
        
        let request1 = ImageRequest(URL: defaultURL)
        var request2 = ImageRequest(URL: defaultURL)
        request2.memoryCachePolicy = .ReloadIgnoringCachedImage
        
        // responseForRequest should ignore ImageRequestMemoryCachePolicy
        XCTAssertNotNil(self.manager.responseForRequest(request1))
        XCTAssertNotNil(self.manager.responseForRequest(request2))
        
        var isCompletionCalled = false
        self.manager.taskWith(request1) {
            switch $0 {
            case .Success(_, let info):
                XCTAssertTrue(info.isFastResponse)
            default: XCTFail()
            }
            // Completion closure should be called synchronously on the main thread
            isCompletionCalled = true
        }.resume()
        XCTAssertTrue(isCompletionCalled, "")
        
        self.expect { fulfill in
            self.manager.taskWith(request2) {
                switch $0 {
                case .Success(_, let info):
                    XCTAssertFalse(info.isFastResponse)
                default: XCTFail()
                }
                fulfill()
            }.resume()
        }
        self.wait()
    }
    
    func testThatMemoryCacheStorageCanBeDisabled() {
        var request = ImageRequest(URL: defaultURL)
        XCTAssertTrue(request.memoryCacheStorageAllowed)
        request.memoryCacheStorageAllowed = false // Test default value
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
        
        self.expect { fulfill in
            self.manager.taskWith(request) {
                switch $0 {
                case .Success(_, let info):
                    XCTAssertFalse(info.isFastResponse)
                default: XCTFail()
                }
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
    }

    func testThatAllCachedImageAreRemoved() {
        let request = ImageRequest(URL: defaultURL)
        self.manager.setResponse(ImageCachedResponse(image: Image(), userInfo: "info"), forRequest: request)

        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)

        self.manager.removeAllCachedImages()

        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
    }
}
