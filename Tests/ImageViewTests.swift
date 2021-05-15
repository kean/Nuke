// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke
@testable import NukeUI

class ImageViewTests: XCTestCase {
    var imageView: _ImageView!
    var mockPipeline: MockImagePipeline!
    var mockCache: MockImageCache!

    override func setUp() {
        super.setUp()

        mockCache = MockImageCache()
        mockPipeline = MockImagePipeline {
            $0.imageCache = mockCache
        }

        // Nuke.loadImage(...) methods use shared pipeline by default.
        ImagePipeline.pushShared(mockPipeline)

        imageView = _ImageView()
    }

    override func tearDown() {
        ImagePipeline.popShared()
    }

    // MARK: - Loading

    func testImageLoaded() {
        // When requesting an image with request
        expectToLoadImage(with: Test.request, into: imageView)
        wait()

        // Expect the image to be downloaded and displayed
        XCTAssertNotNil(imageView.image)
    }

    func testImageLoadedWithURL() {
        // When requesting an image with URL
        let expectation = self.expectation(description: "Image loaded")
        NukeUI.loadImage(with: Test.url, into: imageView) { _ in
            expectation.fulfill()
        }
        wait()

        // Expect the image to be downloaded and displayed
        XCTAssertNotNil(imageView.image)
    }

    // MARK: - Managing Tasks

    func testTaskReturned() {
        // When requesting an image
        let task = NukeUI.loadImage(with: Test.request, into: imageView)

        // Expect Nuke to return a task
        XCTAssertNotNil(task)

        // Expect the task's request to be equivalent to the one provided
        XCTAssertEqual(task?.request.urlRequest, Test.request.urlRequest)
    }

    func testTaskIsNilWhenImageInMemoryCache() {
        // When the requested image is stored in memory cache
        let request = Test.request
        mockCache[request] = ImageContainer(image: PlatformImage())

        // When requesting an image
        let task = NukeUI.loadImage(with: request, into: imageView)

        // Expect Nuke to not return any tasks
        XCTAssertNil(task)
    }

    // MARK: - Prepare For Reuse

    func testViewPreparedForReuse() {
        // Given an image view displaying an image
        imageView.image = Test.image

        // When requesting the new image
        NukeUI.loadImage(with: Test.request, into: imageView)

        // Then
        XCTAssertNil(imageView.image)
    }

    func testViewPreparedForReuseDisabled() {
        // Given an image view displaying an image
        let image = Test.image
        imageView.image = image

        // When requesting the new image with prepare for reuse disabled
        var options = ImageLoadingOptions()
        options.isPrepareForReuseEnabled = false
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        // Expect the original image to still be displayed
        XCTAssertEqual(imageView.image, image)
    }

    // MARK: - Memory Cache

    func testMemoryCacheUsed() {
        // Given the requested image stored in memory cache
        let image = Test.image
        mockCache[Test.request] = ImageContainer(image: image)

        // When requesting the new image
        NukeUI.loadImage(with: Test.request, into: imageView)

        // Expect image to be displayed immediatelly
        XCTAssertEqual(imageView.image, image)
    }

    func testMemoryCacheDisabled() {
        // Given the requested image stored in memory cache
        mockCache[Test.request] = Test.container

        // When requesting the image with memory cache read disabled
        var request = Test.request
        request.options.memoryCacheOptions.isReadAllowed = false
        NukeUI.loadImage(with: request, into: imageView)

        // Expect image to not be displayed, loaded asyncrounously instead
        XCTAssertNil(imageView.image)
    }

    // MARK: - Completion and Progress Closures

    func testCompletionCalled() {
        var didCallCompletion = false
        let expectation = self.expectation(description: "Image loaded")
        NukeUI.loadImage(
            with: Test.request,
            into: imageView,
            completion: { result in
                // Expect completion to be called  on the main thread
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(result.isSuccess)
                didCallCompletion = true
                expectation.fulfill()
            }
        )

        // Expect completion to be called asynchronously
        XCTAssertFalse(didCallCompletion)
        wait()
    }

    func testCompletionCalledImageFromCache() {
        // Given the requested image stored in memory cache
        mockCache[Test.request] = Test.container

        var didCallCompletion = false
        NukeUI.loadImage(
            with: Test.request,
            into: imageView,
            completion: { result in
                // Expect completion to be called syncrhonously on the main thread
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(result.isSuccess)
                didCallCompletion = true
            }
        )
        XCTAssertTrue(didCallCompletion)
    }

    func testProgressHandlerCalled() {
        let expectedProgress = expectProgress([(10, 20), (20, 20)])

        // When loading an image into a view
        NukeUI.loadImage(
            with: Test.request,
            into: imageView,
            progress: { _, completed, total in
                // Expect progress to be reported, on the main thread
                XCTAssertTrue(Thread.isMainThread)
                expectedProgress.received((completed, total))
            }
        )

        wait()
    }

    // MARK: - Cancellation

    func testRequestCancelled() {
        mockPipeline.operationQueue.isSuspended = true

        // Given an image view with an associated image task
        expectNotification(MockImagePipeline.DidStartTask, object: mockPipeline)
        NukeUI.loadImage(with: Test.url, into: imageView)
        wait()

        // Expect the task to get cancelled
        expectNotification(MockImagePipeline.DidCancelTask, object: mockPipeline)

        // When asking Nuke to cancel the request for the view
        NukeUI.cancelRequest(for: imageView)
        wait()
    }

    func testRequestCancelledWhenNewRequestStarted() {
        mockPipeline.operationQueue.isSuspended = true

        // Given an image view with an associated image task
        expectNotification(MockImagePipeline.DidStartTask, object: mockPipeline)
        NukeUI.loadImage(with: Test.url, into: imageView)
        wait()

        // When starting loading a new image
        // Expect previous task to get cancelled
        expectNotification(MockImagePipeline.DidCancelTask, object: mockPipeline)
        NukeUI.loadImage(with: Test.url, into: imageView)
        wait()
    }

    func testRequestCancelledWhenTargetGetsDeallocated() {
        mockPipeline.operationQueue.isSuspended = true

        // Wrap everything in autorelease pool to make sure that imageView
        // gets deallocated immediately.
        autoreleasepool {
            // Given an image view with an associated image task
            var imageView: _ImageView! = _ImageView()
            expectNotification(MockImagePipeline.DidStartTask, object: mockPipeline)
            NukeUI.loadImage(with: Test.url, into: imageView)
            wait()

            // Expect the task to be cancelled automatically
            expectNotification(MockImagePipeline.DidCancelTask, object: mockPipeline)

            // When the view is deallocated
            imageView = nil
        }
        wait()
    }

    func testCancellingTheTaskAndWaitingForCompletion() {
        mockPipeline.operationQueue.isSuspended = true

        // Given pipeline with cancellation disabled (important!)
        mockPipeline.isCancellationEnabled = false

        // Given an image view which is in the process of loading the image
        NukeUI.loadImage(with: Test.request, into: imageView) { _ in
            // Expect completion to never get called, we're already displaying
            // the image B by that point.
            XCTFail("Enexpected completion")
        }

        // When cancelling the request
        NukeUI.cancelRequest(for: imageView)

        // When the pipeline finishes loading the image B.
        expectNotification(MockImagePipeline.DidFinishTask)
        mockPipeline.operationQueue.isSuspended = false
        wait()

        // Expect an image view to still be displaying the image B.
        XCTAssertNil(imageView.image)
    }

    func testCancellingTheTaskByRequestingNewImageStoredInCache() {
        mockPipeline.operationQueue.isSuspended = true

        let requestA = ImageRequest(url: URL(string: "test://imageA")!)
        let requestB = ImageRequest(url: URL(string: "test://imageB")!)

        // Given pipeline with cancellation disabled (important!)
        mockPipeline.isCancellationEnabled = false

        // Given an image A not stored in cache and image B - stored.
        let imageB = PlatformImage()
        mockCache[requestB] = ImageContainer(image: imageB)

        // Given an image view which is in the process of loading the image A.
        NukeUI.loadImage(with: requestA, into: imageView) { _ in
            // Expect completion to never get called, we're already displaying
            // the image B by that point.
            XCTFail("Enexpected completion for requestA")
        }

        // When starting a starting a new request for the image B.
        NukeUI.loadImage(with: requestB, into: imageView)

        // Expect an image B to be displayed immediatelly.
        XCTAssertEqual(imageB, imageView.image)

        // When the pipeline finishes loading the image B.
        expectNotification(MockImagePipeline.DidFinishTask)
        mockPipeline.operationQueue.isSuspended = false
        wait()

        // Expect an image view to still be displaying the image B.
        XCTAssertEqual(imageB, imageView.image)
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
        let placeholder = PlatformImage()
        options.placeholder = placeholder

        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

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
        let failureImage = PlatformImage()
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
        let failureImage = PlatformImage()
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
        options.placeholder = PlatformImage()

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

        mockCache[Test.request] = Test.container

        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

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
        options.failureImage = PlatformImage()

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
    
    #if os(iOS) || os(tvOS)
    
    // MARK: - Tint Colors
    
    func testPlaceholderAndSuccessTintColorApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.tintColors = .init(
            success: .blue,
            failure: nil,
            placeholder: .yellow
        )
        options.placeholder = PlatformImage()
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        
        // Then
        XCTAssertEqual(imageView.tintColor, .yellow)
        wait()
        XCTAssertEqual(imageView.tintColor, .blue)
        XCTAssertEqual(imageView.image?.renderingMode, .alwaysTemplate)
    }
    
    func testSuccessTintColorAppliedWhenFromMemoryCache() {
        // Given
        var options = ImageLoadingOptions()
        options.tintColors = .init(
            success: .blue,
            failure: nil,
            placeholder: nil
        )
        
        mockCache[Test.request] = Test.container
        
        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)
        
        // Then
        XCTAssertEqual(imageView.tintColor, .blue)
        XCTAssertEqual(imageView.image?.renderingMode, .alwaysTemplate)
    }
    
    func testFailureTintColorApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.tintColors = .init(
            success: nil,
            failure: .red,
            placeholder: nil
        )
        options.failureImage = PlatformImage()
        
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()
        
        // Then
        XCTAssertEqual(imageView.tintColor, .red)
        XCTAssertEqual(imageView.image?.renderingMode, .alwaysTemplate)
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
        let placeholder = PlatformImage()
        options.placeholder = placeholder

        ImageLoadingOptions.pushShared(options)

        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.image, placeholder)

        ImageLoadingOptions.popShared()
    }

    // MARK: - Cache Policy

    func testReloadIgnoringCacheData() {
        // When the requested image is stored in memory cache
        var request = Test.request
        mockCache[request] = ImageContainer(image: PlatformImage())

        request.cachePolicy = .reloadIgnoringCachedData

        // When
        expectToFinishLoadingImage(with: request, into: imageView)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
    }
}
