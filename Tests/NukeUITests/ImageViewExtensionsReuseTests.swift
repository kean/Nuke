// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

/// Covers how `loadImage(with:options:into:)` treats a view that gets reused,
/// cancelled, or deallocated, and the memory cache and transition contracts
/// documented on it.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageViewExtensionsReuseTests {
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

    // MARK: - Reuse

    /// The completion of the replaced request has already been dispatched to
    /// the main queue when the view is reused. It must still be dropped, or it
    /// would overwrite the new image – the classic cell reuse bug.
    @Test func lateResponseOfReplacedRequestIsDropped() async throws {
        // Given the first request finishes in the pipeline while the main
        // thread is busy, so its completion can't run yet
        var firstCompletionCount = 0
        try runWhileMainThreadIsBlocked(untilTaskCompletes: observer) {
            NukeUI.loadImage(with: request(id: "a"), options: options, into: imageView) { _ in
                firstCompletionCount += 1
            }
        }

        // When the view is reused before the main queue drains
        let expectation = TestExpectation()
        var secondResult: Result<ImageResponse, ImagePipeline.Error>?
        NukeUI.loadImage(with: request(id: "b"), options: options, into: imageView) {
            secondResult = $0
            expectation.fulfill()
        }
        await expectation.wait()

        // Then only the new request is displayed and reported
        #expect(firstCompletionCount == 0)
        #expect(try #require(secondResult).isSuccess)
        #expect(imageView.image?.nk_test_processorIDs == ["b"])
    }

    /// Starting a new load from the completion of the previous one is the
    /// natural way to chain requests, so the new task must be the one the view
    /// tracks rather than being cleared by the finishing one.
    @Test func loadStartedFromCompletionIsTrackedByTheView() async throws {
        // Given
        var chainedTask: ImageTask?
        let expectation = TestExpectation()
        NukeUI.loadImage(with: request(id: "a"), options: options, into: imageView) { _ in
            dataLoader.isSuspended = true
            chainedTask = NukeUI.loadImage(with: request(id: "b"), options: options, into: imageView)
            expectation.fulfill()
        }
        await expectation.wait()
        let task = try #require(chainedTask)

        // When
        NukeUI.cancelRequest(for: imageView)

        // Then
        #expect(task.isCancelled)
    }

    // MARK: - Cancellation

    @Test func cancelledRequestDeliversNoCallbacksAndKeepsPlaceholder() async throws {
        // Given a request in flight displaying a placeholder
        dataLoader.isSuspended = true
        let placeholder = Test.image
        var options = options
        options.placeholder = placeholder
        options.failureImage = Test.image

        var callbackCount = 0
        let imageTask = NukeUI.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            progress: { _, _, _ in callbackCount += 1 },
            completion: { _ in callbackCount += 1 }
        )
        let task = try #require(imageTask)

        // When
        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            NukeUI.cancelRequest(for: imageView)
        }
        #expect(task.isCancelled)
        dataLoader.isSuspended = false

        // Then another request on the same pipeline completes, and the
        // cancelled one still has reported nothing
        await loadImageAndWait(with: request(id: "other"), options: options, into: _ImageView())
        #expect(callbackCount == 0)
        #expect(imageView.image === placeholder)
    }

    @Test func cancelRequestForViewWithoutRequestIsNoOp() async {
        // Given a view that has never loaded anything
        let image = Test.image
        imageView.image = image

        // When
        NukeUI.cancelRequest(for: imageView)

        // Then it keeps its content and can still load images
        #expect(imageView.image === image)
        await loadImageExpectingSuccess(with: Test.request, options: options, into: imageView)
        #expect(imageView.image != nil)
        #expect(imageView.image !== image)
    }

    // MARK: - View Lifetime

    @Test func viewIsReleasedAfterTheRequestCompletes() async {
        let weakView = WeakRef<_ImageView>()
        var view: _ImageView? = _ImageView()
        weakView.value = view

        await loadImageExpectingSuccess(with: Test.request, options: options, into: view!)

        autoreleasepool { view = nil }
        #expect(weakView.value == nil)
    }

    // MARK: - Defaults

    @Test func defaultOptions() {
        let options = ImageLoadingOptions()

        #expect(options.placeholder == nil)
        #expect(options.failureImage == nil)
        #expect(options.transition == nil)
        #expect(options.failureImageTransition == nil)
        #expect(!options.alwaysTransition)
        #expect(options.isPrepareForReuseEnabled)
        #expect(options.isProgressiveRenderingEnabled)
        #expect(options.pipeline == nil)
        #expect(options.processors.isEmpty)
        #expect(options.transition(for: .placeholder) == nil)
#if os(iOS) || os(tvOS) || os(visionOS)
        #expect(options.contentModes == nil)
        #expect(options.tintColors == nil)
        #expect(options.contentMode(for: .success) == nil)
        #expect(options.tintColor(for: .failure) == nil)
#endif
    }

    // MARK: - Nil Request

    @Test func nilURLCompletesSynchronouslyWithoutTask() {
        // Given
        var result: Result<ImageResponse, ImagePipeline.Error>?

        // When
        let task = NukeUI.loadImage(with: nil as URL?, options: options, into: imageView) {
            result = $0
        }

        // Then
        #expect(task == nil)
        #expect(result?.error == .imageRequestMissing)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func nilRequestKeepsImageWhenPrepareForReuseIsDisabled() {
        // Given
        let image = Test.image
        imageView.image = image
        var options = options
        options.isPrepareForReuseEnabled = false

        // When
        var result: Result<ImageResponse, ImagePipeline.Error>?
        NukeUI.loadImage(with: nil as ImageRequest?, options: options, into: imageView) {
            result = $0
        }

        // Then there is no failure image to replace it with
        #expect(result?.error == .imageRequestMissing)
        #expect(imageView.image === image)
    }

    @Test func failureImageForNilRequestIsDisplayedWithoutTransition() {
        // Given
        var options = options
        let failureImage = Test.image
        options.failureImage = failureImage
        var isTransitionPerformed = false
        options.failureImageTransition = .custom { _, _ in isTransitionPerformed = true }

        // When
        NukeUI.loadImage(with: nil as ImageRequest?, options: options, into: imageView)

        // Then the failure is known immediately, so it's treated like a memory
        // cache hit
        #expect(imageView.image === failureImage)
        #expect(!isTransitionPerformed)
    }

    @Test func failureImageForNilRequestIsAnimatedWithAlwaysTransition() {
        // Given
        var options = options
        let failureImage = Test.image
        options.failureImage = failureImage
        options.alwaysTransition = true
        var transitionImage: PlatformImage?
        options.failureImageTransition = .custom { _, image in transitionImage = image }

        // When
        NukeUI.loadImage(with: nil as ImageRequest?, options: options, into: imageView)

        // Then
        #expect(transitionImage === failureImage)
    }

    // MARK: - Memory Cache

    @Test func memoryCacheHitIsDisplayedWithoutTransition() {
        // Given
        imageCache[Test.request] = Test.container
        var options = options
        var isTransitionPerformed = false
        options.transition = .custom { _, _ in isTransitionPerformed = true }

        // When
        let task = NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(task == nil)
        #expect(imageView.image != nil)
        #expect(!isTransitionPerformed)
    }

    @Test func memoryCacheHitIsAnimatedWithAlwaysTransition() {
        // Given
        let container = Test.container
        imageCache[Test.request] = container
        var options = options
        options.alwaysTransition = true
        var transitionImage: PlatformImage?
        options.transition = .custom { _, image in transitionImage = image }

        // When
        var result: Result<ImageResponse, ImagePipeline.Error>?
        let task = NukeUI.loadImage(with: Test.request, options: options, into: imageView) {
            result = $0
        }

        // Then the transition runs synchronously, and is responsible for
        // displaying the image
        #expect(task == nil)
        #expect(transitionImage === container.image)
        #expect(imageView.image == nil)
        #expect(result?.value?.cacheType == .memory)
    }

    @Test func optionsProcessorsAreUsedForMemoryCacheLookup() throws {
        // Given an image cached for the request with the default processors
        imageCache[request(id: "p1")] = Test.container
        var options = options
        options.processors = [MockImageProcessor(id: "p1")]

        // When
        var result: Result<ImageResponse, ImagePipeline.Error>?
        let task = NukeUI.loadImage(with: Test.request, options: options, into: imageView) {
            result = $0
        }

        // Then
        #expect(task == nil)
        #expect(dataLoader.createdTaskCount == 0)
        let response = try #require(result?.value)
        #expect(response.cacheType == .memory)
        #expect(response.request.processors.map(\.identifier) == ["p1"])
    }

    @Test func requestProcessorsTakePrecedenceOverOptionsProcessors() async {
        // Given
        var options = options
        options.processors = [MockImageProcessor(id: "p1")]

        // When
        await loadImageExpectingSuccess(with: request(id: "p2"), options: options, into: imageView)

        // Then
        #expect(imageView.image?.nk_test_processorIDs == ["p2"])
    }

    // MARK: - Placeholder

    @Test func placeholderIsNotAnimated() {
        // Given
        dataLoader.isSuspended = true
        var options = options
        let placeholder = Test.image
        options.placeholder = placeholder
        options.alwaysTransition = true
        var isTransitionPerformed = false
        options.transition = .custom { _, _ in isTransitionPerformed = true }

        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image === placeholder)
        #expect(!isTransitionPerformed)
    }

    @Test func placeholderIsDisplayedEvenWhenPrepareForReuseIsDisabled() {
        // Given
        dataLoader.isSuspended = true
        imageView.image = Test.image
        var options = options
        let placeholder = Test.image
        options.placeholder = placeholder
        options.isPrepareForReuseEnabled = false

        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image === placeholder)
    }

    @Test func placeholderStaysWhenRequestFailsWithoutFailureImage() async {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "t", code: 42))
        var options = options
        let placeholder = Test.image
        options.placeholder = placeholder

        // When
        await loadImageAndWait(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image === placeholder)
    }

    // MARK: - Prepare For Reuse

    @Test func prepareForReuseRemovesRunningAnimations() throws {
        // Given
        dataLoader.isSuspended = true
        let layer = try #require(makeLayerBacked(imageView))
        layer.add(makeLongAnimation(), forKey: "test")
        try #require(layer.animation(forKey: "test") != nil)

        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(layer.animationKeys() == nil)
    }

    @Test func animationsKeptWhenPrepareForReuseIsDisabled() throws {
        // Given
        dataLoader.isSuspended = true
        let layer = try #require(makeLayerBacked(imageView))
        layer.add(makeLongAnimation(), forKey: "test")
        var options = options
        options.isPrepareForReuseEnabled = false

        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(layer.animation(forKey: "test") != nil)
    }

    // MARK: - Custom Views

    @Test func customViewIsClearedThenGivenTheWholeContainer() async throws {
        // Given an animated image, which carries its data and animation
        dataLoader.results[Test.url] = .success((
            Test.animatedGIF(frameCount: 3),
            URLResponse(url: Test.url, mimeType: "image/gif", expectedContentLength: -1, textEncodingName: nil)
        ))
        let view = RecordingImageView()

        // When
        var response: ImageResponse?
        let expectation = TestExpectation()
        NukeUI.loadImage(with: Test.request, options: options, into: view) {
            response = $0.value
            expectation.fulfill()
        }
        await expectation.wait()

        // Then the view is first prepared for reuse, then handed the container
        // the pipeline produced
        try #require(view.containers.count == 2)
        #expect(view.containers[0] == nil)
        let container = try #require(view.containers[1])
        #expect(container.image === response?.image)
        #expect(container.type == .gif)
        #expect(container.data != nil)
        #expect(container.animation != nil)
    }

    @Test func customViewPlaceholderAndFailureImageAreWrappedInContainers() async throws {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "t", code: 42))
        var options = options
        let placeholder = Test.image
        let failureImage = Test.image
        options.placeholder = placeholder
        options.failureImage = failureImage
        let view = RecordingImageView()

        // When
        await loadImageAndWait(with: Test.request, options: options, into: view)

        // Then a placeholder replaces the "prepare for reuse" call
        try #require(view.containers.count == 2)
        #expect(view.containers[0]?.image === placeholder)
        #expect(view.containers[1]?.image === failureImage)
    }

#if os(macOS)
    /// `ImageDisplayingView` on macOS is `NSObject & ImageDisplaying` so that
    /// an `NSCell` can display images too. Such a type has no layer to animate.
    @Test func displayingObjectWithoutLayerIsSupported() async throws {
        // Given
        let cell = LayerlessDisplayer()
        var options = options
        options.transition = .fadeIn(duration: 10)
        #expect(cell.layer == nil)

        // When
        await loadImageExpectingSuccess(with: Test.request, options: options, into: cell)

        // Then
        try #require(cell.containers.count == 2)
        #expect(cell.containers[0] == nil)
        #expect(cell.containers[1]?.image != nil)
    }

    @Test func fadeInTransitionAnimatesLayerBackedView() async throws {
        // Given
        _ = try #require(makeLayerBacked(imageView))
        var options = options
        options.transition = .fadeIn(duration: 10)

        // When
        // The animation is read from the completion, which runs right after
        // the image is displayed: a layer outside a window drops it at the
        // next commit.
        var animation: CAAnimation?
        let expectation = TestExpectation()
        NukeUI.loadImage(with: Test.request, options: options, into: imageView) { _ in
            animation = imageView.layer?.animation(forKey: "imageTransition")
            expectation.fulfill()
        }
        await expectation.wait()

        // Then
        let fadeIn = try #require(animation as? CABasicAnimation)
        #expect(fadeIn.keyPath == "opacity")
        #expect(fadeIn.duration == 10)
        #expect(fadeIn.fromValue as? Int == 0)
        #expect(fadeIn.toValue as? Int == 1)
        #expect(imageView.image != nil)
    }
#endif

    // MARK: - UIKit

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func tintIsNotAppliedToStatesWithoutTintColor() async {
        // Given
        var options = options
        options.placeholder = Test.image
        options.tintColors = .init(success: nil, failure: nil, placeholder: .yellow)
        let expectation = TestExpectation()

        // When
        NukeUI.loadImage(with: Test.request, options: options, into: imageView) { _ in
            expectation.fulfill()
        }

        // Then only the placeholder is rendered as a template
        #expect(imageView.image?.renderingMode == .alwaysTemplate)
        await expectation.wait()
        #expect(imageView.image?.renderingMode != .alwaysTemplate)
    }

    @Test func contentModeIsAppliedToFailureForNilRequest() {
        // Given
        var options = options
        options.failureImage = Test.image
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .scaleAspectFit)

        // When
        NukeUI.loadImage(with: nil as ImageRequest?, options: options, into: imageView)

        // Then
        #expect(imageView.contentMode == .center)
    }

    @Test func fadeInIntoEmptyViewDoesNotCrossDissolve() async throws {
        // Given an empty image view in a window, which is what makes UIKit
        // run animations. The transition is long so that a temporary view,
        // if one were added, would still be there when the load completes.
        let (window, container) = makeHostedImageView()
        var options = options
        options.transition = .fadeIn(duration: 10)
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)

        // When
        await loadImageExpectingSuccess(with: Test.request, options: options, into: imageView)

        // Then there's nothing to cross-dissolve from, so no temporary view is
        // added
        #expect(container.subviews.count == 1)
        #expect(imageView.image != nil)
        #expect(imageView.contentMode == .scaleAspectFill)
        withExtendedLifetime(window) {}
    }

    @Test func fadeInWithSameContentModeDoesNotCrossDissolve() async throws {
        // Given a view displaying an image with the target content mode
        let (window, container) = makeHostedImageView()
        imageView.image = Test.image
        imageView.contentMode = .scaleAspectFill
        var options = options
        options.transition = .fadeIn(duration: 10)
        options.isPrepareForReuseEnabled = false
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)

        // When
        await loadImageExpectingSuccess(with: Test.request, options: options, into: imageView)

        // Then
        #expect(container.subviews.count == 1)
        withExtendedLifetime(window) {}
    }

    @Test func crossDissolveViewMimicsTheImageView() async throws {
        // Given a view displaying an image with a different content mode
        let (window, container) = makeHostedImageView()
        let previousImage = Test.image
        imageView.image = previousImage
        imageView.contentMode = .center
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.tintColor = .red
        var options = options
        options.transition = .fadeIn(duration: 10)
        options.isPrepareForReuseEnabled = false
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)

        // When
        await loadImageExpectingSuccess(with: Test.request, options: options, into: imageView)

        // Then the temporary view shows the previous image the way the image
        // view displayed it, above the image view
        let transitionView = try #require(container.subviews.last as? UIImageView)
        #expect(transitionView !== imageView)
        #expect(transitionView.image === previousImage)
        #expect(transitionView.contentMode == .center)
        #expect(transitionView.frame == imageView.frame)
        #expect(transitionView.clipsToBounds)
        #expect(transitionView.layer.cornerRadius == 8)
        #expect(transitionView.tintColor == .red)
        #expect(imageView.contentMode == .scaleAspectFill)
        #expect(imageView.image !== previousImage)
        withExtendedLifetime(window) {}
    }

    private func makeHostedImageView() -> (UIWindow, UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        window.isHidden = false
        container.addSubview(imageView)
        imageView.frame = container.bounds
        return (window, container)
    }
#endif

    // MARK: - Helpers

    private func makeLayerBacked(_ view: _ImageView) -> CALayer? {
#if os(macOS)
        view.wantsLayer = true
#endif
        return view.layer
    }

    private func makeLongAnimation() -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = 1000
        return animation
    }
}

// MARK: - Private

private final class RecordingImageView: _PlatformBaseView, ImageDisplaying {
    var containers: [ImageContainer?] = []

    func nuke_display(_ container: ImageContainer?) {
        containers.append(container)
    }
}

#if os(macOS)
private final class LayerlessDisplayer: NSObject, ImageDisplaying {
    var containers: [ImageContainer?] = []

    func nuke_display(_ container: ImageContainer?) {
        containers.append(container)
    }
}
#endif

#endif
