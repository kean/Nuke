// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageRequestTests: XCTestCase {
    // The compiler picks up the new version
    func testInit() {
        _ = ImageRequest(url: Test.url)
        _ = ImageRequest(url: Test.url, processors: [])
        _ = ImageRequest(url: Test.url, processors: [])
        _ = ImageRequest(url: Test.url, priority: .high)
        _ = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
    }

    func testExpressibleByStringLiteral() {
        let _: ImageRequest = "https://example.com/image.jpeg"
    }

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
        // Request makes a copy at this point under the hood.
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
        AssertHashableEqual(MemoryCacheKey(request), MemoryCacheKey(request)) // equal to itself
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url)
        AssertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testRequestsWithDefaultURLRequestAndURLAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(urlRequest: URLRequest(url: Test.url))
        AssertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let lhs = ImageRequest(url: URL(string: "http://test.com/1.png"))
        let rhs = ImageRequest(url: URL(string: "http://test.com/2.png"))
        XCTAssertNotEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testRequestsWithTheSameProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        AssertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testRequestsWithDifferentProcessorsAreNotEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        XCTAssertNotEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testURLRequestParametersAreIgnored() {
        let lhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let rhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        AssertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testSettingDefaultProcessorManually() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url, processors: lhs.processors)
        AssertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }
}

class ImageRequestLoadKeyTests: XCTestCase {
    func testDefaults() {
        let request = ImageRequest(url: Test.url)
        AssertHashableEqual(TaskFetchOriginalDataKey(request), TaskFetchOriginalDataKey(request))
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url)
        AssertHashableEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let lhs = ImageRequest(url: URL(string: "http://test.com/1.png"))
        let rhs = ImageRequest(url: URL(string: "http://test.com/2.png"))
        XCTAssertNotEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    func testRequestsWithTheSameProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        AssertHashableEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    func testRequestsWithDifferentProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        AssertHashableEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    func testRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let lhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let rhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertNotEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
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
        XCTAssertNotEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testThatCacheKeyUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        AssertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testThatCacheKeyForProcessedImageDataUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        XCTAssertNotEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testThatCacheKeyForProcessedImageDataUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        AssertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    func testThatLoadKeyForProcessedImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        XCTAssertNotEqual(TaskLoadImageKey(lhs), TaskLoadImageKey(rhs))
    }

    func testThatLoadKeyForOriginalImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        XCTAssertNotEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }
}

private func AssertHashableEqual<T: Hashable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(lhs.hashValue, rhs.hashValue, file: file, line: line)
    XCTAssertEqual(lhs, rhs, file: file, line: line)
}
