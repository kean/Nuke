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
    var options = ImageLoadingOptions()
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

        options.pipeline = pipeline

        imageView = _ImageView()
    }

    // MARK: - Loading

    @Test func imageLoaded() async throws {
        // When
        try await loadImage(with: Test.request, options: options, into: imageView)

        // Expect the image to be downloaded and displayed
        #expect(imageView.image != nil)
    }

#if os(tvOS)
    @Test func imageLoadedToTVPosterView() async throws {
        // Use local instance for this tvOS specific test for simplicity
        let posterView = TVPosterView()

        // When requesting an image with request
        try await loadImage(with: Test.request, options: options, into: posterView)

        // Expect the image to be downloaded and displayed
        #expect(posterView.image != nil)
    }
#endif

    @Test func imageLoadedWithURL() async throws {
        // When requesting an image with URL
        try await loadImage(with: Test.url, options: options, into: imageView)

        // Expect the image to be downloaded and displayed
        #expect(imageView.image != nil)
    }

    @Test func loadImageWithNilRequest() async throws {
        // When
        imageView.image = Test.image

        let request: ImageRequest? = nil
        do {
            try await loadImage(with: request, options: options, into: imageView)
            Issue.record()
        } catch {
            #expect(error == .imageRequestMissing)
        }

        // Then
        #expect(imageView.image == nil)
    }

    @Test func loadImageWithNilRequestAndPlaceholder() async throws {
        // Given
        let failureImage = Test.image
        options.failureImage = failureImage

        // When
        let request: ImageRequest? = nil
        do {
            try await loadImage(with: request, options: options, into: imageView)
            Issue.record()
        } catch {
            #expect(error == .imageRequestMissing)
        }

        // Then failure image is displayed
        #expect(imageView.image === failureImage)
    }

//    // MARK: - Managing Tasks
//
    @Test func taskReturned() {
        // When requesting an image
        let task = NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)

        // Expect Nuke to return a task
        #expect(task != nil)

        // Expect the task's request to be equivalent to the one provided
        #expect(task?.request.urlRequest == Test.request.urlRequest)
    }

    @Test func taskIsNilWhenImageInMemoryCache() {
        // When the requested image is stored in memory cache
        let request = Test.request
        imageCache[request] = ImageContainer(image: PlatformImage())

        // When requesting an image
        let task = NukeExtensions.loadImage(with: request, options: options, into: imageView)

        // Expect Nuke to not return any tasks
        #expect(task == nil)
    }

    // MARK: - Prepare For Reuse

    @Test func viewPreparedForReuse() {
        // Given an image view displaying an image
        imageView.image = Test.image

        // When requesting the new image
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image == nil)
    }

    @Test func viewPreparedForReuseDisabled() {
        // Given an image view displaying an image
        let image = Test.image
        imageView.image = image

        // When requesting the new image with prepare for reuse disabled
        options.isPrepareForReuseEnabled = false
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)

        // Expect the original image to still be displayed
        #expect(imageView.image == image)
    }

    // MARK: - Memory Cache

    @Test func memoryCacheUsed() {
        // Given the requested image stored in memory cache
        let image = Test.image
        imageCache[Test.request] = ImageContainer(image: image)

        // When requesting the new image
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)

        // Expect image to be displayed immediately
        #expect(imageView.image == image)
    }

    @Test func memoryCacheDisabled() {
        // Given the requested image stored in memory cache
        imageCache[Test.request] = Test.container

        // When requesting the image with memory cache read disabled
        var request = Test.request
        request.options.insert(.disableMemoryCacheReads)
        NukeExtensions.loadImage(with: request, options: options, into: imageView)

        // Expect image to not be displayed, loaded asyncrounously instead
        #expect(imageView.image == nil)
    }

    // MARK: - Completion and Progress Closures

    @Test func completionCalled() async {
        // When
        var didCallCompletion = false
        let expectation = AsyncExpectation<Void>()

        NukeExtensions.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            completion: { result in
                // Expect completion to be called  on the main thread
                #expect(Thread.isMainThread)
                #expect(result.isSuccess)
                didCallCompletion = true
                expectation.fulfill()
            }
        )

        // Then expect completion to be called asynchronously
        #expect(!didCallCompletion)
        await expectation.wait()
    }

    @Test func completionCalledImageFromCache() {
        // Given the requested image stored in memory cache
        imageCache[Test.request] = Test.container

        var didCallCompletion = false
        NukeExtensions.loadImage(
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
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        var progress: [(Int64, Int64)] = []

        // When loading an image into a view
        _ = await withUnsafeContinuation { continuation in
            NukeExtensions.loadImage(
                with: Test.request,
                options: options,
                into: imageView,
                progress: { _, completed, total in
                    // Expect progress to be reported, on the main thread
                    #expect(Thread.isMainThread)
                    progress.append((completed, total))
                }, completion: { _ in
                    continuation.resume()
                }
            )
        }

        // Then
        #expect(progress.map(\.0) == [10, 20])
        #expect(progress.map(\.1) == [20, 20])
    }

    // MARK: - Cancellation

    @MainActor
    @Test func requestCancelled() async {
        dataLoader.isSuspended = true

        // Given an image view with an associated image task
        let expectation1 = expect(notification: ImagePipelineObserver.didCreateTask, object: observer)
        Task {
            try? await loadImage(with: Test.url, options: options, into: imageView)
        }
        await expectation1.wait()

        // Expect the task to get cancelled
        // When asking Nuke to cancel the request for the view
        let expectation2 = expect(notification: ImagePipelineObserver.didCancelTask, object: observer)
        cancelRequest(for: imageView)
        await expectation2.wait()
    }

    @Test func requestCancelledWhenNewRequestStarted() async {
        dataLoader.isSuspended = true

        // Given an image view with an associated image task
        let expectation1 = expect(notification: ImagePipelineObserver.didCreateTask, object: observer)
        Task { @MainActor in
            try? await loadImage(with: Test.url, options: options, into: imageView)
        }
        await expectation1.wait()
        expectation1.invalidate()

        // When starting loading a new image
        // Expect previous task to get cancelled
        let expectation2 = expect(notification: ImagePipelineObserver.didCancelTask, object: observer)
        Task { @MainActor in
            try? await loadImage(with: Test.url, options: options, into: imageView)
        }
        await expectation2.wait()
    }
}

#endif
