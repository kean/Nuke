// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImageRequestTests {
    // The compiler picks up the new version
    @Test func testInit() {
        _ = ImageRequest(url: Test.url)
        _ = ImageRequest(url: Test.url, processors: [])
        _ = ImageRequest(url: Test.url, processors: [])
        _ = ImageRequest(url: Test.url, priority: .high)
        _ = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
    }

    @Test func expressibleByStringLiteral() {
        let _: ImageRequest = "https://example.com/image.jpeg"
    }

    // MARK: - CoW

    @Test func copyOnWrite() {
        // Given
        var request = ImageRequest(url: URL(string: "http://test.com/1.png"))
        request.options.insert(.disableMemoryCacheReads)
        request.userInfo["key"] = "3"
        request.processors = [MockImageProcessor(id: "4")]
        request.priority = .high

        // When
        var copy = request
        // Request makes a copy at this point under the hood.
        copy.priority = .low

        // Then
        #expect(copy.options.contains(.disableMemoryCacheReads) == true)
        #expect(copy.userInfo["key"] as? String == "3")
        #expect((copy.processors.first as? MockImageProcessor)?.identifier == "4")
        #expect(request.priority == .high) // Original request no updated // Original request no updated
        #expect(copy.priority == .low)
    }

    // MARK: - Misc

    // Just to make sure that comparison works as expected.
    @Test func priorityComparison() {
        typealias Priority = ImageRequest.Priority
        #expect(Priority.veryLow < Priority.veryHigh)
        #expect(Priority.low < Priority.normal)
        #expect(Priority.normal == Priority.normal)
    }

    @Test func userInfoKey() {
        // When
        let request = ImageRequest(url: Test.url, userInfo: [.init("a"): 1])

        // Then
        #expect(request.userInfo["a"] != nil)
    }
}

@Suite struct ImageRequestCacheKeyTests {
    @Test func defaults() {
        let request = Test.request
        expectHashableMatch(MemoryCacheKey(request), MemoryCacheKey(request)) // equal to itself
    }

    @Test func requestsWithTheSameURLsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url)
        expectHashableMatch(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func requestsWithDefaultURLRequestAndURLAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(urlRequest: URLRequest(url: Test.url))
        expectHashableMatch(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func requestsWithDifferentURLsAreNotEquivalent() {
        let lhs = ImageRequest(url: URL(string: "http://test.com/1.png"))
        let rhs = ImageRequest(url: URL(string: "http://test.com/2.png"))
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
    }

    @Test func requestsWithTheSameProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        expectHashableMatch(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func requestsWithDifferentProcessorsAreNotEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
    }

    @Test func uRLRequestParametersAreIgnored() {
        let lhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let rhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        expectHashableMatch(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func settingDefaultProcessorManually() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url, processors: lhs.processors)
        expectHashableMatch(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }
}

@Suite struct ImageRequestLoadKeyTests {
    @Test func defaults() {
        let request = ImageRequest(url: Test.url)
        expectHashableMatch(TaskFetchOriginalDataKey(request), TaskFetchOriginalDataKey(request))
    }

    @Test func requestsWithTheSameURLsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url)
        expectHashableMatch(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    @Test func requestsWithDifferentURLsAreNotEquivalent() {
        let lhs = ImageRequest(url: URL(string: "http://test.com/1.png"))
        let rhs = ImageRequest(url: URL(string: "http://test.com/2.png"))
        #expect(TaskFetchOriginalDataKey(lhs) != TaskFetchOriginalDataKey(rhs))
    }

    @Test func requestsWithTheSameProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        expectHashableMatch(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    @Test func requestsWithDifferentProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        expectHashableMatch(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    @Test func requestWithDifferentURLRequestParametersAreNotEquivalent() {
        let lhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let rhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        #expect(TaskFetchOriginalDataKey(lhs) != TaskFetchOriginalDataKey(rhs))
    }

    @Test func mockImageProcessorCorrectlyImplementsIdentifiers() {
        #expect(MockImageProcessor(id: "1").identifier == MockImageProcessor(id: "1").identifier)
        #expect(MockImageProcessor(id: "1").hashableIdentifier == MockImageProcessor(id: "1").hashableIdentifier)

        #expect(MockImageProcessor(id: "1").identifier != MockImageProcessor(id: "2").identifier)
        #expect(MockImageProcessor(id: "1").hashableIdentifier != MockImageProcessor(id: "2").hashableIdentifier)
    }
}

@Suite struct ImageRequestImageIdTests {
    @Test func thatCacheKeyUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
    }

    @Test func thatCacheKeyUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        expectHashableMatch(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func thatCacheKeyForProcessedImageDataUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
    }

    @Test func thatCacheKeyForProcessedImageDataUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        expectHashableMatch(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func thatLoadKeyForProcessedImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        #expect(TaskLoadImageKey(lhs) != TaskLoadImageKey(rhs))
    }

    @Test func thatLoadKeyForOriginalImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url, userInfo: [.imageIdKey: Test.url.absoluteString])
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"), userInfo: [.imageIdKey: Test.url.absoluteString])
        #expect(TaskFetchOriginalDataKey(lhs) != TaskFetchOriginalDataKey(rhs))
    }
}

private func expectHashableMatch<T: Hashable>(_ lhs: T, _ rhs: T) {
    #expect(lhs.hashValue == rhs.hashValue)
    #expect(lhs == rhs)
}
