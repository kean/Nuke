// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestTests {
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
        #expect(copy.options.contains(.disableMemoryCacheReads) == true)
        #expect(copy.userInfo["key"] as? String == "3")
        #expect((copy.processors.first as? MockImageProcessor)?.identifier == "4")
        #expect(request.priority == .high) // Original request not updated
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
        // WHEN
        let request = ImageRequest(url: Test.url, userInfo: [.init("a"): 1])

        // THEN
        #expect(request.userInfo["a"] != nil)
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestCacheKeyTests {
    @Test func defaults() {
        let request = Test.request
        assertHashableEqual(MemoryCacheKey(request), MemoryCacheKey(request)) // equal to itself
    }

    @Test func requestsWithTheSameURLsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url)
        assertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func requestsWithDefaultURLRequestAndURLAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(urlRequest: URLRequest(url: Test.url))
        assertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func requestsWithDifferentURLsAreNotEquivalent() {
        let lhs = ImageRequest(url: URL(string: "http://test.com/1.png"))
        let rhs = ImageRequest(url: URL(string: "http://test.com/2.png"))
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
    }

    @Test func requestsWithTheSameProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        assertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func requestsWithDifferentProcessorsAreNotEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
    }

    @Test func urlRequestParametersAreIgnored() {
        let lhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let rhs = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        assertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func settingDefaultProcessorManually() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url, processors: lhs.processors)
        assertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestLoadKeyTests {
    @Test func defaults() {
        let request = ImageRequest(url: Test.url)
        assertHashableEqual(TaskFetchOriginalDataKey(request), TaskFetchOriginalDataKey(request))
    }

    @Test func requestsWithTheSameURLsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url)
        assertHashableEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    @Test func requestsWithDifferentURLsAreNotEquivalent() {
        let lhs = ImageRequest(url: URL(string: "http://test.com/1.png"))
        let rhs = ImageRequest(url: URL(string: "http://test.com/2.png"))
        #expect(TaskFetchOriginalDataKey(lhs) != TaskFetchOriginalDataKey(rhs))
    }

    @Test func requestsWithTheSameProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        assertHashableEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
    }

    @Test func requestsWithDifferentProcessorsAreEquivalent() {
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "2")])
        assertHashableEqual(TaskFetchOriginalDataKey(lhs), TaskFetchOriginalDataKey(rhs))
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

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestImageIdTests {
    @Test func thatCacheKeyUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
    }

    @Test func thatCacheKeyUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url).with {
            $0.imageID = Test.url.absoluteString
        }
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1")).with {
            $0.imageID = Test.url.absoluteString
        }
        assertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func thatCacheKeyForProcessedImageDataUsesAbsoluteURLByDefault() {
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1"))
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
    }

    @Test func thatCacheKeyForProcessedImageDataUsesFilteredURLWhenSet() {
        let lhs = ImageRequest(url: Test.url).with {
            $0.imageID = Test.url.absoluteString
        }
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1")).with {
            $0.imageID = Test.url.absoluteString
        }
        assertHashableEqual(MemoryCacheKey(lhs), MemoryCacheKey(rhs))
    }

    @Test func thatLoadKeyForProcessedImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url).with {
            $0.imageID = Test.url.absoluteString
        }
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1")).with {
            $0.imageID = Test.url.absoluteString
        }
        #expect(TaskLoadImageKey(lhs) != TaskLoadImageKey(rhs))
    }

    @Test func thatLoadKeyForOriginalImageDoesntUseFilteredURL() {
        let lhs = ImageRequest(url: Test.url).with {
            $0.imageID = Test.url.absoluteString
        }
        let rhs = ImageRequest(url: Test.url.appendingPathComponent("?token=1")).with {
            $0.imageID = Test.url.absoluteString
        }
        #expect(TaskFetchOriginalDataKey(lhs) != TaskFetchOriginalDataKey(rhs))
    }

    @Test(.disabled()) func memoryLayout() {
        #expect(ImageRequest._containerInstanceSize == 104)

        #expect(MemoryLayout<ImageRequest.ThumbnailOptions>.size == 9)
        #expect(MemoryLayout<ImageRequest.ThumbnailOptions>.stride == 12)

        #expect(MemoryLayout<ImageRequest.Resource>.size == 17)
        #expect(MemoryLayout<ImageRequest.Resource>.stride == 24)
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ThumbnailOptionsTests {
    // MARK: - Default Values

    @Test func defaultBoolPropertiesWithMaxPixelSize() {
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        #expect(options.createThumbnailFromImageIfAbsent == true)
        #expect(options.createThumbnailFromImageAlways == true)
        #expect(options.createThumbnailWithTransform == true)
        #expect(options.shouldCacheImmediately == true)
    }

    @Test func defaultBoolPropertiesWithSize() {
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels)
        #expect(options.createThumbnailFromImageIfAbsent == true)
        #expect(options.createThumbnailFromImageAlways == true)
        #expect(options.createThumbnailWithTransform == true)
        #expect(options.shouldCacheImmediately == true)
    }

    // MARK: - contentMode

    @Test func contentModeDefaultsToAspectFill() {
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels)
        #expect(options.contentMode == .aspectFill)
    }

    @Test func contentModeAspectFitIsPreserved() {
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit)
        #expect(options.contentMode == .aspectFit)
    }

    // MARK: - Identifier reflects flag changes

    @Test func identifierChangesWhenCreateFromImageIfAbsentIsFalse() {
        var options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        options.createThumbnailFromImageIfAbsent = false
        #expect(options.identifier.hasSuffix("options=falsetruetruetrue"))
    }

    @Test func identifierChangesWhenCreateFromImageAlwaysIsFalse() {
        var options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        options.createThumbnailFromImageAlways = false
        #expect(options.identifier.hasSuffix("options=truefalsetruetrue"))
    }

    @Test func identifierChangesWhenCreateWithTransformIsFalse() {
        var options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        options.createThumbnailWithTransform = false
        #expect(options.identifier.hasSuffix("options=truetruefalsetrue"))
    }

    @Test func identifierChangesWhenShouldCacheImmediatelyIsFalse() {
        var options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        options.shouldCacheImmediately = false
        #expect(options.identifier.hasSuffix("options=truetruetruefalse"))
    }

    // MARK: - Hashable

    @Test func equalOptionsAreEqual() {
        #expect(ImageRequest.ThumbnailOptions(maxPixelSize: 400) == ImageRequest.ThumbnailOptions(maxPixelSize: 400))
    }

    @Test func optionsWithDifferentFlagAreNotEqual() {
        let lhs = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        var rhs = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        rhs.createThumbnailWithTransform = false
        #expect(lhs != rhs)
    }

    @Test func optionsWithDifferentContentModeAreNotEqual() {
        let lhs = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)
        let rhs = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit)
        #expect(lhs != rhs)
    }

    @Test func thumbnailOptionsWithDifferentMaxPixelSizeHaveDifferentIdentifiers() {
        let small = ImageRequest.ThumbnailOptions(maxPixelSize: 200)
        let large = ImageRequest.ThumbnailOptions(maxPixelSize: 800)
        #expect(small.identifier != large.identifier)
    }

    @Test func thumbnailOptionsWithSameParametersAreEqual() {
        let a = ImageRequest.ThumbnailOptions(size: CGSize(width: 300, height: 300), unit: .pixels, contentMode: .aspectFit)
        let b = ImageRequest.ThumbnailOptions(size: CGSize(width: 300, height: 300), unit: .pixels, contentMode: .aspectFit)
        #expect(a == b)
        #expect(a.identifier == b.identifier)
    }

    @Test func modifyingOptionsOnCopyDoesNotAffectOriginal() {
        // GIVEN
        var original = Test.request
        original.options = []

        // WHEN - make a copy and add an option only to the copy
        var copy = original
        copy.options.insert(.disableMemoryCacheReads)

        // THEN - original is unchanged
        #expect(!original.options.contains(.disableMemoryCacheReads))
        #expect(copy.options.contains(.disableMemoryCacheReads))
    }

    @Test func loadOptionsDoNotAffectMemoryCacheKey() {
        // GIVEN - same URL, but different load-time options
        let base          = ImageRequest(url: Test.url)
        let disableReads  = ImageRequest(url: Test.url, options: [.disableDiskCacheReads])
        let disableWrites = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])
        let reload        = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])

        // THEN - the memory-cache key is determined by URL/processors, not by load options
        let baseKey = MemoryCacheKey(base)
        #expect(MemoryCacheKey(disableReads)  == baseKey)
        #expect(MemoryCacheKey(disableWrites) == baseKey)
        #expect(MemoryCacheKey(reload)        == baseKey)
    }
}

private func assertHashableEqual<T: Hashable>(_ lhs: T, _ rhs: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(lhs.hashValue == rhs.hashValue, sourceLocation: sourceLocation)
    #expect(lhs == rhs, sourceLocation: sourceLocation)
}
