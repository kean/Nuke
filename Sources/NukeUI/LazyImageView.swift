// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Lazily loads and displays images.
///
/// ``LazyImageView`` is a ``LazyImage`` counterpart for UIKit and AppKit with the equivalent set of APIs.
///
/// ```swift
/// let imageView = LazyImageView()
/// imageView.placeholderView = UIActivityIndicatorView()
/// imageView.priority = .high
/// imageView.pipeline = customPipeline
/// imageView.onCompletion = { _ in print("Request completed") }
///
/// imageView.url = URL(string: "https://example.com/image.jpeg")
/// ```
@MainActor
public final class LazyImageView: _PlatformBaseView {

    // MARK: Placeholder View

    /// An image to be shown while the request is in progress.
    public var placeholderImage: PlatformImage? {
        didSet { setPlaceholderImage(placeholderImage) }
    }

    /// A view to be shown while the request is in progress. For example,
    /// a spinner.
    public var placeholderView: _PlatformBaseView? {
        didSet { setPlaceholderView(oldValue, placeholderView) }
    }

    /// The position of the placeholder. `.fill` by default.
    ///
    /// It also affects `placeholderImage` because it gets converted to a view.
    public var placeholderViewPosition: SubviewPosition = .fill {
        didSet {
            guard oldValue != placeholderViewPosition,
                  placeholderView != nil else { return }
            setNeedsUpdateConstraints()
        }
    }

    /// Displays the placeholder image or view in the case of a failure.
    /// `false` by default.
    public var showPlaceholderOnFailure = false

    private var placeholderViewConstraints: [NSLayoutConstraint] = []

    // MARK: Failure View

    /// An image to be shown if the request fails.
    public var failureImage: PlatformImage? {
        didSet { setFailureImage(failureImage) }
    }

    /// A view to be shown if the request fails.
    public var failureView: _PlatformBaseView? {
        didSet { setFailureView(oldValue, failureView) }
    }

    /// The position of the failure view. `.fill` by default.
    ///
    /// It also affects `failureImage` because it gets converted to a view.
    public var failureViewPosition: SubviewPosition = .fill {
        didSet {
            guard oldValue != failureViewPosition,
                  failureView != nil else { return }
            setNeedsUpdateConstraints()
        }
    }

    private var failureViewConstraints: [NSLayoutConstraint] = []

    // MARK: Transition

    /// An animated transition to be performed when displaying a loaded image.
    /// `.fadeIn(duration: 0.33)` by default.
    public var transition: Transition?

    /// An animated transition.
    @frozen public enum Transition {
        /// Fade-in transition.
        case fadeIn(duration: TimeInterval)
        /// A custom image view transition.
        ///
        /// The closure will get called after the image is already displayed but
        /// before `imageContainer` value is updated.
        case custom(closure: (LazyImageView, ImageContainer) -> Void)
    }

    // MARK: Underlying Views

    /// Returns the underlying image view.
    ///
    /// It is an ``AnimatedImageView``, so a response the pipeline recognized as
    /// an animated image plays instead of showing its first frame. Its
    /// ``AnimatedImageView/player`` is the way to control that playback.
    public let imageView = AnimatedImageView()

    /// Creates a custom view for displaying the given image response.
    ///
    /// Return `nil` to use the default platform image view.
    public var makeImageView: ((ImageContainer) -> _PlatformBaseView?)?

    private var customImageView: _PlatformBaseView?

    // MARK: Managing Image Tasks

    /// Processors to be applied to the image. `nil` by default.
    ///
    /// If you pass an image request with a non-empty list of processors as
    /// a source, your processors will be applied instead.
    public var processors: [any ImageProcessing]? {
        didSet { loader.processors = processors ?? [] }
    }

    /// Overrides the priority of the request. `nil` by default, which uses the
    /// request's own priority. The priority can be changed dynamically.
    public var priority: ImageRequest.Priority? {
        didSet { loader.priority = priority }
    }

    /// Current image task.
    public var imageTask: ImageTask? { loader.task }

    /// The pipeline to be used for download. `shared` by default.
    public var pipeline: ImagePipeline {
        get { loader.pipeline }
        set { loader.pipeline = newValue }
    }

    private let loader = ImageLoader()

    // MARK: Callbacks

    /// Gets called when the request is started.
    public var onStart: (@MainActor @Sendable (ImageTask) -> Void)?

    /// Gets called when a progressive image preview is produced.
    public var onPreview: (@MainActor @Sendable (ImageResponse) -> Void)?

    /// Gets called when the request progress is updated.
    ///
    /// Receives `ImageTask.Progress`, the same struct the pipeline reports.
    public var onProgress: (@MainActor @Sendable (ImageTask.Progress) -> Void)?

    /// Gets called when the request finishes successfully.
    public var onSuccess: (@MainActor @Sendable (ImageResponse) -> Void)?

    /// Gets called when the request fails.
    public var onFailure: (@MainActor @Sendable (ImagePipeline.Error) -> Void)?

    /// Gets called when the request is completed.
    public var onCompletion: (@MainActor @Sendable (Result<ImageResponse, ImagePipeline.Error>) -> Void)?

    // MARK: Other Options

    /// `true` by default. If disabled, progressive image scans will be ignored.
    public var isProgressiveRenderingEnabled = true

    /// `true` by default. If enabled, the image view will be cleared before the
    /// new download is started. You can disable it if you want to keep the
    /// previous content while the new download is in progress.
    public var isResetEnabled = true

    // MARK: Private

    private var isResetNeeded = false

    // MARK: Initializers

    override public init(frame: CGRect) {
        super.init(frame: frame)
        didInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        didInit()
    }

    private func didInit() {
        loader.onUpdate = { [weak self] in self?.render($0) }

        imageView.isHidden = true
        addSubview(imageView)
        imageView.pinToSuperview()

        placeholderView = {
            let view = _PlatformBaseView()
            let color = _PlatformColor.secondarySystemBackground
#if os(macOS)
            view.wantsLayer = true
            view.layer?.backgroundColor = color.cgColor
#else
            view.backgroundColor = color
#endif

            return view
        }()

        transition = .fadeIn(duration: 0.33)
    }

    /// Sets the given URL and immediately starts the download.
    public var url: URL? {
        get { request?.url }
        set {
            if let newValue {
                request = ImageRequest(url: newValue)
            } else {
                request = nil
            }
        }
    }

    /// Sets the given request and immediately starts the download.
    ///
    /// If the view is already loading the same image, whatever the priority,
    /// the task keeps running and gets the new priority.
    public var request: ImageRequest? {
        didSet { load(request) }
    }

    override public func updateConstraints() {
        super.updateConstraints()

        updatePlaceholderViewConstraints()
        updateFailureViewConstraints()
    }

    /// Cancels current request and prepares the view for reuse.
    public func reset() {
        loader.reset()
    }

    private func resetViews(clearImage: Bool) {
        if clearImage {
            if imageView.image != nil { imageView.prepareForReuse() }
            if !imageView.isHidden { imageView.isHidden = true }
        }

        removeCustomImageView()

        setPlaceholderViewHidden(true)
        setFailureViewHidden(true)

        isResetNeeded = false
    }

    private func resetOrDefer(clearImage: Bool = true) {
        if isResetEnabled {
            resetViews(clearImage: clearImage)
        } else {
            isResetNeeded = true
        }
    }

    /// Cancels current request.
    public func cancel() {
        loader.cancel()
    }

    // MARK: Loading Images

    /// Loads an image with the given request.
    private func load(_ request: ImageRequest?) {
        assert(Thread.isMainThread, "Must be called from the main thread")
        loader.load(request)
    }

    private func render(_ state: ImageLoader.State) {
        switch state.event {
        case .started(let task):
            handleStart(state, task: task)
        case .progress(let progress):
            onProgress?(progress)
        case .preview(let response):
            if isProgressiveRenderingEnabled {
                setPlaceholderViewHidden(true)
                display(response.container, isFromMemory: false)
            }
            onPreview?(response)
        case let .finished(result, isSynchronous):
            if isSynchronous {
                // A hit overwrites `imageView.image` directly, without clearing it first.
                if case .success = result {
                    resetOrDefer(clearImage: false)
                } else {
                    resetOrDefer()
                }
            }
            handle(result: result, isSynchronous: isSynchronous)
        case .reset:
            resetViews(clearImage: true)
        case .cancelled:
            break
        }
    }

    private func handleStart(_ state: ImageLoader.State, task: ImageTask?) {
        resetOrDefer()
        if let container = state.imageContainer {
            display(container, isFromMemory: true) // A preview found in the memory cache
        }
        setPlaceholderViewHidden(false)
        if let task {
            onStart?(task)
        }
    }

    private func handle(result: Result<ImageResponse, ImagePipeline.Error>, isSynchronous: Bool) {
        switch result {
        case .success: resetIfNeeded(clearImage: false)
        case .failure: resetIfNeeded()
        }
        setPlaceholderViewHidden(true)

        switch result {
        case let .success(response):
            display(response.container, isFromMemory: isSynchronous)
        case .failure:
            if showPlaceholderOnFailure {
                setPlaceholderViewHidden(false)
            } else {
                setFailureViewHidden(false)
            }
        }

        switch result {
        case .success(let response): onSuccess?(response)
        case .failure(let error): onFailure?(error)
        }
        onCompletion?(result)
    }

    private func display(_ container: ImageContainer, isFromMemory: Bool) {
        resetIfNeeded(clearImage: false)

        // Remove the view created for the previous response (a progressive
        // preview or a cached preview) before displaying the new one.
        removeCustomImageView()

        if let view = makeImageView?(container) {
            addSubview(view)
            view.pinToSuperview()
            customImageView = view
        } else {
            // Goes through `display` rather than setting `image` so that an
            // animated response starts playing.
            imageView.display(container)
            if imageView.isHidden {
                imageView.isHidden = false
            }
        }

        if !isFromMemory, let transition = transition {
            runTransition(transition, container)
        }
    }

    private func removeCustomImageView() {
        guard let customImageView else { return }
        customImageView.removeFromSuperview()
        self.customImageView = nil
    }

    // MARK: Private (Placeholder View)

    private func setPlaceholderViewHidden(_ isHidden: Bool) {
        guard let placeholderView, placeholderView.isHidden != isHidden else { return }
        placeholderView.isHidden = isHidden
    }

    private func setPlaceholderImage(_ placeholderImage: PlatformImage?) {
        guard let placeholderImage else {
            placeholderView = nil
            return
        }
        placeholderView = _PlatformImageView(image: placeholderImage)
    }

    private func setPlaceholderView(_ oldView: _PlatformBaseView?, _ newView: _PlatformBaseView?) {
        if let oldView {
            oldView.removeFromSuperview()
        }
        if let newView {
            newView.isHidden = !imageView.isHidden
            insertSubview(newView, at: 0)
            setNeedsUpdateConstraints()
#if os(iOS) || os(tvOS) || os(visionOS)
            if let spinner = newView as? UIActivityIndicatorView {
                spinner.startAnimating()
            }
#endif
        }
    }

    private func updatePlaceholderViewConstraints() {
        NSLayoutConstraint.deactivate(placeholderViewConstraints)
        placeholderViewConstraints = placeholderView?.layout(with: placeholderViewPosition) ?? []
    }

    // MARK: Private (Failure View)

    private func setFailureViewHidden(_ isHidden: Bool) {
        guard let failureView, failureView.isHidden != isHidden else { return }
        failureView.isHidden = isHidden
    }

    private func setFailureImage(_ failureImage: PlatformImage?) {
        guard let failureImage else {
            failureView = nil
            return
        }
        failureView = _PlatformImageView(image: failureImage)
    }

    private func setFailureView(_ oldView: _PlatformBaseView?, _ newView: _PlatformBaseView?) {
        if let oldView {
            oldView.removeFromSuperview()
        }
        if let newView {
            newView.isHidden = true
            insertSubview(newView, at: 0)
            setNeedsUpdateConstraints()
        }
    }

    private func updateFailureViewConstraints() {
        NSLayoutConstraint.deactivate(failureViewConstraints)
        failureViewConstraints = failureView?.layout(with: failureViewPosition) ?? []
    }

    // MARK: Private (Transitions)

    private func runTransition(_ transition: Transition, _ image: ImageContainer) {
        switch transition {
        case .fadeIn(let duration):
            runFadeInTransition(duration: duration)
        case .custom(let closure):
            closure(self, image)
        }
    }

#if os(macOS)
    private func runFadeInTransition(duration: TimeInterval) {
        guard !imageView.isHidden else { return }
        imageView.layer?.animateOpacity(duration: duration)
    }
#else
    private func runFadeInTransition(duration: TimeInterval) {
        guard !imageView.isHidden else { return }
        imageView.alpha = 0
        UIView.animate(withDuration: duration, delay: 0, options: [.allowUserInteraction]) {
            self.imageView.alpha = 1
        }
    }
#endif

    // MARK: Misc

    @frozen public enum SubviewPosition {
        /// Center in the superview.
        case center

        /// Fill the superview.
        case fill
    }

    private func resetIfNeeded(clearImage: Bool = true) {
        if isResetNeeded {
            resetViews(clearImage: clearImage)
        }
    }
}

#endif
