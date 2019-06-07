// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

@available(*, deprecated)
class DeprecatedImageViewLoadingOptionsTests: XCTestCase {
    var mockCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var imageView: _ImageView!

    override func setUp() {
        super.setUp()

        mockCache = MockImageCache()
        dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = mockCache
        }
        // Nuke.loadImage(...) methods use shared pipeline by default.
        ImagePipeline.pushShared(pipeline)

        imageView = _ImageView()
    }

    override func tearDown() {
        ImagePipeline.popShared()
    }

    // MARK: - Transition

    func testCustomTransitionPerformed() {
        // Given
        var options = ImageLoadingOptions()

        let expectTransition = self.expectation(description: "")
        options.transition = .custom({ (view, image) in
            // Then
            XCTAssertEqual(view, self.imageView)
            XCTAssertNil(self.imageView.image) // Image isn't displayed automatically.
            XCTAssertEqual(view, self.imageView)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        // When
        expectToLoadImage(with: Test.request, options: options, into: imageView)
        wait()
    }

    // Tests https://github.com/kean/Nuke/issues/206
    func testImageIsDisplayedFadeInTransition() {
        // Given options with .fadeIn transition
        let options = ImageLoadingOptions(transition: .fadeIn(duration: 10))

        // When loading an image into an image view
        expectToLoadImage(with: Test.request, options: options, into: imageView)
        wait()

        // Then image is actually displayed
        XCTAssertNotNil(imageView.image)
    }

    // MARK: - Placeholder

    func testPlaceholderDisplayed() {
        // Given
        var options = ImageLoadingOptions()
        let placeholder = Image()
        options.placeholder = placeholder

        // When
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.image, placeholder)
    }

    // MARK: - Failure Image

    func testFailureImageDisplayed() {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "ErrorDomain", code: 42, userInfo: nil)
        )

        var options = ImageLoadingOptions()
        let failureImage = Image()
        options.failureImage = failureImage

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()

        // Then
        XCTAssertEqual(imageView.image, failureImage)
    }

    func testFailureImageTransitionRun() {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        var options = ImageLoadingOptions()
        let failureImage = Image()
        options.failureImage = failureImage

        // Given
        let expectTransition = self.expectation(description: "")
        options.failureImageTransition = .custom({ (view, image) in
            // Then
            XCTAssertEqual(view, self.imageView)
            XCTAssertEqual(image, failureImage)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()

        // Then
        XCTAssertEqual(imageView.image, failureImage)
    }

    #if !os(macOS)

    // MARK: - Content Modes

    func testPlaceholderAndSuccessContentModesApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = .init(
            success: .scaleAspectFill, // default is .scaleToFill
            failure: .center,
            placeholder: .center
        )
        options.placeholder = Image()

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.contentMode, .center)
        wait()
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }

    func testSuccessContentModeAppliedWhenFromMemoryCache() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )

        mockCache[Test.request] = Test.image

        // Whem
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }

    func testFailureContentModeApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )
        options.failureImage = Image()

        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()

        // Then
        XCTAssertEqual(imageView.contentMode, .center)
    }

    #endif

    // MARK: - Pipeline

    func testCustomPipelineUsed() {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        var options = ImageLoadingOptions()
        options.pipeline = pipeline

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)

        // Then
        wait { _ in
            _ = pipeline
            XCTAssertEqual(dataLoader.createdTaskCount, 1)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 0)
        }
    }

    // MARK: - Shared Options

    func testSharedOptionsUsed() {
        // Given
        var options = ImageLoadingOptions.shared
        let placeholder = Image()
        options.placeholder = placeholder

        ImageLoadingOptions.pushShared(options)

        // When
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.image, placeholder)

        ImageLoadingOptions.popShared()

    }
}

@available(*, deprecated)
class DeprecatedImageRequestTests: XCTestCase {
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
        request.memoryCacheOptions.isReadAllowed = false
        request.loadKey = "1"
        request.cacheKey = "2"
        request.userInfo = "3"
        request.processor = MockImageProcessor(id: "4")
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
        XCTAssertEqual((copy.processor as? MockImageProcessor)?.identifier, MockImageProcessor(id: "4").identifier)
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

@available(*, deprecated)
class DeprecatedImageRequestCacheKeyTests: XCTestCase {
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

    func testURLRequestParametersAreIgnored() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testSettingDefaultProcessorManually() {
        let request1 = ImageRequest(url: Test.url)
        var request2 = ImageRequest(url: Test.url)
        request2.processor = request1.processor
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

@available(*, deprecated)
class DeprecatedImageRequestLoadKeyTests: XCTestCase {
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

    func testRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertNotEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    // MARK: - Custom Load Key

    func testRequestsWithSameCustomKeysAreEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.loadKey = "1"
        AssertHashableEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testRequestsWithSameCustomKeysButDifferentURLsAreEquivalent() {
        var request1 = ImageRequest(url: URL(string: "https://example.com/photo1.jpg")!)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: URL(string: "https://example.com/photo2.jpg")!)
        request2.loadKey = "1"
        AssertHashableEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }

    func testRequestsWithDifferentCustomKeysAreNotEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.loadKey = "2"
        XCTAssertNotEqual(request1.makeLoadKeyForOriginalImage(), request2.makeLoadKeyForOriginalImage())
    }
}

private typealias CacheKey = ImageRequest.CacheKey

private func AssertHashableEqual<T: Hashable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(lhs.hashValue, rhs.hashValue, file: file, line: line)
    XCTAssertEqual(lhs, rhs, file: file, line: line)
}
