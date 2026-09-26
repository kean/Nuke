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

/// Covers the order and timing of the `LazyImageView` callbacks, what the view
/// shows in each state, and how it behaves when a request is replaced,
/// cancelled, or outlived by the view.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct LazyImageViewLifecycleTests {
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let observer: ImagePipelineObserver
    let pipeline: ImagePipeline
    let view: LazyImageView

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

    // MARK: - Defaults

    @Test func defaultConfiguration() throws {
        let view = LazyImageView()

        guard case .fadeIn(let duration)? = view.transition else {
            Issue.record("Expected the default fade-in transition")
            return
        }
        #expect(duration == 0.33)
        #expect(view.placeholderViewPosition == .fill)
        #expect(view.failureViewPosition == .fill)
        #expect(!view.showPlaceholderOnFailure)
        #expect(view.isProgressiveImageRenderingEnabled)
        #expect(view.isResetEnabled)
        #expect(view.priority == nil)
        #expect(view.processors == nil)
        #expect(view.request == nil)
        #expect(view.imageTask == nil)
        #expect(view.makeImageView == nil)
        #expect(view.placeholderImage == nil)
        #expect(view.failureImage == nil)
        #expect(view.failureView == nil)

        // The default placeholder is shown until there is an image to display.
        let placeholder = try #require(view.placeholderView)
        #expect(placeholder.superview === view)
        #expect(!placeholder.isHidden)
    }

    // MARK: - Callbacks

    @Test func successCallbacksAreDeliveredInOrder() async {
        // Given
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        var events: [String] = []
        view.onStart = { _ in events.append("start") }
        view.onProgress = { _ in events.append("progress") }
        view.onPreview = { _ in events.append("preview") }
        view.onFailure = { _ in events.append("failure") }
        view.onSuccess = { _ in
            events.append("success")
            // The image is on screen, and the task is over, by the time the
            // callbacks run.
            #expect(view.imageTask == nil)
            #expect(view.imageView.image != nil)
            #expect(!view.imageView.isHidden)
            #expect(placeholder.isHidden)
        }
        let expectation = TestExpectation()
        view.onCompletion = { _ in
            events.append("completion")
            expectation.fulfill()
        }

        // When
        view.url = Test.url
        await expectation.wait()

        // Then
        #expect(events.first == "start")
        #expect(events.suffix(2) == ["success", "completion"])
        #expect(events.dropFirst().dropLast(2).allSatisfy { $0 == "progress" })
    }

    @Test func failureCallbacksAreDeliveredInOrder() async {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        var events: [String] = []
        view.onStart = { _ in events.append("start") }
        view.onSuccess = { _ in events.append("success") }
        view.onFailure = { _ in
            events.append("failure")
            #expect(view.imageTask == nil)
            #expect(!failureView.isHidden)
            #expect(view.imageView.isHidden)
        }
        let expectation = TestExpectation()
        view.onCompletion = { _ in
            events.append("completion")
            expectation.fulfill()
        }

        // When
        view.url = Test.url
        await expectation.wait()

        // Then
        #expect(events == ["start", "failure", "completion"])
    }

    @Test func memoryCacheHitCompletesSynchronouslyWithoutStarting() {
        // Given
        imageCache[Test.request] = Test.container
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        var events: [String] = []
        view.onStart = { _ in events.append("start") }
        view.onSuccess = { _ in events.append("success") }
        view.onCompletion = { _ in events.append("completion") }

        // When
        view.request = Test.request

        // Then
        #expect(events == ["success", "completion"])
        #expect(placeholder.isHidden)
        #expect(failureView.isHidden)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func nilRequestFailsSynchronouslyWithoutStarting() {
        // Given
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        var events: [String] = []
        view.onStart = { _ in events.append("start") }
        view.onFailure = { _ in events.append("failure") }
        view.onCompletion = { _ in events.append("completion") }

        // When
        view.url = nil

        // Then
        #expect(events == ["failure", "completion"])
        #expect(!failureView.isHidden)
        #expect(placeholder.isHidden)
        #expect(view.imageTask == nil)
        #expect(dataLoader.createdTaskCount == 0)
    }

    /// Clearing the task before the callbacks are called is what lets a
    /// callback start the next request, e.g. a fallback image on failure.
    @Test func requestStartedFromCallbackBecomesTheCurrentTask() async throws {
        // Given
        let fallbackURL = URL(string: "https://example.com/fallback.jpg")!
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        var startedTasks: [ImageTask] = []
        view.onStart = { startedTasks.append($0) }
        let expectation = TestExpectation()
        view.onFailure = { _ in
            dataLoader.isSuspended = true
            view.url = fallbackURL
            expectation.fulfill()
        }

        // When
        view.url = Test.url
        await expectation.wait()

        // Then
        try #require(startedTasks.count == 2)
        let task = try #require(view.imageTask)
        #expect(task === startedTasks[1])
        #expect(task.request.url == fallbackURL)
        #expect(!task.isCancelled)
    }

    // MARK: - Transitions

    @Test func customTransitionRunsAfterImageIsDisplayedAndBeforeCallbacks() async {
        // Given
        var events: [String] = []
        view.transition = .custom { view, container in
            events.append("transition")
            #expect(view === self.view)
            #expect(view.imageView.image === container.image)
            #expect(!view.imageView.isHidden)
        }
        view.onSuccess = { _ in events.append("success") }
        let expectation = TestExpectation()
        view.onCompletion = { _ in
            events.append("completion")
            expectation.fulfill()
        }

        // When
        view.url = Test.url
        await expectation.wait()

        // Then
        #expect(events == ["transition", "success", "completion"])
    }

    @Test func customTransitionIsNotRunOnFailure() async {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        var isTransitionPerformed = false
        view.transition = .custom { _, _ in isTransitionPerformed = true }

        // When
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()

        // Then
        #expect(!isTransitionPerformed)
    }

    // MARK: - Custom Image View

    @Test func makeImageViewReceivesTheResponseAndItsViewFillsTheView() async throws {
        // Given
        let customView = _PlatformBaseView()
        var receivedContainer: ImageContainer?
        view.makeImageView = {
            receivedContainer = $0
            return customView
        }
        var response: ImageResponse?
        let expectation = TestExpectation()
        view.onSuccess = { response = $0 }
        view.onCompletion = { _ in expectation.fulfill() }

        // When
        view.url = Test.url
        await expectation.wait()

        // Then
        let container = try #require(receivedContainer)
        #expect(container.image === response?.image)
        let constraints = view.constraints.filter { $0.firstItem === customView && $0.isActive }
        #expect(constraints.count == 4)
        #expect(!customView.translatesAutoresizingMaskIntoConstraints)
    }

    // MARK: - Replacing Requests

    /// The response of the replaced request has already been dispatched to the
    /// main queue when the new one is set. It must still be dropped, or it would
    /// overwrite the new image – the classic cell reuse bug.
    @Test func lateResponseOfReplacedRequestIsDropped() async throws {
        // Given the first request finishes in the pipeline while the main
        // thread is busy, so its completion can't run yet
        var responses: [ImageResponse] = []
        view.onSuccess = { responses.append($0) }
        try runWhileMainThreadIsBlocked(untilTaskCompletes: observer) {
            view.request = request(id: "a")
        }

        // When the view is given a new request before the main queue drains
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.request = request(id: "b")
        await expectation.wait()

        // Then only the new request is displayed and reported
        #expect(responses.count == 1)
        #expect(responses.first?.image.nk_test_processorIDs == ["b"])
        #expect(view.imageView.image?.nk_test_processorIDs == ["b"])
    }

    @Test func viewProcessorsAreUsedForMemoryCacheLookup() throws {
        // Given an image cached for the request with the view's processors
        imageCache[request(id: "p1")] = Test.container
        view.processors = [MockImageProcessor(id: "p1")]
        var response: ImageResponse?
        view.onSuccess = { response = $0 }

        // When
        view.url = Test.url

        // Then
        #expect(view.imageTask == nil)
        #expect(dataLoader.createdTaskCount == 0)
        #expect(try #require(response).request.processors.map(\.identifier) == ["p1"])
    }

    // MARK: - Cancellation

    @Test func cancelledRequestDeliversNoCallbacks() async {
        // Given a request in flight
        dataLoader.isSuspended = true
        var callbackCount = 0
        view.onPreview = { _ in callbackCount += 1 }
        view.onProgress = { _ in callbackCount += 1 }
        view.onSuccess = { _ in callbackCount += 1 }
        view.onFailure = { _ in callbackCount += 1 }
        view.onCompletion = { _ in callbackCount += 1 }
        let startExpectation = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        view.url = Test.url
        await startExpectation.wait()
        #expect(view.imageTask != nil)

        // When
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            view.cancel()
        }
        dataLoader.isSuspended = false

        // Then another request on the same pipeline completes, and the
        // cancelled one still has reported nothing
        await loadAndWait(URL(string: "https://example.com/other.jpg")!, into: makeView())
        #expect(callbackCount == 0)
        #expect(view.imageTask == nil)
    }

    @Test func resetWhileLoadingCancelsRequestAndHidesPlaceholder() async {
        // Given
        dataLoader.isSuspended = true
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        let startExpectation = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        view.url = Test.url
        await startExpectation.wait()
        #expect(!placeholder.isHidden)

        // When
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            view.reset()
        }

        // Then
        #expect(view.imageTask == nil)
        #expect(placeholder.isHidden)
        #expect(view.imageView.isHidden)
    }

    // MARK: - View Lifetime

    @Test func viewIsReleasedAfterRequestCompletes() async {
        let weakView = WeakRef<LazyImageView>()
        var localView: LazyImageView? = makeView()
        weakView.value = localView

        await loadAndWait(Test.url, into: localView!)
        #expect(localView?.imageView.image != nil)

        autoreleasepool { localView = nil }
        #expect(weakView.value == nil)
    }

    // MARK: - Placeholder and Failure Views

    @Test func placeholderViewAddedWhileImageIsDisplayedIsHidden() async {
        // Given
        await loadAndWait(Test.url, into: view)

        // When
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        // Then
        #expect(placeholder.isHidden)
    }

    @Test func placeholderViewAddedWhileLoadingIsVisible() async {
        // Given
        dataLoader.isSuspended = true
        let startExpectation = TestExpectation()
        view.onStart = { _ in startExpectation.fulfill() }
        view.url = Test.url
        await startExpectation.wait()

        // When
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        // Then
        #expect(!placeholder.isHidden)
    }

    @Test func newRequestAfterFailureHidesFailureView() async {
        // Given a view displaying a failure
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        await loadAndWait(Test.url, into: view)
        #expect(!failureView.isHidden)
        #expect(placeholder.isHidden)

        // When
        dataLoader.isSuspended = true
        view.url = URL(string: "https://example.com/other.jpg")!

        // Then
        #expect(failureView.isHidden)
        #expect(!placeholder.isHidden)
    }

    @Test func resetAfterFailureHidesFailureView() async {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        await loadAndWait(Test.url, into: view)
        #expect(!failureView.isHidden)

        // When
        view.reset()

        // Then
        #expect(failureView.isHidden)
        #expect(view.placeholderView?.isHidden == true)
        #expect(view.imageView.isHidden)
    }

    @Test func showPlaceholderOnFailureKeepsFailureViewHidden() async {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        view.showPlaceholderOnFailure = true

        // When
        await loadAndWait(Test.url, into: view)

        // Then
        #expect(!placeholder.isHidden)
        #expect(failureView.isHidden)
    }

    @Test func failureImageIsShownOnFailure() async throws {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        let failureImage = Test.image
        view.failureImage = failureImage

        // When
        await loadAndWait(Test.url, into: view)

        // Then
        let failureView = try #require(view.failureView as? _PlatformImageView)
        #expect(failureView.image === failureImage)
        #expect(!failureView.isHidden)
        #expect(failureView.superview === view)
    }

    /// The placeholder and failure views sit below the image, so an image on
    /// screen covers them, while a custom view goes on top of everything.
    @Test func subviewsAreLayeredBelowTheImage() async throws {
        // Given
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        let customView = _PlatformBaseView()
        view.makeImageView = { _ in customView }

        // When
        await loadAndWait(Test.url, into: view)

        // Then
        let imageViewIndex = try #require(view.subviews.firstIndex(of: view.imageView))
        let placeholderIndex = try #require(view.subviews.firstIndex(of: placeholder))
        let failureViewIndex = try #require(view.subviews.firstIndex(of: failureView))
        #expect(placeholderIndex < imageViewIndex)
        #expect(failureViewIndex < imageViewIndex)
        #expect(view.subviews.last === customView)
    }

    // MARK: - Deferred Reset

    @Test func deferredResetIsAppliedWhenRequestFails() async {
        // Given a displayed image and a failing request with the reset deferred
        await loadAndWait(Test.url, into: view)
        #expect(view.imageView.image != nil)

        let otherURL = URL(string: "https://example.com/other.jpg")!
        dataLoader.results[otherURL] = .failure(NSError(domain: "test", code: 42))
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        view.isResetEnabled = false

        // When
        await loadAndWait(otherURL, into: view)

        // Then the previous image is gone, and the failure is shown instead
        #expect(view.imageView.image == nil)
        #expect(view.imageView.isHidden)
        #expect(!failureView.isHidden)
    }

    @Test func deferredResetIsAppliedImmediatelyForNilRequest() async {
        // Given
        await loadAndWait(Test.url, into: view)
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        view.isResetEnabled = false

        // When
        view.url = nil

        // Then
        #expect(view.imageView.image == nil)
        #expect(view.imageView.isHidden)
        #expect(!failureView.isHidden)
    }

    @Test func deferredResetKeepsImageWhenNewRequestIsCancelled() async {
        // Given a displayed image and a new request with the reset deferred
        await loadAndWait(Test.url, into: view)
        let image = view.imageView.image
        view.isResetEnabled = false

        dataLoader.isSuspended = true
        let startExpectation = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        view.url = URL(string: "https://example.com/other.jpg")!
        await startExpectation.wait()

        // When
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            view.cancel()
        }

        // Then nothing replaced the previous image
        #expect(view.imageView.image === image)
        #expect(!view.imageView.isHidden)
    }

    // MARK: - Progressive Rendering

    @Test func previewIsDisplayedBeforeOnPreviewIsCalled() async {
        // Given
        let progressiveLoader = MockProgressiveDataLoader()
        view.pipeline = ImagePipeline {
            $0.dataLoader = progressiveLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageProcessingQueue.maxConcurrentTaskCount = 1
        }
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        var isFirstPreviewDisplayed: Bool?
        view.onPreview = { response in
            if isFirstPreviewDisplayed == nil {
                isFirstPreviewDisplayed = view.imageView.image === response.image
                    && !view.imageView.isHidden
                    && placeholder.isHidden
                    && view.imageTask != nil
            }
            progressiveLoader.resume()
        }
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }

        // When
        view.url = Test.url
        await expectation.wait()

        // Then
        #expect(isFirstPreviewDisplayed == true)
    }

    // MARK: - Helpers

    private func makeView() -> LazyImageView {
        let view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
        return view
    }

    private func loadAndWait(_ url: URL, into view: LazyImageView) async {
        let expectation = TestExpectation()
        let onCompletion = view.onCompletion
        view.onCompletion = {
            onCompletion?($0)
            expectation.fulfill()
        }
        view.url = url
        await expectation.wait()
        view.onCompletion = onCompletion
    }
}

#endif
