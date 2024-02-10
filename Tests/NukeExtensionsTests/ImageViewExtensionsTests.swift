// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
#if os(tvOS)
import TVUIKit
#endif
@testable import Nuke
@testable import NukeExtensions

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@MainActor
class ImageViewExtensionsTests: XCTestCase {
    var imageView: _ImageView!
    var observer: ImagePipelineObserver!
    var imageCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    
    @MainActor
    override func setUp() {
        super.setUp()
        
        imageCache = MockImageCache()
        dataLoader = MockDataLoader()
        observer = ImagePipelineObserver()
        pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
        
        // Nuke.loadImage(...) methods use shared pipeline by default.
        ImagePipeline.pushShared(pipeline)
        
        imageView = _ImageView()
    }
    
    override func tearDown() {
        super.tearDown()
        
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
    
#if os(tvOS)
    func testImageLoadedToTVPosterView() {
        // Use local instance for this tvOS specific test for simplicity
        let posterView = TVPosterView()
        
        // When requesting an image with request
        expectToLoadImage(with: Test.request, into: posterView)
        wait()
        
        // Expect the image to be downloaded and displayed
        XCTAssertNotNil(posterView.image)
    }
#endif
    
    func testImageLoadedWithURL() {
        // When requesting an image with URL
        let expectation = self.expectation(description: "Image loaded")
        NukeExtensions.loadImage(with: Test.url, into: imageView) { _ in
            expectation.fulfill()
        }
        wait()
        
        // Expect the image to be downloaded and displayed
        XCTAssertNotNil(imageView.image)
    }
    
    func testLoadImageWithNilRequest() {
        // WHEN
        imageView.image = Test.image
        
        let expectation = self.expectation(description: "Image loaded")
        let request: ImageRequest? = nil
        NukeExtensions.loadImage(with: request, into: imageView) {
            XCTAssertEqual($0.error, .imageRequestMissing)
            expectation.fulfill()
        }
        wait()
        
        // THEN
        XCTAssertNil(imageView.image)
    }
    
    func testLoadImageWithNilRequestAndPlaceholder() {
        // GIVEN
        let failureImage = Test.image
        
        // WHEN
        let options = ImageLoadingOptions(failureImage: failureImage)
        let request: ImageRequest? = nil
        NukeExtensions.loadImage(with: request, options: options, into: imageView)
        
        // THEN failure image is displayed
        XCTAssertTrue(imageView.image === failureImage)
    }
    
    // MARK: - Managing Tasks
    
    func testTaskReturned() {
        // When requesting an image
        let task = NukeExtensions.loadImage(with: Test.request, into: imageView)
        
        // Expect Nuke to return a task
        XCTAssertNotNil(task)
        
        // Expect the task's request to be equivalent to the one provided
        XCTAssertEqual(task?.request.urlRequest, Test.request.urlRequest)
    }
    
    func testTaskIsNilWhenImageInMemoryCache() {
        // When the requested image is stored in memory cache
        let request = Test.request
        imageCache[request] = ImageContainer(image: PlatformImage())
        
        // When requesting an image
        let task = NukeExtensions.loadImage(with: request, into: imageView)
        
        // Expect Nuke to not return any tasks
        XCTAssertNil(task)
    }
    
    // MARK: - Prepare For Reuse
    
    func testViewPreparedForReuse() {
        // Given an image view displaying an image
        imageView.image = Test.image
        
        // When requesting the new image
        NukeExtensions.loadImage(with: Test.request, into: imageView)
        
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
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)
        
        // Expect the original image to still be displayed
        XCTAssertEqual(imageView.image, image)
    }
    
    // MARK: - Memory Cache
    
    func testMemoryCacheUsed() {
        // Given the requested image stored in memory cache
        let image = Test.image
        imageCache[Test.request] = ImageContainer(image: image)
        
        // When requesting the new image
        NukeExtensions.loadImage(with: Test.request, into: imageView)
        
        // Expect image to be displayed immediately
        XCTAssertEqual(imageView.image, image)
    }
    
    func testMemoryCacheDisabled() {
        // Given the requested image stored in memory cache
        imageCache[Test.request] = Test.container
        
        // When requesting the image with memory cache read disabled
        var request = Test.request
        request.options.insert(.disableMemoryCacheReads)
        NukeExtensions.loadImage(with: request, into: imageView)
        
        // Expect image to not be displayed, loaded asyncrounously instead
        XCTAssertNil(imageView.image)
    }
    
    // MARK: - Completion and Progress Closures
    
    func testCompletionCalled() {
        var didCallCompletion = false
        let expectation = self.expectation(description: "Image loaded")
        NukeExtensions.loadImage(
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
        // GIVEN the requested image stored in memory cache
        imageCache[Test.request] = Test.container
        
        var didCallCompletion = false
        NukeExtensions.loadImage(
            with: Test.request,
            into: imageView,
            completion: { result in
                // Expect completion to be called synchronously on the main thread
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(result.isSuccess)
                didCallCompletion = true
            }
        )
        XCTAssertTrue(didCallCompletion)
    }
    
    func testProgressHandlerCalled() {
        // GIVEN
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )
        
        let expectedProgress = expectProgress([(10, 20), (20, 20)])
        
        // WHEN loading an image into a view
        NukeExtensions.loadImage(
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
        dataLoader.isSuspended = true
        
        // Given an image view with an associated image task
        expectNotification(ImagePipelineObserver.didStartTask, object: observer)
        NukeExtensions.loadImage(with: Test.url, into: imageView)
        wait()
        
        // Expect the task to get cancelled
        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
        
        // When asking Nuke to cancel the request for the view
        NukeExtensions.cancelRequest(for: imageView)
        wait()
    }
    
    func testRequestCancelledWhenNewRequestStarted() {
        dataLoader.isSuspended = true
        
        // Given an image view with an associated image task
        expectNotification(ImagePipelineObserver.didStartTask, object: observer)
        NukeExtensions.loadImage(with: Test.url, into: imageView)
        wait()
        
        // When starting loading a new image
        // Expect previous task to get cancelled
        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
        NukeExtensions.loadImage(with: Test.url, into: imageView)
        wait()
    }
    
    func testRequestCancelledWhenTargetGetsDeallocated() {
        dataLoader.isSuspended = true
        
        // Wrap everything in autorelease pool to make sure that imageView
        // gets deallocated immediately.
        autoreleasepool {
            // Given an image view with an associated image task
            var imageView: _ImageView! = _ImageView()
            expectNotification(ImagePipelineObserver.didStartTask, object: observer)
            NukeExtensions.loadImage(with: Test.url, into: imageView)
            wait()
            
            // Expect the task to be cancelled automatically
            expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
            
            // When the view is deallocated
            imageView = nil
        }
        wait()
    }
}

#endif
