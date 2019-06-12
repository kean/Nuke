// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageRequestTests: XCTestCase {
    // MARK: - CoW

    func testStructSemanticsArePreserved() {
        // Given
        let url1 =  URL(string: "http://test.com/1.png")!
        let url2 = URL(string: "http://test.com/2.png")!
        let request = ImageRequest(url: url1)

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
        request.options.memoryCacheOptions.isReadAllowed = false
        request.options.loadKey = "1"
        request.options.cacheKey = "2"
        request.options.userInfo = "3"
        request.options.filteredURL = "4"
        request.processors = [MockImageProcessor(id: "4")]
        request.priority = .high

        // When
        var copy = request
        // Requst makes a copy at this point under the hood.
        copy.urlRequest = URLRequest(url: URL(string: "http://test.com/2.png")!)

        // Then
        XCTAssertEqual(copy.options.memoryCacheOptions.isReadAllowed, false)
        XCTAssertEqual(copy.options.loadKey, "1")
        XCTAssertEqual(copy.options.cacheKey, "2")
        XCTAssertEqual(copy.options.userInfo as? String, "3")
        XCTAssertEqual(copy.options.filteredURL, "4")
        XCTAssertEqual((copy.processors.first as? MockImageProcessor)?.identifier, "4")
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
        let request1 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }
    
    func testRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        XCTAssertNotEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testURLRequestParametersAreIgnored() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testSettingDefaultProcessorManually() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url, processors: request1.processors)
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestWithDefaultAndCustomKeysAreNotEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url, options: .init(cacheKey: "2"))
        XCTAssertNotEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    // MARK: Custom Cache Key

    func testRequestsWithSameCustomKeysAreEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.options.cacheKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.options.cacheKey = "1"
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithSameCustomKeysButDifferentURLsAreEquivalent() {
        var request1 = ImageRequest(url: URL(string: "https://example.com/photo1.jpg")!)
        request1.options.cacheKey = "1"
        var request2 = ImageRequest(url: URL(string: "https://example.com/photo2.jpg")!)
        request2.options.cacheKey = "1"
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithDifferentCustomKeysAreNotEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.options.cacheKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.options.cacheKey = "2"
        XCTAssertNotEqual(CacheKey(request: request1), CacheKey(request: request2))
    }
}

class ImageRequestLoadKeyTests: XCTestCase {
    func testDefaults() {
        let request = ImageRequest(url: Test.url)
        AssertHashableEqual(request.makeLoadKeyForOriginalImage(), request.makeLoadKeyForOriginalImage())
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url)
        AssertHashableEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        AssertHashableEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testRequestsWithDifferentProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        AssertHashableEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertNotEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testMockImageProcessorCorrectlyImplementsIdentifiers() {
        XCTAssertEqual(MockImageProcessor(id: "1").identifier, MockImageProcessor(id: "1").identifier)
        XCTAssertEqual(MockImageProcessor(id: "1").hashableIdentifier, MockImageProcessor(id: "1").hashableIdentifier)

        XCTAssertNotEqual(MockImageProcessor(id: "1").identifier, MockImageProcessor(id: "2").identifier)
        XCTAssertNotEqual(MockImageProcessor(id: "1").hashableIdentifier, MockImageProcessor(id: "2").hashableIdentifier)
    }

    // MARK: - Custom Load Key

    func testRequestsWithSameCustomKeysAreEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.options.loadKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.options.loadKey = "1"
        AssertHashableEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testRequestsWithSameCustomKeysButDifferentURLsAreEquivalent() {
        var request1 = ImageRequest(url: URL(string: "https://example.com/photo1.jpg")!)
        request1.options.loadKey = "1"
        var request2 = ImageRequest(url: URL(string: "https://example.com/photo2.jpg")!)
        request2.options.loadKey = "1"
        AssertHashableEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testRequestsWithDifferentCustomKeysAreNotEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.options.loadKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.options.loadKey = "2"
        XCTAssertNotEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }
}

class ImageRequestFilteredURLTests: XCTestCase {
    func testThatCacheKeyUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        XCTAssertNotEqual(lhs.makeCacheKeyForProcessedImage(), rhs.makeCacheKeyForProcessedImage())
    }

    func testThatCacheKeyUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, options: .init(filteredURL: Test.url.absoluteString))
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), options: .init(filteredURL: Test.url.absoluteString))
        AssertHashableEqual(lhs.makeCacheKeyForProcessedImage(), rhs.makeCacheKeyForProcessedImage())
    }

    func testThatCacheKeyForProcessedImageDataUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        XCTAssertNotEqual(lhs.makeCacheKeyForProcessedImageData(), rhs.makeCacheKeyForProcessedImageData())
    }

    func testThatCacheKeyForProcessedImageDataUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, options: .init(filteredURL: Test.url.absoluteString))
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), options: .init(filteredURL: Test.url.absoluteString))
        AssertHashableEqual(lhs.makeCacheKeyForProcessedImageData(), rhs.makeCacheKeyForProcessedImageData())
    }

    func testThatCacheKeyForOriginalImageDataUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        XCTAssertNotEqual(lhs.makeCacheKeyForOriginalImageData(), rhs.makeCacheKeyForOriginalImageData())
    }

    func testThatCacheKeyForOriginalImageDataUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, options: .init(filteredURL: Test.url.absoluteString))
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), options: .init(filteredURL: Test.url.absoluteString))
        AssertHashableEqual(lhs.makeCacheKeyForOriginalImageData(), rhs.makeCacheKeyForOriginalImageData())
    }

    func testThatLoadKeyForProcessedImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url, options: .init(filteredURL: Test.url.absoluteString))
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), options: .init(filteredURL: Test.url.absoluteString))
        XCTAssertNotEqual(lhs.makeLoadKeyForProcessedImage(), rhs.makeLoadKeyForProcessedImage())
    }

    func testThatLoadKeyForOriginalImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url, options: .init(filteredURL: Test.url.absoluteString))
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), options: .init(filteredURL: Test.url.absoluteString))
        XCTAssertNotEqual(lhs.makeLoadKeyForOriginalImage(), rhs.makeLoadKeyForOriginalImage())
    }
}

private typealias CacheKey = ImageRequest.CacheKey

private func AssertHashableEqual<T: Hashable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(lhs.hashValue, rhs.hashValue, file: file, line: line)
    XCTAssertEqual(lhs, rhs, file: file, line: line)
}
