// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
#if os(tvOS)
import TVUIKit
#endif
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageViewExtensionsTests {
    let imageView: _ImageView
    let observer: ImagePipelineObserver
    let imageCache: MockImageCache
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline
    let options: ImageLoadingOptions

    init() {
        let imageCache = MockImageCache()
        let dataLoader = MockDataLoader()
        let observer = ImagePipelineObserver()
        self.imageCache = imageCache
        self.dataLoader = dataLoader
        self.observer = observer
        self.pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
        self.imageView = _ImageView()
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        self.options = options
    }

    // MARK: - Loading

    @Test func imageLoaded() async {
        await loadImageExpectingSuccess(with: Test.request, options: options, into: imageView)
        #expect(imageView.image != nil)
    }

#if os(tvOS)
    @Test func imageLoadedToTVPosterView() async {
        let posterView = TVPosterView()
        await loadImageExpectingSuccess(with: Test.request, options: options, into: posterView)
        #expect(posterView.image != nil)
    }
#endif

    @Test func imageLoadedWithURL() async {
        let expectation = TestExpectation()
        NukeUI.loadImage(with: Test.url, options: options, into: imageView) { _ in
            expectation.fulfill()
        }
        await expectation.wait()
        #expect(imageView.image != nil)
    }

    @Test func loadImageWithNilRequest() async {
        imageView.image = Test.image

        let expectation = TestExpectation()
        let request: ImageRequest? = nil
        NukeUI.loadImage(with: request, options: options, into: imageView) {
            #expect($0.error == .imageRequestMissing)
            expectation.fulfill()
        }
        await expectation.wait()
        #expect(imageView.image == nil)
    }

    @Test func loadImageWithNilRequestAndPlaceholder() {
        let failureImage = Test.image
        var options = options
        options.failureImage = failureImage
        let request: ImageRequest? = nil
        NukeUI.loadImage(with: request, options: options, into: imageView)
        #expect(imageView.image === failureImage)
    }

    // MARK: - Managing Tasks

    @Test func taskReturned() {
        let task = NukeUI.loadImage(with: Test.request, options: options, into: imageView)
        #expect(task != nil)
        #expect(task?.request.urlRequest == Test.request.urlRequest)
    }

    @Test func taskIsNilWhenImageInMemoryCache() {
        let request = Test.request
        imageCache[request] = ImageContainer(image: PlatformImage())
        let task = NukeUI.loadImage(with: request, options: options, into: imageView)
        #expect(task == nil)
    }

    // MARK: - Prepare For Reuse

    @Test func viewPreparedForReuse() {
        imageView.image = Test.image
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)
        #expect(imageView.image == nil)
    }

    @Test func viewPreparedForReuseDisabled() {
        let image = Test.image
        imageView.image = image
        var options = options
        options.isPrepareForReuseEnabled = false
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)
        #expect(imageView.image == image)
    }

    // MARK: - Memory Cache

    @Test func memoryCacheUsed() {
        let image = Test.image
        imageCache[Test.request] = ImageContainer(image: image)
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)
        #expect(imageView.image == image)
    }

    @Test func memoryCacheDisabled() {
        imageCache[Test.request] = Test.container
        var request = Test.request
        request.options.insert(.disableMemoryCacheReads)
        NukeUI.loadImage(with: request, options: options, into: imageView)
        #expect(imageView.image == nil)
    }

    // MARK: - Completion and Progress Closures

    @Test func completionCalled() async {
        var didCallCompletion = false
        let expectation = TestExpectation()
        NukeUI.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            completion: { result in
                #expect(Thread.isMainThread)
                #expect(result.isSuccess)
                didCallCompletion = true
                expectation.fulfill()
            }
        )

        // Expect completion to be called asynchronously
        #expect(!didCallCompletion)
        await expectation.wait()
    }

    @Test func completionCalledImageFromCache() {
        // GIVEN the requested image stored in memory cache
        imageCache[Test.request] = Test.container

        var didCallCompletion = false
        NukeUI.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            completion: { result in
                // Expect completion to be called synchronously on the main thread
                #expect(Thread.isMainThread)
                #expect(result.isSuccess)
                didCallCompletion = true
            }
        )
        #expect(didCallCompletion)
    }

    @Test func progressHandlerCalled() async {
        // GIVEN
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        var progressValues: [(Int64, Int64)] = []
        let expectation = TestExpectation()

        // WHEN loading an image into a view
        NukeUI.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            progress: { _, completed, total in
                // Expect progress to be reported, on the main thread
                #expect(Thread.isMainThread)
                progressValues.append((completed, total))
            },
            completion: { _ in
                expectation.fulfill()
            }
        )

        await expectation.wait()
        #expect(progressValues.count == 2)
        #expect(progressValues[0] == (10, 20))
        #expect(progressValues[1] == (20, 20))
    }

    // MARK: - Cancellation

    @Test func requestCancelled() async {
        dataLoader.isSuspended = true

        // Given an image view with an associated image task
        let startExpectation = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        NukeUI.loadImage(with: Test.url, options: options, into: imageView)
        await startExpectation.wait()

        // Expect the task to get cancelled
        // When asking Nuke to cancel the request for the view
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            NukeUI.cancelRequest(for: imageView)
        }
    }

    @Test func requestCancelledWhenNewRequestStarted() async {
        dataLoader.isSuspended = true

        // Given an image view with an associated image task
        let startExpectation = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        NukeUI.loadImage(with: Test.url, options: options, into: imageView)
        await startExpectation.wait()

        // When starting loading a new image
        // Expect previous task to get cancelled
        let cancelExpectation = TestExpectation(notification: ImagePipelineObserver.didCancelTask, object: observer)
        NukeUI.loadImage(with: Test.url, options: options, into: imageView)
        await cancelExpectation.wait()
    }

    @Test func requestCancelledWhenTargetGetsDeallocated() async {
        dataLoader.isSuspended = true

        // Wrap everything in autorelease pool to make sure that imageView
        // gets deallocated immediately.
        var localImageView: _ImageView? = _ImageView()
        let startExpectation = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        NukeUI.loadImage(with: Test.url, options: options, into: localImageView!)
        await startExpectation.wait()

        // Expect the task to be cancelled automatically
        // When the view is deallocated
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            localImageView = nil
        }
    }

    // MARK: - ImageDisplaying

    @Test func subclassOverridesDisplay() async {
        // GIVEN a subclass that overrides the built-in `UIImageView` conformance,
        // which is only possible because the conformance is exposed to the
        // Objective-C runtime
        let imageView = MockSubclassedImageView()

        // WHEN
        await loadImageExpectingSuccess(with: Test.request, options: options, into: imageView)

        // THEN the override runs instead of the built-in implementation
        #expect(imageView.lastDisplayedImage != nil)
        #expect(imageView.image == nil)
    }

    @Test func displayKeepsPrefixedSelector() {
        // The selector is unchanged since Nuke 8 so that the Objective-C
        // subclasses that override it keep working
        let selector = #selector(_ImageView.display(image:data:))
        #expect(NSStringFromSelector(selector) == "nuke_displayWithImage:data:")
    }
}

private final class MockSubclassedImageView: _ImageView {
    var lastDisplayedImage: PlatformImage?

    override func display(image: PlatformImage?, data: Data?) {
        lastDisplayedImage = image
    }
}

#endif
