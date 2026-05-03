// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite(.timeLimit(.minutes(5))) @MainActor
struct LazyImageViewTests {
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let observer: ImagePipelineObserver
    let pipeline: ImagePipeline
    var view: LazyImageView

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let observer = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.observer = observer
        self.pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = MockDataCache()
        }
        self.view = LazyImageView()
        self.view.pipeline = pipeline
        // Disable the default fade-in transition to keep assertions deterministic.
        self.view.transition = nil
    }

    // MARK: - Loading

    @Test func imageLoadedViaURL() async {
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }

        view.url = Test.url
        await expectation.wait()

        #expect(view.imageView.image != nil)
        #expect(view.imageView.isHidden == false)
    }

    @Test func imageLoadedViaRequest() async {
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }

        view.request = Test.request
        await expectation.wait()

        #expect(view.imageView.image != nil)
    }

    @Test func nilRequestProducesFailure() async throws {
        var capturedError: Error?
        let expectation = TestExpectation()
        view.onCompletion = { result in
            if case .failure(let error) = result {
                capturedError = error
            }
            expectation.fulfill()
        }

        view.request = nil
        await expectation.wait()

        let error = try #require(capturedError as? ImagePipeline.Error)
        #expect(error == .imageRequestMissing)
        #expect(view.imageView.image == nil)
    }

    @Test func underlyingImageViewIsHiddenBeforeLoad() {
        #expect(view.imageView.isHidden)
        #expect(view.imageView.image == nil)
    }

    @Test func urlPropertyReflectsRequest() {
        view.url = Test.url
        #expect(view.url == Test.url)
        #expect(view.request?.url == Test.url)
    }

    // MARK: - Memory Cache

    @Test func memoryCacheHitDisplaysImageSynchronously() {
        pipeline.cache[Test.request] = Test.container

        view.request = Test.request

        #expect(view.imageView.image != nil)
        #expect(view.imageView.isHidden == false)
        #expect(view.imageTask == nil)
    }

    @Test func memoryCacheHitReportsCacheTypeMemory() throws {
        pipeline.cache[Test.request] = Test.container

        var capturedResponse: ImageResponse?
        view.onSuccess = { capturedResponse = $0 }

        view.request = Test.request

        let response = try #require(capturedResponse)
        #expect(response.cacheType == .memory)
    }

    @Test func memoryCachePreviewDisplayedThenFinalImage() async {
        let preview = ImageContainer(image: Test.image, isPreview: true)
        pipeline.cache[Test.request] = preview

        // Preview is displayed synchronously.
        view.request = Test.request
        #expect(view.imageView.image != nil)

        // The pipeline still completes a real load for the final image.
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        await expectation.wait()
        #expect(view.imageView.image != nil)
    }

    // MARK: - Callbacks

    @Test func onStartCalled() async throws {
        dataLoader.isSuspended = true

        let expectation = TestExpectation()
        var capturedTask: ImageTask?
        view.onStart = { task in
            capturedTask = task
            expectation.fulfill()
        }

        view.url = Test.url
        await expectation.wait()

        let task = try #require(capturedTask)
        #expect(view.imageTask === task)
    }

    @Test func onSuccessCalled() async throws {
        let expectation = TestExpectation()
        var capturedResponse: ImageResponse?
        view.onSuccess = { response in
            capturedResponse = response
            expectation.fulfill()
        }

        view.url = Test.url
        await expectation.wait()

        _ = try #require(capturedResponse)
    }

    @Test func onCompletionCalledOnSuccess() async throws {
        let expectation = TestExpectation()
        var capturedResult: Result<ImageResponse, Error>?
        view.onCompletion = { result in
            capturedResult = result
            expectation.fulfill()
        }

        view.url = Test.url
        await expectation.wait()

        let result = try #require(capturedResult)
        #expect(result.isSuccess)
    }

    @Test func onFailureCalled() async throws {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        let expectation = TestExpectation()
        var capturedError: Error?
        view.onFailure = { error in
            capturedError = error
            expectation.fulfill()
        }

        view.url = Test.url
        await expectation.wait()

        _ = try #require(capturedError)
    }

    @Test func onCompletionCalledOnFailure() async throws {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        let expectation = TestExpectation()
        var capturedResult: Result<ImageResponse, Error>?
        view.onCompletion = { result in
            capturedResult = result
            expectation.fulfill()
        }

        view.url = Test.url
        await expectation.wait()

        let result = try #require(capturedResult)
        #expect(result.isFailure)
    }

    @Test func onProgressCalled() async {
        dataLoader.results[Test.url] = .success((
            Data(count: 20),
            URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil)
        ))

        var progressValues: [(Int64, Int64)] = []
        let expectation = TestExpectation()
        view.onProgress = { progress in
            progressValues.append((progress.completed, progress.total))
        }
        view.onCompletion = { _ in expectation.fulfill() }

        view.url = Test.url
        await expectation.wait()

        #expect(progressValues.count == 2)
        #expect(progressValues.first?.0 == 10)
        #expect(progressValues.first?.1 == 20)
        #expect(progressValues.last?.0 == 20)
    }

    // MARK: - Placeholder

    @Test func placeholderViewVisibleDuringLoad() async {
        dataLoader.isSuspended = true

        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        let startExpectation = TestExpectation()
        view.onStart = { _ in startExpectation.fulfill() }
        view.url = Test.url
        await startExpectation.wait()

        #expect(placeholder.isHidden == false)
    }

    @Test func placeholderHiddenAfterSuccess() async {
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(placeholder.isHidden == true)
    }

    @Test func placeholderHiddenAfterFailureByDefault() async {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(placeholder.isHidden == true)
    }

    @Test func showPlaceholderOnFailureKeepsPlaceholderVisible() async {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        view.showPlaceholderOnFailure = true

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(placeholder.isHidden == false)
    }

    @Test func placeholderImageWrapsInImageView() {
        view.placeholderImage = Test.image
        #expect(view.placeholderView is _PlatformImageView)
    }

    @Test func clearingPlaceholderImageRemovesPlaceholderView() {
        view.placeholderImage = Test.image
        #expect(view.placeholderView != nil)

        view.placeholderImage = nil
        #expect(view.placeholderView == nil)
    }

    @Test func placeholderViewAddedAsSubview() {
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        #expect(placeholder.superview === view)
    }

    @Test func replacingPlaceholderViewRemovesOld() {
        let first = _PlatformBaseView()
        view.placeholderView = first
        #expect(first.superview === view)

        let second = _PlatformBaseView()
        view.placeholderView = second
        #expect(first.superview == nil)
        #expect(second.superview === view)
    }

    // MARK: - Failure View

    @Test func failureViewHiddenInitially() {
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        #expect(failureView.isHidden == true)
    }

    @Test func failureViewShownOnFailure() async {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        let failureView = _PlatformBaseView()
        view.failureView = failureView

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(failureView.isHidden == false)
    }

    @Test func failureViewHiddenAfterSuccess() async {
        let failureView = _PlatformBaseView()
        view.failureView = failureView

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(failureView.isHidden == true)
    }

    @Test func failureImageWrapsInImageView() {
        view.failureImage = Test.image
        #expect(view.failureView is _PlatformImageView)
    }

    @Test func clearingFailureImageRemovesFailureView() {
        view.failureImage = Test.image
        #expect(view.failureView != nil)

        view.failureImage = nil
        #expect(view.failureView == nil)
    }

    // MARK: - Cancellation

    @Test func cancelClearsImageTask() async {
        dataLoader.isSuspended = true

        let startExp = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        view.url = Test.url
        await startExp.wait()

        #expect(view.imageTask != nil)

        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            view.cancel()
        }
        #expect(view.imageTask == nil)
    }

    @Test func resetCancelsAndClearsImage() async {
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(view.imageView.image != nil)
        #expect(view.imageView.isHidden == false)

        view.reset()

        #expect(view.imageView.image == nil)
        #expect(view.imageView.isHidden == true)
        #expect(view.imageTask == nil)
    }

    @Test func newRequestCancelsPreviousTask() async {
        dataLoader.isSuspended = true

        let startExp = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        view.url = Test.url
        await startExp.wait()

        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            view.url = URL(string: "https://example.com/other.jpg")!
        }
    }

    @Test func viewDeallocCancelsTask() async {
        dataLoader.isSuspended = true

        var localView: LazyImageView? = LazyImageView()
        localView?.pipeline = pipeline

        let startExp = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        localView?.url = Test.url
        await startExp.wait()

        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            localView = nil
        }
    }

    // MARK: - Priority

    @Test func priorityAppliedOnStart() async {
        dataLoader.isSuspended = true
        view.priority = .high

        let startExp = TestExpectation()
        view.onStart = { _ in startExp.fulfill() }
        view.url = Test.url
        await startExp.wait()

        #expect(view.imageTask?.priority == .high)
    }

    @Test func priorityChangedDynamically() async {
        dataLoader.isSuspended = true

        let startExp = TestExpectation()
        view.onStart = { _ in startExp.fulfill() }
        view.url = Test.url
        await startExp.wait()

        let task = view.imageTask
        view.priority = .high
        #expect(task?.priority == .high)
    }

    // MARK: - Pipeline

    @Test func customPipelineUsed() async {
        let customDataLoader = MockDataLoader()
        let customPipeline = ImagePipeline {
            $0.dataLoader = customDataLoader
            $0.imageCache = nil
        }
        view.pipeline = customPipeline

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(customDataLoader.createdTaskCount == 1)
        #expect(self.dataLoader.createdTaskCount == 0)
    }

    // MARK: - Processors

    @Test func processorsAppliedFromView() async {
        view.processors = [MockImageProcessor(id: "p1")]

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(view.imageView.image?.nk_test_processorIDs == ["p1"])
    }

    @Test func processorsFromRequestTakePrecedenceOverViewProcessors() async {
        view.processors = [MockImageProcessor(id: "p1")]

        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p2")])
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.request = request
        await expectation.wait()

        #expect(view.imageView.image?.nk_test_processorIDs == ["p2"])
    }

    // MARK: - Transition

    @Test func customTransitionRunOnSuccess() async {
        let transitionExpectation = TestExpectation()
        view.transition = .custom { v, _ in
            #expect(v === self.view)
            transitionExpectation.fulfill()
        }

        let completionExpectation = TestExpectation()
        view.onCompletion = { _ in completionExpectation.fulfill() }
        view.url = Test.url
        await completionExpectation.wait()
        await transitionExpectation.wait()
    }

    @Test func transitionNotRunFromMemoryCache() {
        pipeline.cache[Test.request] = Test.container

        var transitionRun = false
        view.transition = .custom { _, _ in transitionRun = true }
        view.request = Test.request

        #expect(transitionRun == false)
        #expect(view.imageView.image != nil)
    }

    @Test func transitionNilProducesNoTransition() async {
        view.transition = nil

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(view.imageView.image != nil)
    }

    // MARK: - Custom Image View

    @Test func makeImageViewUsedForCustomView() async {
        let customView = _PlatformBaseView()
        view.makeImageView = { _ in customView }

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(customView.superview === view)
        // The default image view stays unused.
        #expect(view.imageView.image == nil)
    }

    @Test func makeImageViewReturningNilFallsBackToDefault() async {
        view.makeImageView = { _ in nil }

        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        #expect(view.imageView.image != nil)
    }

    // MARK: - Reset Behavior

    @Test func isResetEnabledFalseKeepsImageDuringLoad() async {
        // Load an initial image.
        let firstExp = TestExpectation()
        view.onCompletion = { _ in firstExp.fulfill() }
        view.url = Test.url
        await firstExp.wait()

        let firstImage = view.imageView.image
        #expect(firstImage != nil)

        // Start a second request with reset disabled.
        view.isResetEnabled = false
        view.onCompletion = nil

        dataLoader.isSuspended = true
        let startExp = TestExpectation()
        view.onStart = { _ in startExp.fulfill() }
        view.url = URL(string: "https://example.com/other.jpg")!
        await startExp.wait()

        // Previous image is still displayed.
        #expect(view.imageView.image === firstImage)
        #expect(view.imageView.isHidden == false)
    }

    @Test func isResetEnabledFalseAppliesDeferredResetWhenNewImageReady() async {
        // Load an initial image.
        let firstExp = TestExpectation()
        view.onCompletion = { _ in firstExp.fulfill() }
        view.url = Test.url
        await firstExp.wait()

        let firstImage = view.imageView.image

        // Start a second request with reset disabled.
        view.isResetEnabled = false

        let secondExp = TestExpectation()
        view.onCompletion = { _ in secondExp.fulfill() }
        view.url = URL(string: "https://example.com/other.jpg")!
        await secondExp.wait()

        // The image was replaced with the new one.
        #expect(view.imageView.image != nil)
        #expect(view.imageView.image !== firstImage)
    }
}

#endif
