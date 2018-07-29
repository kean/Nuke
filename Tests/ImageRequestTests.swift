// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageRequestTests: XCTestCase {
    // MARK: - CoW

    func testStructSemanticsArePreserved() {
        // Given
        let url1 =  URL(string: "http://test.com/1.png")!
        let url2 = URL(string: "http://test.com/2.png")!
        var request = ImageRequest(url: url1)

        // When
        var copy = request
        copy.urlRequest = URLRequest(url: url2)

        // Then
        XCTAssertEqual(url2, copy.urlRequest.url)
        XCTAssertEqual(url1, request.urlRequest.url)
    }

    func testCopyOnWrite() {
        // Given
        var request = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        request.memoryCacheOptions.isReadAllowed = false
        request.loadKey = "1"
        request.cacheKey = "2"
        request.userInfo = "3"
        request.processor = AnyImageProcessor(MockImageProcessor(id: "4"))
        request.priority = .high

        // When
        var copy = request
        // Requst makes a copy at this point under the hood.
        copy.urlRequest = URLRequest(url: URL(string: "http://test.com/2.png")!)

        // Then
        XCTAssertEqual(copy.memoryCacheOptions.isReadAllowed, false)
        XCTAssertEqual(copy.loadKey, "1")
        XCTAssertEqual(copy.cacheKey, "2")
        XCTAssertEqual(copy.userInfo as? String, "3")
        XCTAssertEqual(copy.processor, AnyImageProcessor(MockImageProcessor(id: "4")))
        XCTAssertEqual(copy.priority, .high)
    }

    // MARK: - Misc

    // Just to make sure that comparison works as expected.
    func testPriorityComparison() {
        typealias Priority = ImageRequest.Priority
        XCTAssertTrue(Priority.veryLow < Priority.veryHigh)
        XCTAssertTrue(Priority.low < Priority.normal)
        XCTAssertTrue(Priority.normal == Priority.normal)
    }
}

class ImageRequestCacheKeyTests: XCTestCase {
    func testDefaults() {
        let request = Test.request
        AssertHashableEqual(CacheKey(request: request), CacheKey(request: request)) // equal to itself
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url)
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }
    
    func testRequestsWithDefaultURLRequestAndURLAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url))
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "1"))
        let request2 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "1"))
        XCTAssertEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "1"))
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }
    
    func testRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "1"))
        let request2 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "2"))
        XCTAssertNotEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "2"))
        XCTAssertNotEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testURLRequestParametersAreIgnored() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testSettingDefaultProcessorManually() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url).mutated {
            $0.processor = request1.processor
        }
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    // MARK: Custom Cache Key

    func testRequestsWithSameCustomKeysAreEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.cacheKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.cacheKey = "1"
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithSameCustomKeysButDifferentURLsAreEquivalent() {
        var request1 = ImageRequest(url: URL(string: "https://example.com/photo1.jpg")!)
        request1.cacheKey = "1"
        var request2 = ImageRequest(url: URL(string: "https://example.com/photo2.jpg")!)
        request2.cacheKey = "1"
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithDifferentCustomKeysAreNotEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.cacheKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.cacheKey = "2"
        XCTAssertNotEqual(CacheKey(request: request1), CacheKey(request: request2))
    }
}

class ImageRequestLoadKeyTests: XCTestCase {
    func testDefaults() {
        let request = ImageRequest(url: Test.url)
        AssertHashableEqual(LoadKey(request: request), LoadKey(request: request))
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url)
        AssertHashableEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "1"))
        let request2 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "1"))
        XCTAssertEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "1"))
        AssertHashableEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestsWithDifferentProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "1"))
        let request2 = ImageRequest(url: Test.url).processed(with: MockImageProcessor(id: "2"))
        XCTAssertNotEqual(MockImageProcessor(id: "1"), MockImageProcessor(id: "2"))
        AssertHashableEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertNotEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    // MARK: - Custom Load Key

    func testRequestsWithSameCustomKeysAreEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.loadKey = "1"
        AssertHashableEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestsWithSameCustomKeysButDifferentURLsAreEquivalent() {
        var request1 = ImageRequest(url: URL(string: "https://example.com/photo1.jpg")!)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: URL(string: "https://example.com/photo2.jpg")!)
        request2.loadKey = "1"
        AssertHashableEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestsWithDifferentCustomKeysAreNotEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.loadKey = "2"
        XCTAssertNotEqual(LoadKey(request: request1), LoadKey(request: request2))
    }
}

private typealias CacheKey = ImageRequest.CacheKey
private typealias LoadKey = ImageRequest.LoadKey

private func AssertHashableEqual<T: Hashable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(lhs.hashValue, rhs.hashValue)
    XCTAssertEqual(lhs, rhs)
}
