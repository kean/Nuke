// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

// MARK: - Copy-on-Write

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestCopyOnWriteTests {
    /// A mutable property of a request, rendered as a string so that two
    /// requests can be compared field by field.
    enum Field: String, CaseIterable, Sendable {
        case priority, processors, options, userInfo, imageID, scale, thumbnail

        func value(in request: ImageRequest) -> String {
            switch self {
            case .priority: "\(request.priority)"
            case .processors: request.processors.map(\.identifier).joined(separator: ",")
            case .options: "\(request.options.rawValue)"
            case .userInfo: request.userInfo.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
            case .imageID: request.imageID ?? "nil"
            case .scale: "\(request.scale)"
            case .thumbnail: request.thumbnail?.identifier ?? "nil"
            }
        }

        /// Changes the field to a value different from the one in
        /// ``ImageRequestCopyOnWriteTests/makeConfiguredRequest()``.
        func mutate(_ request: inout ImageRequest) {
            switch self {
            case .priority: request.priority = .veryLow
            case .processors: request.processors = [MockImageProcessor(id: "p2")]
            case .options: request.options.insert(.skipDecompression)
            case .userInfo: request.userInfo["key"] = "other"
            case .imageID: request.imageID = "other-id"
            case .scale: request.scale = 2
            case .thumbnail: request.thumbnail = nil
            }
        }
    }

    /// A request with every mutable property moved away from its default.
    static func makeConfiguredRequest() -> ImageRequest {
        var request = ImageRequest(
            url: Test.url,
            processors: [MockImageProcessor(id: "p1")],
            priority: .high,
            options: [.disableMemoryCacheReads]
        )
        request.userInfo["key"] = "value"
        request.imageID = "custom-id"
        request.scale = 3
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 200)
        return request
    }

    static func snapshot(of request: ImageRequest) -> [Field: String] {
        Dictionary(uniqueKeysWithValues: Field.allCases.map { ($0, $0.value(in: request)) })
    }

    static func changedFields(from lhs: [Field: String], to rhs: [Field: String]) -> [Field] {
        Field.allCases.filter { lhs[$0] != rhs[$0] }
    }

    /// The storage copy made on the first mutation has to carry every other
    /// field over: a field it forgets reverts to its default on the copy.
    @Test(arguments: Field.allCases)
    func mutatingCopyLeavesOriginalIntact(_ field: Field) {
        // Given
        let original = Self.makeConfiguredRequest()
        let before = Self.snapshot(of: original)

        // When
        var copy = original
        field.mutate(&copy)

        // Then
        #expect(Self.snapshot(of: original) == before)
        #expect(Self.changedFields(from: before, to: Self.snapshot(of: copy)) == [field])
        #expect(copy.url == original.url)
        #expect(copy.originalImageID == original.originalImageID)
        #expect(!copy.isIdentical(to: original))
    }

    @Test(arguments: Field.allCases)
    func mutatingOriginalLeavesCopyIntact(_ field: Field) {
        // Given
        var original = Self.makeConfiguredRequest()
        let copy = original
        let before = Self.snapshot(of: copy)

        // When
        field.mutate(&original)

        // Then
        #expect(Self.snapshot(of: copy) == before)
        #expect(Self.changedFields(from: before, to: Self.snapshot(of: original)) == [field])
    }

    @Test func consecutiveMutationsOfCopyAccumulate() {
        // Given
        let original = Self.makeConfiguredRequest()
        let before = Self.snapshot(of: original)

        // When every field of the copy is changed, one after another
        var copy = original
        for field in Field.allCases {
            field.mutate(&copy)
        }

        // Then none of the mutations is lost and none leaks into the original
        #expect(Self.changedFields(from: before, to: Self.snapshot(of: copy)) == Field.allCases)
        #expect(Self.snapshot(of: original) == before)
    }

    // MARK: Internal Derived Requests

    @Test func withProcessorsReplacesOnlyProcessors() {
        // Given
        let request = Self.makeConfiguredRequest()
        let before = Self.snapshot(of: request)

        // When
        let derived = request.withProcessors([])

        // Then
        #expect(derived.processors.isEmpty)
        #expect(Self.changedFields(from: before, to: Self.snapshot(of: derived)) == [.processors])
        #expect(Self.snapshot(of: request) == before)
    }

    @Test func withoutThumbnailRemovesOnlyThumbnail() {
        // Given
        let request = Self.makeConfiguredRequest()
        let before = Self.snapshot(of: request)

        // When
        let derived = request.withoutThumbnail()

        // Then
        #expect(derived.thumbnail == nil)
        #expect(Self.changedFields(from: before, to: Self.snapshot(of: derived)) == [.thumbnail])
        #expect(Self.snapshot(of: request) == before)
    }
}

// MARK: - Initializers

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestInitializerTests {
    enum Kind: String, CaseIterable, Sendable {
        case url, urlRequest, data, image

        func make(
            processors: [any ImageProcessing] = [],
            priority: ImageRequest.Priority = .normal,
            options: ImageRequest.Options = []
        ) -> ImageRequest {
            switch self {
            case .url:
                ImageRequest(url: Test.url, processors: processors, priority: priority, options: options)
            case .urlRequest:
                ImageRequest(urlRequest: URLRequest(url: Test.url), processors: processors, priority: priority, options: options)
            case .data:
                ImageRequest(id: "closure-id", data: { Test.data }, processors: processors, priority: priority, options: options)
            case .image:
                ImageRequest(id: "closure-id", image: { Test.container }, processors: processors, priority: priority, options: options)
            }
        }

        var expectedImageID: String {
            switch self {
            case .url, .urlRequest: Test.url.absoluteString
            case .data, .image: "closure-id"
            }
        }
    }

    @Test(arguments: Kind.allCases)
    func defaults(_ kind: Kind) {
        // When
        let request = kind.make()

        // Then
        #expect(request.imageID == kind.expectedImageID)
        #expect(request.priority == .normal)
        #expect(request.processors.isEmpty)
        #expect(request.options == [])
        #expect(request.userInfo.isEmpty)
        #expect(request.scale == 1)
        #expect(request.thumbnail == nil)
    }

    @Test(arguments: Kind.allCases)
    func processorsPriorityAndOptionsArePassedThrough(_ kind: Kind) {
        // When
        let request = kind.make(
            processors: [MockImageProcessor(id: "p1"), MockImageProcessor(id: "p2")],
            priority: .veryHigh,
            options: [.skipDecompression, .disableDiskCache]
        )

        // Then
        #expect(request.processors.map(\.identifier) == ["p1", "p2"])
        #expect(request.priority == .veryHigh)
        #expect(request.options == [.skipDecompression, .disableDiskCache])
    }

    @Test func urlInitializerCreatesDefaultURLRequest() {
        // When
        let request = ImageRequest(url: Test.url)

        // Then
        #expect(request.url == Test.url)
        #expect(request.urlRequest == URLRequest(url: Test.url))
        #expect(request.urlRequest?.cachePolicy == .useProtocolCachePolicy)
    }

    @Test func urlRequestIsPassedThroughUnchanged() {
        // Given
        var urlRequest = URLRequest(url: Test.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 7)
        urlRequest.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        urlRequest.allowsCellularAccess = false

        // When
        let request = ImageRequest(urlRequest: urlRequest)

        // Then
        #expect(request.urlRequest == urlRequest)
        #expect(request.urlRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request.url == Test.url)
        #expect(request.imageID == Test.url.absoluteString)
    }

    /// The image ID is the absolute string, so a relative URL and its absolute
    /// counterpart share the cache entries.
    @Test func imageIDOfRelativeURLIsItsAbsoluteString() throws {
        // Given
        let base = try #require(URL(string: "https://example.com/images/"))
        let relative = try #require(URL(string: "avatar.jpeg?size=2", relativeTo: base))
        let absolute = try #require(URL(string: "https://example.com/images/avatar.jpeg?size=2"))

        // When
        let request = ImageRequest(url: relative)

        // Then
        #expect(request.imageID == absolute.absoluteString)
        #expect(ImageRequest(urlRequest: URLRequest(url: relative)).imageID == absolute.absoluteString)
        #expect(MemoryCacheKey(request) == MemoryCacheKey(ImageRequest(url: absolute)))
    }

    @Test func nilURL() {
        // When
        let request = ImageRequest(url: nil)

        // Then
        #expect(request.url == nil)
        #expect(request.urlRequest == nil)
        #expect(request.imageID == nil)
    }

    @Test func urlRequestWithoutURL() {
        // Given
        var urlRequest = URLRequest(url: Test.url)
        urlRequest.url = nil

        // When
        let request = ImageRequest(urlRequest: urlRequest)

        // Then the URL request is kept, but there is nothing to identify the image by
        #expect(request.urlRequest != nil)
        #expect(request.url == nil)
        #expect(request.imageID == nil)
    }

    @Test func stringLiteral() {
        // When
        let request: ImageRequest = "https://example.com/image.jpeg"

        // Then
        #expect(request.url?.absoluteString == "https://example.com/image.jpeg")
        #expect(request.imageID == "https://example.com/image.jpeg")
    }

    @Test func emptyStringLiteralProducesRequestWithoutURL() {
        // When
        let request: ImageRequest = ""

        // Then
        #expect(request.url == nil)
        #expect(request.imageID == nil)
    }

    @Test(arguments: [Kind.data, .image])
    func closureRequestHasNoURLAndDoesNotRunTheClosure(_ kind: Kind) {
        // Given
        let calls = OSAllocatedUnfairLock(initialState: 0)

        // When
        let request = switch kind {
        case .data: ImageRequest(id: "closure-id", data: {
            calls.withLock { $0 += 1 }
            return Test.data
        })
        default: ImageRequest(id: "closure-id", image: {
            calls.withLock { $0 += 1 }
            return Test.container
        })
        }

        // Then
        #expect(request.url == nil)
        #expect(request.urlRequest == nil)
        #expect(request.imageID == "closure-id")
        #expect(calls.withLock { $0 } == 0)
    }
}

// MARK: - Image ID Override

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestImageIDOverrideTests {
    @Test func overrideChangesImageIDButNotTheResource() throws {
        // Given
        let url = try #require(URL(string: "https://example.com/image.jpeg?token=123"))
        var request = ImageRequest(url: url)

        // When
        request.imageID = "https://example.com/image.jpeg"

        // Then
        #expect(request.imageID == "https://example.com/image.jpeg")
        #expect(request.url == url)
        #expect(request.urlRequest?.url == url)
        #expect(request.originalImageID == url.absoluteString)
    }

    @Test func emptyOverrideIsHonored() {
        // When
        var request = ImageRequest(url: Test.url)
        request.imageID = ""

        // Then an empty ID is a valid ID, not a request to use the default one
        #expect(request.imageID == "")
        #expect(MemoryCacheKey(request) != MemoryCacheKey(ImageRequest(url: Test.url)))
    }

    @Test func overrideOnClosureRequestKeepsTheOriginalID() {
        // When
        var request = ImageRequest(id: "original", data: { Test.data })
        request.imageID = "override"

        // Then
        #expect(request.imageID == "override")
        #expect(request.originalImageID == "original")
    }

    @Test func requestsWithSameOverrideShareMemoryCacheKeyButNotDataLoadingKey() {
        // Given two different closures under the same override
        let lhs = ImageRequest(id: "a", data: { Test.data }).with { $0.imageID = "shared" }
        let rhs = ImageRequest(id: "b", data: { Test.data }).with { $0.imageID = "shared" }

        // Then they share the cached image, but each fetches its own data
        #expect(MemoryCacheKey(lhs) == MemoryCacheKey(rhs))
        #expect(TaskFetchOriginalDataKey(lhs) != TaskFetchOriginalDataKey(rhs))
    }
}

// MARK: - Options

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestOptionsTests {
    static let primitives: [ImageRequest.Options] = [
        .disableMemoryCacheReads,
        .disableMemoryCacheWrites,
        .disableDiskCacheReads,
        .disableDiskCacheWrites,
        .returnCacheDataDontLoad,
        .skipDecompression,
        .skipDataLoadingQueue
    ]

    /// Two options sharing a bit would make one imply the other.
    @Test func eachPrimitiveOptionIsDistinctBit() {
        for option in Self.primitives {
            #expect(option.rawValue.nonzeroBitCount == 1, "\(option)")
        }
        #expect(Set(Self.primitives.map(\.rawValue)).count == Self.primitives.count)
    }

    /// The unions are exact: `reloadIgnoringCachedData`, for one, disables the
    /// cache reads, but the freshly loaded image still updates the caches.
    @Test func compositeOptionsAreUnionsOfTheirParts() {
        #expect(ImageRequest.Options.disableMemoryCache == [.disableMemoryCacheReads, .disableMemoryCacheWrites])
        #expect(ImageRequest.Options.disableDiskCache == [.disableDiskCacheReads, .disableDiskCacheWrites])
        #expect(ImageRequest.Options.reloadIgnoringCachedData == [.disableMemoryCacheReads, .disableDiskCacheReads])
    }
}

// MARK: - Priority

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestPriorityTests {
    typealias Priority = ImageRequest.Priority

    static let ascending: [Priority] = [.veryLow, .low, .normal, .high, .veryHigh]

    @Test func prioritiesAreStrictlyOrdered() {
        for (i, lhs) in Self.ascending.enumerated() {
            for (j, rhs) in Self.ascending.enumerated() {
                #expect((lhs < rhs) == (i < j), "\(lhs) < \(rhs)")
                #expect((lhs == rhs) == (i == j), "\(lhs) == \(rhs)")
            }
        }
        #expect(Self.ascending.reversed().sorted() == Self.ascending)
    }

    /// The pipeline schedules the work by the task priority it maps to.
    @Test func taskPriorityPreservesTheOrder() {
        #expect(Self.ascending.map(\.taskPriority) == Nuke.TaskPriority.allCases)
    }

    @Test func codableRoundTripUsesNames() throws {
        let names = ["veryLow", "low", "normal", "high", "veryHigh"]
        for (priority, name) in zip(Self.ascending, names) {
            let data = try JSONEncoder().encode(priority)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(name)\"")
            #expect(try JSONDecoder().decode(Priority.self, from: data) == priority)
        }
    }
}

// MARK: - Scale and Thumbnail Keys

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestScaleKeyTests {
    /// The scale changes the decoded image, but not the data it's decoded from.
    @Test func scaleDistinguishesImagesButNotData() {
        // Given
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url).with { $0.scale = 3 }

        // Then
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
        #expect(TaskLoadImageKey(lhs) != TaskLoadImageKey(rhs))
        #expect(TaskFetchOriginalImageKey(lhs) != TaskFetchOriginalImageKey(rhs))
        #expect(TaskFetchOriginalDataKey(lhs) == TaskFetchOriginalDataKey(rhs))
    }

    @Test func equalScalesProduceEqualKeys() {
        // Given
        let lhs = ImageRequest(url: Test.url).with { $0.scale = 2 }
        let rhs = ImageRequest(url: Test.url).with { $0.scale = 2 }

        // Then
        #expect(MemoryCacheKey(lhs) == MemoryCacheKey(rhs))
        #expect(MemoryCacheKey(lhs).hashValue == MemoryCacheKey(rhs).hashValue)
        #expect(TaskFetchOriginalImageKey(lhs) == TaskFetchOriginalImageKey(rhs))
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestThumbnailKeyTests {
    typealias ThumbnailOptions = ImageRequest.ThumbnailOptions

    /// A thumbnail is a different image made from the same data.
    @Test func thumbnailDistinguishesImagesButNotData() {
        // Given
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url).with { $0.thumbnail = ThumbnailOptions(maxPixelSize: 100) }

        // Then
        #expect(MemoryCacheKey(lhs) != MemoryCacheKey(rhs))
        #expect(TaskFetchOriginalImageKey(lhs) != TaskFetchOriginalImageKey(rhs))
        #expect(TaskFetchOriginalDataKey(lhs) == TaskFetchOriginalDataKey(rhs))
    }

    /// The identifier is a part of the disk cache key, so the thumbnails that
    /// differ must never share one.
    @Test func identifierDependsOnContentMode() {
        let fill = ThumbnailOptions(size: CGSize(width: 300, height: 200), unit: .pixels, contentMode: .aspectFill)
        let fit = ThumbnailOptions(size: CGSize(width: 300, height: 200), unit: .pixels, contentMode: .aspectFit)
        #expect(fill.identifier != fit.identifier)
    }

    @Test func identifierDistinguishesWidthFromHeight() {
        let landscape = ThumbnailOptions(size: CGSize(width: 300, height: 200), unit: .pixels)
        let portrait = ThumbnailOptions(size: CGSize(width: 200, height: 300), unit: .pixels)
        #expect(landscape != portrait)
        #expect(landscape.identifier != portrait.identifier)
    }

    @Test func maxPixelSizeDoesNotCollideWithFlexibleSize() {
        let maxPixelSize = ThumbnailOptions(maxPixelSize: 400)
        let flexible = ThumbnailOptions(size: CGSize(width: 400, height: 0), unit: .pixels)
        #expect(maxPixelSize != flexible)
        #expect(maxPixelSize.identifier != flexible.identifier)
    }

    @Test func turningFlagBackOnRestoresEquality() {
        // Given
        let original = ThumbnailOptions(maxPixelSize: 400)
        var options = original

        // When
        options.createThumbnailWithTransform = false
        options.createThumbnailWithTransform = true

        // Then
        #expect(options == original)
        #expect(options.hashValue == original.hashValue)
        #expect(options.identifier == original.identifier)
    }

    @Test func flagsAreIndependent() {
        // When
        var options = ThumbnailOptions(maxPixelSize: 400)
        options.createThumbnailFromImageIfAbsent = false
        options.shouldCacheImmediately = false

        // Then
        #expect(options.createThumbnailFromImageIfAbsent == false)
        #expect(options.createThumbnailFromImageAlways == true)
        #expect(options.createThumbnailWithTransform == true)
        #expect(options.shouldCacheImmediately == false)
        #expect(options.identifier.hasSuffix("options=falsetruetruefalse"))
    }
}

// MARK: - User Info

@Suite(.timeLimit(.minutes(5)))
struct ImageRequestUserInfoTests {
    @Test func keyInitializersAreEquivalent() {
        // A literal argument would be coerced with `init(stringLiteral:)`
        let rawValue = "com.example/key"
        let lhs = ImageRequest.UserInfoKey(rawValue)
        let rhs: ImageRequest.UserInfoKey = "com.example/key"
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
        #expect(lhs.rawValue == rawValue)
    }

    /// The user info is metadata: it doesn't identify the image.
    @Test func userInfoDoesNotAffectKeys() {
        // Given
        let lhs = ImageRequest(url: Test.url)
        let rhs = ImageRequest(url: Test.url).with { $0.userInfo[.labelKey] = "avatar" }

        // Then
        #expect(MemoryCacheKey(lhs) == MemoryCacheKey(rhs))
        #expect(TaskLoadImageKey(lhs) == TaskLoadImageKey(rhs))
        #expect(TaskFetchOriginalDataKey(lhs) == TaskFetchOriginalDataKey(rhs))
    }
}
