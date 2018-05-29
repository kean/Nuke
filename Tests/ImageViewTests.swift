// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageViewTests: XCTestCase {
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

    // MARK: - Loading

    func testImageLoaded() {
        // When
        expectToLoadImage(with: Test.request, into: imageView)
        wait()

        // Then
        XCTAssertNotNil(imageView.image)
    }

    func testImageLoadedWithURL() {
        // When
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(with: Test.url, into: imageView) { response, _ in
            expectation.fulfill()
        }
        wait()

        // Then
        XCTAssertNotNil(imageView.image)
    }

    // MARK: - Managing Tasks

    func testTaskReturned() {
        // When
        let task = Nuke.loadImage(with: Test.request, into: imageView)

        // Then
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.request.urlRequest, Test.request.urlRequest)
    }

    func testTaskIsNilWhenImageInMemoryCache() {
        // Given
        let request = Test.request
        mockCache[request] = Image()

        // When
        let task = Nuke.loadImage(with: request, into: imageView)

        // Then
        XCTAssertNil(task)
    }

    // MARK: - Prepare For Reuse

    func testViewPreparedForReuse() {
        // Given
        imageView.image = Test.image

        // When
        Nuke.loadImage(with: Test.request, into: imageView)

        // Then
        XCTAssertNil(imageView.image)
    }

    func testViewPreparedForReuseDisabled() {
        // Given
        var options = ImageLoadingOptions()
        options.isPrepareForReuseEnabled = false

        // When
        imageView.image = Test.image
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.image, Test.image)
    }

    // MARK: - Memory Cache

    func testMemoryCacheUsed() {
        // Given
        mockCache[Test.request] = Test.image

        // When
        Nuke.loadImage(with: Test.request, into: imageView)

        // Then
        XCTAssertEqual(imageView.image, Test.image)
    }

    func testMemoryCacheDisabled() {
        // Given
        mockCache[Test.request] = Test.image

        var request = Test.request
        request.memoryCacheOptions.isReadAllowed = false

        // When
        Nuke.loadImage(with: request, into: imageView)

        // Then
        XCTAssertNil(imageView.image) // Image will load asynchronously
    }

    // MARK: - Completion and Progress Closures

    func testCompletionCalled() {
        // When
        var didCallCompletion = false
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { response, _ in
                // Then
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(response)
                didCallCompletion = true
                expectation.fulfill()
        })

        // Then
        XCTAssertFalse(didCallCompletion) // not called synchronously
        wait()
    }

    func testCompletionCalledImageFromCache() {
        // Given
        mockCache[Test.request] = Test.image

        // When
        var didCallCompletion = false
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { response, _ in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(response)
                didCallCompletion = true
        })

        // Then
        XCTAssertTrue(didCallCompletion)
    }

    func testProgressHandlerCalled() {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let expectedCompleted = self.expect(values: [10, 20] as [Int64])
        let expectedTotal = self.expect(values: [20, 20] as [Int64])

        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            progress: { _, completed, total in
                // Then
                XCTAssertTrue(Thread.isMainThread)
                expectedCompleted.received(completed)
                expectedTotal.received(total)
            }
        )

        wait()
    }

    // MARK: - Cancellation

    func testRequestCancelled() {
        // Given
        dataLoader.queue.isSuspended = true

        // When/Then
        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        Nuke.cancelRequest(for: imageView)
        wait()
    }

    func testRequestCancelledWhenNewRequestStarted() {
        // Given
        dataLoader.queue.isSuspended = true

        // When/Then
        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()
    }

    func testRequestCancelledWhenTargetGetsDeallocated() {
        // Wrap everything in autorelease pool to make sure that imageView
        // gets deallocated immediately.
        autoreleasepool {
            // Given
            var imageView: _ImageView! = _ImageView()

            dataLoader.queue.isSuspended = true

            // When/Then
            expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
            Nuke.loadImage(with: Test.url, into: imageView)
            wait()

            expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
            imageView = nil // deallocate target
        }
        wait()
    }
}

class ImageViewLoadingOptionsTests: XCTestCase {
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
