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
            self.manager.taskWithRequest(request) { (response) -> Void in
                XCTAssertNotNil(response.image, "")
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        XCTAssertNotNil(self.manager.cachedResponseForRequest(request))
        
        self.mockSessionManager.enabled = false
        
        var isCompletionCalled = false
        self.manager.taskWithRequest(request) { (response) -> Void in
            XCTAssertNotNil(response.image, "")
            // Comletion block should be called on the main thread
            isCompletionCalled = true
        }.resume()
        XCTAssertTrue(isCompletionCalled, "")
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.cachedResponseForRequest(request))
        
        self.manager.storeResponse(ImageCachedResponse(image: UIImage(), userInfo: "info"), forRequest: request)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        let response = self.manager.cachedResponseForRequest(request)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.userInfo as? String, "info")
    }
}
