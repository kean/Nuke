// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageRequestTests: XCTestCase {
    // MARK: - CoW

    func testCopyOnWrite() {
        // GIVEN
        var request = ImageRequest(url: URL(string: "http://test.com/1.png"))
        request.options.insert(.disableMemoryCacheReads)
        request.userInfo["key"] = "3"
        request.processors = [MockImageProcessor(id: "4")]
        request.priority = .high

        // WHEN
        var copy = request
        // Requst makes a copy at this point under the hood.
        copy.priority = .low

        // THEN
        XCTAssertEqual(copy.options.contains(.disableMemoryCacheReads), true)
        XCTAssertEqual(copy.userInfo["key"] as? String, "3")
        XCTAssertEqual((copy.processors.first as? MockImageProcessor)?.identifier, "4")
        XCTAssertEqual(request.priority, .high) // Original request no updated
        XCTAssertEqual(copy.priority, .low)
    }

    // MARK: - Misc

    // Just to make sure that comparison works as expected.
    func testPriorityComparison() {
        typealias Priority = ImageRequest.Priority
        XCTAssertTrue(Priority.veryLow < Priority.veryHigh)
        XCTAssertTrue(Priority.low < Priority.normal)
        XCTAssertTrue(Priority.normal == Priority.normal)
    }

    func testUserInfoKey() {
        // WHEN
        let request = ImageRequest(url: Test.url, userInfo: [.init("a"): 1])

        // THEN
        XCTAssertNotNil(request.userInfo["a"])
    }
}

class ImageRequestCacheKeyTests: XCTestCase {
    func testDefaults() {
        let request = Test.request
        AssertHashableEqual(CacheKey(request), CacheKey(request)) // equal to itself
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url)
        AssertHashableEqual(CacheKey(request1), CacheKey(request2))
    }
    
    func testRequestsWithDefaultURLRequestAndURLAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url))
        AssertHashableEqual(CacheKey(request1), CacheKey(request2))
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png"))
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png"))
        XCTAssertNotEqual(CacheKey(request1), CacheKey(request2))
    }

    func testRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        AssertHashableEqual(CacheKey(request1), CacheKey(request2))
    }
    
    func testRequestsWithDifferentProcessorsAreNotEquivalent() {
        let request1 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        XCTAssertNotEqual(CacheKey(request1), CacheKey(request2))
    }

    func testURLRequestParametersAreIgnored() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        AssertHashableEqual(CacheKey(request1), CacheKey(request2))
    }

    func testSettingDefaultProcessorManually() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url, processors: request1.processors)
        AssertHashableEqual(CacheKey(request1), CacheKey(request2))
    }
}

class ImageRequestLoadKeyTests: XCTestCase {
    func testDefaults() {
        let request = ImageRequest(url: Test.url)
        AssertHashableEqual(request.makeDataLoadKey(), request.makeDataLoadKey())
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url)
        AssertHashableEqual(request1.makeDataLoadKey(), request2.makeDataLoadKey())
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png"))
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png"))
        XCTAssertNotEqual(request1.makeDataLoadKey(), request2.makeDataLoadKey())
    }

    func testRequestsWithTheSameProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        AssertHashableEqual(request1.makeDataLoadKey(), request2.makeDataLoadKey())
    }

    func testRequestsWithDifferentProcessorsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        AssertHashableEqual(request1.makeDataLoadKey(), request2.makeDataLoadKey())
    }

    func testRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertNotEqual(request1.makeDataLoadKey(), request2.makeDataLoadKey())
    }

    func testMockImageProcessorCorrectlyImplementsIdentifiers() {
        XCTAssertEqual(MockImageProcessor(id: "1").identifier, MockImageProcessor(id: "1").identifier)
        XCTAssertEqual(MockImageProcessor(id: "1").hashableIdentifier, MockImageProcessor(id: "1").hashableIdentifier)

        XCTAssertNotEqual(MockImageProcessor(id: "1").identifier, MockImageProcessor(id: "2").identifier)
        XCTAssertNotEqual(MockImageProcessor(id: "1").hashableIdentifier, MockImageProcessor(id: "2").hashableIdentifier)
    }
}

class ImageRequestImageIdTests: XCTestCase {
    func testThatCacheKeyUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        XCTAssertNotEqual(lhs.makeImageCacheKey(), rhs.makeImageCacheKey())
    }

    func testThatCacheKeyUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        AssertHashableEqual(lhs.makeImageCacheKey(), rhs.makeImageCacheKey())
    }

    func testThatCacheKeyForProcessedImageDataUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        XCTAssertNotEqual(lhs.makeImageCacheKey(), rhs.makeImageCacheKey())
    }

    func testThatCacheKeyForProcessedImageDataUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        AssertHashableEqual(lhs.makeImageCacheKey(), rhs.makeImageCacheKey())
    }

    func testThatLoadKeyForProcessedImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        XCTAssertNotEqual(lhs.makeImageLoadKey(), rhs.makeImageLoadKey())
    }

    func testThatLoadKeyForOriginalImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        XCTAssertNotEqual(lhs.makeDataLoadKey(), rhs.makeDataLoadKey())
    }
}

private func AssertHashableEqual<T: Hashable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(lhs.hashValue, rhs.hashValue, file: file, line: line)
    XCTAssertEqual(lhs, rhs, file: file, line: line)
}
