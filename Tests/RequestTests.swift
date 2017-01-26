// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class RequestSemanticsTests: XCTestCase {
    func testThatStructSemanticsArePreserved() {
        let url1 =  URL(string: "http://test.com/1.png")!
        let url2 = URL(string: "http://test.com/2.png")!
        
        var request = Request(url: url1)
        XCTAssertEqual(url1, request.urlRequest.url)
        
        var copy = request
        copy.urlRequest = URLRequest(url: url2)
        
        XCTAssertEqual(url2, copy.urlRequest.url)
        XCTAssertEqual(url1, request.urlRequest.url)
    }
}

class RequestCacheKeyTests: XCTestCase {
    func testDefaults() {
        let request = Request(url: defaultURL)
        XCTAssertNil(request.cacheKey)
        XCTAssertNotNil(Request.cacheKey(for: request))
        XCTAssertTrue(Request.cacheKey(for: request) == Request.cacheKey(for: request))
    }
    
    func testThatRequestsWithTheSameURLsAreEquivalent() {
        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertTrue(Request.cacheKey(for: request1) == Request.cacheKey(for: request2))
    }
    
    func testThatRequestsWithDefaultURLRequestAndURLAreEquivalent() {
        let request1 = Request(url: defaultURL)
        let request2 = Request(urlRequest: URLRequest(url: defaultURL))
        XCTAssertTrue(Request.cacheKey(for: request1) == Request.cacheKey(for: request2))
    }
    
    func testThatRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = Request(url: URL(string: "http://test.com/1.png")!)
        let request2 = Request(url: URL(string: "http://test.com/2.png")!)
        XCTAssertFalse(Request.cacheKey(for: request1) == Request.cacheKey(for: request2))
    }
    
    func testThatRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "1"))
        let request2 = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "1"))
        XCTAssertTrue(MockImageProcessor(ID: "1") == MockImageProcessor(ID: "1"))
        XCTAssertTrue(Request.cacheKey(for: request1) == Request.cacheKey(for: request2))
    }
    
    func testThatRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "1"))
        let request2 = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "2"))
        XCTAssertFalse(MockImageProcessor(ID: "1") == MockImageProcessor(ID: "2"))
        XCTAssertFalse(Request.cacheKey(for: request1) == Request.cacheKey(for: request2))
    }
    
    func testThatURLRequestParametersAreIgnored() {
        let request1 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertTrue(Request.cacheKey(for: request1) == Request.cacheKey(for: request2))
    }
}

class RequestLoadKeyTests: XCTestCase {
    func testDefaults() {
        let request = Request(url: defaultURL)
        XCTAssertNil(request.loadKey)
        XCTAssertNotNil(Request.loadKey(for: request))
        XCTAssertTrue(Request.loadKey(for: request) == Request.loadKey(for: request))
    }
    
    func testThatRequestsWithTheSameURLsAreEquivalent() {
        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertTrue(Request.loadKey(for: request1) == Request.loadKey(for: request2))
    }
    
    func testThatRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = Request(url: URL(string: "http://test.com/1.png")!)
        let request2 = Request(url: URL(string: "http://test.com/2.png")!)
        XCTAssertFalse(Request.loadKey(for: request1) == Request.loadKey(for: request2))
    }
    
    func testThatRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "1"))
        let request2 = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "1"))
        XCTAssertTrue(MockImageProcessor(ID: "1") == MockImageProcessor(ID: "1"))
        XCTAssertTrue(Request.loadKey(for: request1) == Request.loadKey(for: request2))
    }
    
    func testThatRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "1"))
        let request2 = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "2"))
        XCTAssertFalse(MockImageProcessor(ID: "1") == MockImageProcessor(ID: "2"))
        XCTAssertFalse(Request.loadKey(for: request1) == Request.loadKey(for: request2))
    }
    
    func testThatRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let request1 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertFalse(Request.loadKey(for: request1) == Request.loadKey(for: request2))
    }
}
