// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

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

    func testCopyOnWrite() {
        var request = Request(url: URL(string: "http://test.com/1.png")!)
        request.memoryCacheOptions.readAllowed = false
        request.loadKey = "1"
        request.cacheKey = "2"
        request.userInfo = "3"
        request.progress = { (_,_) in }
        request.processor = AnyProcessor(MockImageProcessor(id: "4"))

        var copy = request
        // Requsts makes a copy at this point.
        copy.urlRequest = URLRequest(url: URL(string: "http://test.com/2.png")!)

        XCTAssertEqual(copy.memoryCacheOptions.readAllowed, false)
        XCTAssertEqual(copy.loadKey, "1")
        XCTAssertEqual(copy.cacheKey, "2")
        XCTAssertEqual(copy.userInfo as? String, "3")
        XCTAssertNotNil(copy.progress)
        XCTAssertEqual(copy.processor, AnyProcessor(MockImageProcessor(id: "4")))
    }
}

class RequestCacheKeyTests: XCTestCase {
    func testDefaults() {
        let request = Request(url: defaultURL)
        XCTAssertEqual(request.cacheKey, request.cacheKey) // equal to itself
    }
    
    func testThatRequestsWithTheSameURLsAreEquivalent() {
        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertEqual(request1.cacheKey, request2.cacheKey)
    }
    
    func testThatRequestsWithDefaultURLRequestAndURLAreEquivalent() {
        let request1 = Request(url: defaultURL)
        let request2 = Request(urlRequest: URLRequest(url: defaultURL))
        XCTAssertEqual(request1.cacheKey, request2.cacheKey)
    }
    
    func testThatRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = Request(url: URL(string: "http://test.com/1.png")!)
        let request2 = Request(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(request1.cacheKey, request2.cacheKey)
    }
    
    func testThatRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = Request(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        let request2 = Request(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        XCTAssertEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "1"))
        XCTAssertEqual(request1.cacheKey, request2.cacheKey)
    }
    
    func testThatRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = Request(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        let request2 = Request(url: defaultURL).processed(with: MockImageProcessor(id: "2"))
        XCTAssertNotEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "2"))
        XCTAssertNotEqual(request1.cacheKey, request2.cacheKey)
    }
    
    func testThatURLRequestParametersAreIgnored() {
        let request1 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertEqual(request1.cacheKey, request2.cacheKey)
    }
}

class RequestLoadKeyTests: XCTestCase {
    func testDefaults() {
        let request = Request(url: defaultURL)
        XCTAssertEqual(request.loadKey, request.loadKey)
    }
    
    func testThatRequestsWithTheSameURLsAreEquivalent() {
        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertEqual(request1.loadKey, request2.loadKey)
    }
    
    func testThatRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = Request(url: URL(string: "http://test.com/1.png")!)
        let request2 = Request(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(request1.loadKey, request2.loadKey)
    }
    
    func testThatRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = Request(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        let request2 = Request(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        XCTAssertEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "1"))
        XCTAssertEqual(request1.loadKey, request2.loadKey)
    }
    
    func testThatRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = Request(url: defaultURL).processed(with: MockImageProcessor(id: "1"))
        let request2 = Request(url: defaultURL).processed(with: MockImageProcessor(id: "2"))
        XCTAssertNotEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "2"))
        XCTAssertNotEqual(request1.loadKey, request2.loadKey)
    }
    
    func testThatRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let request1 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertNotEqual(request1.loadKey, request2.loadKey)
    }
}
