// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

#if os(tvOS)
import TVUIKit
#endif

@testable import Nuke
@testable import NukeExtensions

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@MainActor
@Suite class ImageViewExtensionsTests {
    var imageView: _ImageView!
    var observer: ImagePipelineObserver!
    var imageCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    init() {
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

    deinit {
        MainActor.assumeIsolated {
            ImagePipeline.popShared()
        }
    }

    // MARK: - Loading

    @Test func imageLoaded() async throws {
        // When requesting an image with request
        try await NukeExtensions.loadImage(with: Test.request, into: imageView)

        // Expect the image to be downloaded and displayed
        #expect(imageView.image != nil)
    }

//#if os(tvOS)
//    @Test func imageLoadedToTVPosterView() {
//        // Use local instance for this tvOS specific test for simplicity
//        let posterView = TVPosterView()
//
//        // When requesting an image with request
//        expectToLoadImage(with: Test.request, into: posterView)
//        wait()
//
//        // Expect the image to be downloaded and displayed
//        #expect(posterView.image != nil)
//    }
//#endif
//
//    @Test func imageLoadedWithURL() {
//        // When requesting an image with URL
//        let expectation = self.expectation(description: "Image loaded")
//        NukeExtensions.loadImage(with: Test.url, into: imageView) { _ in
//            expectation.fulfill()
//        }
//        wait()
//
//        // Expect the image to be downloaded and displayed
//        #expect(imageView.image != nil)
//    }
//
//    @Test func loadImageWithNilRequest() {
//        // When
//        imageView.image = Test.image
//
//        let expectation = self.expectation(description: "Image loaded")
//        let request: ImageRequest? = nil
//        NukeExtensions.loadImage(with: request, into: imageView) {
//            #expect($0.error == .imageRequestMissing)
//            expectation.fulfill()
//        }
//        wait()
//
//        // Then
//        #expect(imageView.image == nil)
//    }
//
//    @Test func loadImageWithNilRequestAndPlaceholder() {
//        // Given
//        let failureImage = Test.image
//
//        // When
//        let options = ImageLoadingOptions(failureImage: failureImage)
//        let request: ImageRequest? = nil
//        NukeExtensions.loadImage(with: request, options: options, into: imageView)
//
//        // Then failure image is displayed
//        #expect(imageView.image === failureImage)
//    }
//
//    // MARK: - Managing Tasks
//
//    @Test func taskReturned() {
//        // When requesting an image
//        let task = NukeExtensions.loadImage(with: Test.request, into: imageView)
//
//        // Expect Nuke to return a task
//        #expect(task != nil)
//
//        // Expect the task's request to be equivalent to the one provided
//        #expect(task?.request.urlRequest == Test.request.urlRequest)
//    }
//
//    @Test func taskIsNilWhenImageInMemoryCache() {
//        // When the requested image is stored in memory cache
//        let request = Test.request
//        imageCache[request] = ImageContainer(image: PlatformImage())
//
//        // When requesting an image
//        let task = NukeExtensions.loadImage(with: request, into: imageView)
//
//        // Expect Nuke to not return any tasks
//        #expect(task == nil)
//    }
//
//    // MARK: - Prepare For Reuse
//
//    @Test func viewPreparedForReuse() {
//        // Given an image view displaying an image
//        imageView.image = Test.image
//
//        // When requesting the new image
//        NukeExtensions.loadImage(with: Test.request, into: imageView)
//
//        // Then
//        #expect(imageView.image == nil)
//    }
//
//    @Test func viewPreparedForReuseDisabled() {
//        // Given an image view displaying an image
//        let image = Test.image
//        imageView.image = image
//
//        // When requesting the new image with prepare for reuse disabled
//        var options = ImageLoadingOptions()
//        options.isPrepareForReuseEnabled = false
//        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)
//
//        // Expect the original image to still be displayed
//        #expect(imageView.image == image)
//    }
//
//    // MARK: - Memory Cache
//
//    @Test func memoryCacheUsed() {
//        // Given the requested image stored in memory cache
//        let image = Test.image
//        imageCache[Test.request] = ImageContainer(image: image)
//
//        // When requesting the new image
//        NukeExtensions.loadImage(with: Test.request, into: imageView)
//
//        // Expect image to be displayed immediately
//        #expect(imageView.image == image)
//    }
//
//    @Test func memoryCacheDisabled() {
//        // Given the requested image stored in memory cache
//        imageCache[Test.request] = Test.container
//
//        // When requesting the image with memory cache read disabled
//        var request = Test.request
//        request.options.insert(.disableMemoryCacheReads)
//        NukeExtensions.loadImage(with: request, into: imageView)
//
//        // Expect image to not be displayed, loaded asyncrounously instead
//        #expect(imageView.image == nil)
//    }
//
//    // MARK: - Completion and Progress Closures
//
//    @Test func completionCalled() {
//        var didCallCompletion = false
//        let expectation = self.expectation(description: "Image loaded")
//        NukeExtensions.loadImage(
//            with: Test.request,
//            into: imageView,
//            completion: { result in
//                // Expect completion to be called  on the main thread
//                #expect(Thread.isMainThread)
//                #expect(result.isSuccess)
//                didCallCompletion = true
//                expectation.fulfill()
//            }
//        )
//
//        // Expect completion to be called asynchronously
//        #expect(!didCallCompletion)
//        wait()
//    }
//
//    @Test func completionCalledImageFromCache() {
//        // Given the requested image stored in memory cache
//        imageCache[Test.request] = Test.container
//
//        var didCallCompletion = false
//        NukeExtensions.loadImage(
//            with: Test.request,
//            into: imageView,
//            completion: { result in
//                // Expect completion to be called synchronously on the main thread
//                #expect(Thread.isMainThread)
//                #expect(result.isSuccess)
//                didCallCompletion = true
//            }
//        )
//        #expect(didCallCompletion)
//    }
//
//    @Test func progressHandlerCalled() {
//        // Given
//        dataLoader.results[Test.url] = .success(
//            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
//        )
//
//        let expectedProgress = expectProgress([(10, 20), (20, 20)])
//
//        // When loading an image into a view
//        NukeExtensions.loadImage(
//            with: Test.request,
//            into: imageView,
//            progress: { _, completed, total in
//                // Expect progress to be reported, on the main thread
//                #expect(Thread.isMainThread)
//                expectedProgress.received((completed, total))
//            }
//        )
//
//        wait()
//    }
//
//    // MARK: - Cancellation
//
//    @Test func requestCancelled() {
//        dataLoader.isSuspended = true
//
//        // Given an image view with an associated image task
//        expectNotification(ImagePipelineObserver.didCreateTask, object: observer)
//        NukeExtensions.loadImage(with: Test.url, into: imageView)
//        wait()
//
//        // Expect the task to get cancelled
//        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
//
//        // When asking Nuke to cancel the request for the view
//        NukeExtensions.cancelRequest(for: imageView)
//        wait()
//    }
//
//    @Test func requestCancelledWhenNewRequestStarted() {
//        dataLoader.isSuspended = true
//
//        // Given an image view with an associated image task
//        expectNotification(ImagePipelineObserver.didCreateTask, object: observer)
//        NukeExtensions.loadImage(with: Test.url, into: imageView)
//        wait()
//
//        // When starting loading a new image
//        // Expect previous task to get cancelled
//        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
//        NukeExtensions.loadImage(with: Test.url, into: imageView)
//        wait()
//    }
//
//    @Test  func requestCancelledWhenTargetGetsDeallocated() {
//        dataLoader.isSuspended = true
//
//        // Wrap everything in autorelease pool to make sure that imageView
//        // gets deallocated immediately.
//        autoreleasepool {
//            // Given an image view with an associated image task
//            var imageView: _ImageView! = _ImageView()
//            expectNotification(ImagePipelineObserver.didCreateTask, object: observer)
//            NukeExtensions.loadImage(with: Test.url, into: imageView)
//            wait()
//
//            // Expect the task to be cancelled automatically
//            expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
//
//            // When the view is deallocated
//            imageView = nil
//        }
//        wait()
//    }
}

#endif
