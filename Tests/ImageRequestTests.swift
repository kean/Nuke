// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageRequestTests: XCTestCase {
    // MARK: - CoW

    func testThatStructSemanticsArePreserved() {
        let url1 =  URL(string: "http://test.com/1.png")!
        let url2 = URL(string: "http://test.com/2.png")!
        
        var request = ImageRequest(url: url1)
        XCTAssertEqual(url1, request.urlRequest.url)

        var copy = request
        copy.urlRequest = URLRequest(url: url2)
        
        XCTAssertEqual(url2, copy.urlRequest.url)
        XCTAssertEqual(url1, request.urlRequest.url)
    }

    func testCopyOnWrite() {
        var request = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        request.memoryCacheOptions.readAllowed = false
        request.loadKey = "1"
        request.cacheKey = "2"
        request.userInfo = "3"
        request.processor = AnyImageProcessor(MockImageProcessor(id: "4"))
        request.priority = .high

        var copy = request
        // Requsts makes a copy at this point.
        copy.urlRequest = URLRequest(url: URL(string: "http://test.com/2.png")!)

        XCTAssertEqual(copy.memoryCacheOptions.readAllowed, false)
        XCTAssertEqual(copy.loadKey, "1")
        XCTAssertEqual(copy.cacheKey, "2")
        XCTAssertEqual(copy.userInfo as? String, "3")
        XCTAssertEqual(copy.processor, AnyImageProcessor(MockImageProcessor(id: "4")))
        XCTAssertEqual(copy.priority, .high)
    }

    // MARK: - Misc

    // Just to make sure that comparison works as expected.
    func testPriorityComparison() {
        XCTAssertTrue(ImageRequest.Priority.veryLow < ImageRequest.Priority.veryHigh)
        XCTAssertTrue(ImageRequest.Priority.low < ImageRequest.Priority.normal)
        XCTAssertTrue(ImageRequest.Priority.normal == ImageRequest.Priority.normal)
    }
}

class ImageRequestCacheKeyTests: XCTestCase {
    func testDefaults() {
        let request = ImageRequest(url: defaultURL)
        XCTAssertEqual(ImageRequest.CacheKey(request: request), ImageRequest.CacheKey(request: request)) // equal to itself
    }
    
    func testThatRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)
        XCTAssertEqual(ImageRequest.CacheKey(request: request1), ImageRequest.CacheKey(request: request2))
    }
    
    func testThatRequestsWithDefaultURLRequestAndURLAreEquivalent() {
        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(urlRequest: URLRequest(url: defaultURL))
        XCTAssertEqual(ImageRequest.CacheKey(request: request1), ImageRequest.CacheKey(request: request2))
    }
    
    func testThatRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(ImageRequest.CacheKey(request: request1), ImageRequest.CacheKey(request: request2))
    }
    
    func testThatRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        let request2 = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        XCTAssertEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "1"))
        XCTAssertEqual(ImageRequest.CacheKey(request: request1), ImageRequest.CacheKey(request: request2))
    }
    
    func testThatRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        let request2 = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "2"))
        XCTAssertNotEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "2"))
        XCTAssertNotEqual(ImageRequest.CacheKey(request: request1), ImageRequest.CacheKey(request: request2))
    }
    
    func testThatURLRequestParametersAreIgnored() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertEqual(ImageRequest.CacheKey(request: request1), ImageRequest.CacheKey(request: request2))
    }
}

class ImageRequestLoadKeyTests: XCTestCase {
    func testDefaults() {
        let request = ImageRequest(url: defaultURL)
        XCTAssertEqual(ImageRequest.LoadKey(request: request), ImageRequest.LoadKey(request: request))
    }
    
    func testThatRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)
        XCTAssertEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))
    }
    
    func testThatRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))
    }
    
    func testThatRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        let request2 = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        XCTAssertEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "1"))
        XCTAssertEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))
    }
    
    func testThatRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        let request2 = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "2"))
        XCTAssertNotEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "2"))
        XCTAssertNotEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))
    }
    
    func testThatRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertNotEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))
    }
}
