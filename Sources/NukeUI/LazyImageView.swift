// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Lazily loads and displays images.
public final class LazyImageView: _PlatformBaseView {

    // MARK: Placeholder View

    #if os(macOS)
    /// An image to be shown while the request is in progress.
    public var placeholderImage: NSImage? {
        didSet { setPlaceholderImage(placeholderImage) }
    }

    /// A view to be shown while the request is in progress. For example,
    /// a spinner.
    public var placeholderView: NSView? {
        didSet { setPlaceholderView(oldValue, placeholderView) }
    }
    #else
    /// An image to be shown while the request is in progress.
    public var placeholderImage: UIImage? {
        didSet { setPlaceholderImage(placeholderImage) }
    }

    /// A view to be shown while the request is in progress. For example,
    /// a spinner.
    public var placeholderView: UIView? {
        didSet { setPlaceholderView(oldValue, placeholderView) }
    }
    #endif

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

    private var placeholderViewConstraints: [NSLayoutConstraint] = []

    // MARK: Failure View

    #if os(macOS)
    /// An image to be shown if the request fails.
    public var failureImage: NSImage? {
        didSet { setFailureImage(failureImage) }
    }

    /// A view to be shown if the request fails.
    public var failureView: NSView? {
        didSet { setFailureView(oldValue, failureView) }
    }
    #else
    /// An image to be shown if the request fails.
    public var failureImage: UIImage? {
        didSet { setFailureImage(failureImage) }
    }

    /// A view to be shown if the request fails.
    public var failureView: UIView? {
        didSet { setFailureView(oldValue, failureView) }
    }
    #endif

    /// The position of the failure vuew. `.fill` by default.
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

    /// A animated transition to be performed when displaying a loaded image
    /// By default, `.fadeIn(duration: 0.33)`.
    public var transition: Transition?

    /// An animated transition.
    public enum Transition {
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
    public let imageView = ImageView()

    // MARK: Managing Image Tasks

    /// Processors to be applied to the image. `nil` by default.
    ///
    /// If you pass an image requests with a non-empty list of processors as
    /// a source, your processors will be applied instead.
    public var processors: [ImageProcessing]?

    /// Sets the priority of the image task. The priorit can be changed
    /// dynamically. `nil` by default.
    public var priority: ImageRequest.Priority? {
        didSet {
            if let priority = self.priority {
                imageTask?.priority = priority
            }
        }
    }

    /// Current image task.
    public var imageTask: ImageTask?

    /// The pipeline to be used for download. `shared` by default.
    public var pipeline: ImagePipeline = .shared

    // MARK: Callbacks

    /// Gets called when the request is started.
    public var onStart: ((_ task: ImageTask) -> Void)?

    /// Gets called when the request progress is updated.
    public var onProgress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?

    /// Gets called when the requests finished successfully.
    public var onSuccess: ((_ response: ImageResponse) -> Void)?

    /// Gets called when the requests fails.
    public var onFailure: ((_ response: Error) -> Void)?

    /// Gets called when the request is completed.
    public var onCompletion: ((_ result: Result<ImageResponse, Error>) -> Void)?

    // MARK: Other Options

    /// `true` by default. If disabled, progressive image scans will be ignored.
    ///
    /// This option also affects the previews for animated images or videos.
    public var isProgressiveImageRenderingEnabled = true

    /// `true` by default. If enabled, the image view will be cleared before the
    /// new download is started. You can disable it if you want to keep the
    /// previous content while the new download is in progress.
    public var isResetEnabled = true

    // MARK: Private

    private var isResetNeeded = false
    private var isDisplayingContent = false

    // MARK: Initializers

    deinit {
        cancel()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        didInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        didInit()
    }

    private func didInit() {
        addSubview(imageView)
        imageView.pinToSuperview()

        placeholderView = {
            let view = _PlatformBaseView()
            let color: _PlatformColor
            if #available(iOS 13.0, *) {
                color = .secondarySystemBackground
            } else {
                color = _PlatformColor.lightGray.withAlphaComponent(0.5)
            }
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

    /// Sets the given source and immediately starts the download.
    public var source: ImageRequestConvertible? {
        didSet { load(source) }
    }

    public override func updateConstraints() {
        super.updateConstraints()

        updatePlaceholderViewConstraints()
        updateFailureViewConstraints()
    }

    /// Cancels current request and prepares the view for reuse.
    public func reset() {
        cancel()

        imageView.imageContainer = nil
        imageView.isHidden = true

        setPlaceholderViewHidden(true)
        setFailureViewHidden(true)

        isDisplayingContent = false
        isResetNeeded = false
    }

    /// Cancels current request.
    public func cancel() {
        imageTask?.cancel()
        imageTask = nil
    }

    // MARK: Load (ImageRequestConvertible)

    /// Loads an image with the given request.
    private func load(_ request: ImageRequestConvertible?) {
        assert(Thread.isMainThread, "Must be called from the main thread")

        cancel()

        if isResetEnabled {
            reset()
        } else {
            isResetNeeded = true
        }

        guard var request = request?.asImageRequest() else {
            handle(result: .failure(FetchImageError.sourceEmpty), isSync: true)
            return
        }

        if let processors = self.processors, !processors.isEmpty, !request.processors.isEmpty {
            request.processors = processors
        }
        if let priority = self.priority {
            request.priority = priority
        }

        // Quick synchronous memory cache lookup
        if let image = pipeline.cache[request] {
            if image.isPreview {
                display(image, isFromMemory: true) // Display progressive preview
            } else {
                let response = ImageResponse(container: image, cacheType: .memory)
                handle(result: .success(response), isSync: true)
                return
            }
        }

        setPlaceholderViewHidden(false)

        let task = pipeline.loadImage(
            with: request,
            queue: .main,
            progress: { [weak self] response, completedCount, totalCount in
                guard let self = self else { return }
                if let response = response {
                    self.handle(preview: response)
                }
                self.onProgress?(response, completedCount, totalCount)
            },
            completion: { [weak self] result in
                self?.handle(result: result.mapError { $0 }, isSync: false)
            }
        )
        imageTask = task
        onStart?(task)
    }

    private func handle(preview: ImageResponse) {
        guard isProgressiveImageRenderingEnabled else {
            return
        }
        setPlaceholderViewHidden(true)
        display(preview.container, isFromMemory: false)
    }

    private func handle(result: Result<ImageResponse, Error>, isSync: Bool) {
        resetIfNeeded()
        setPlaceholderViewHidden(true)

        switch result {
        case let .success(response):
            display(response.container, isFromMemory: isSync)
        case .failure:
            setFailureViewHidden(false)
        }

        imageTask = nil
        switch result {
        case .success(let response): onSuccess?(response)
        case .failure(let error): onFailure?(error)
        }
        onCompletion?(result)
    }

    private func display(_ container: ImageContainer, isFromMemory: Bool) {
        resetIfNeeded()

        imageView.imageContainer = container
        imageView.isHidden = false

        if !isFromMemory, let transition = transition {
            runTransition(transition, container)
        }

        // It's used to determine when to perform certain transitions
        isDisplayingContent = true
    }

    // MARK: Private (Placeholder View)

    private func setPlaceholderViewHidden(_ isHidden: Bool) {
        placeholderView?.isHidden = isHidden
    }

    private func setPlaceholderImage(_ placeholderImage: _PlatformImage?) {
        guard let placeholderImage = placeholderImage else {
            placeholderView = nil
            return
        }
        placeholderView = _PlatformImageView(image: placeholderImage)
    }

    private func setPlaceholderView(_ oldView: _PlatformBaseView?, _ newView: _PlatformBaseView?) {
        if let oldView = oldView {
            oldView.removeFromSuperview()
        }
        if let newView = newView {
            newView.isHidden = true
            insertSubview(newView, at: 0)
            setNeedsUpdateConstraints()
            #if os(iOS) || os(tvOS)
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
        failureView?.isHidden = isHidden
    }

    private func setFailureImage(_ failureImage: _PlatformImage?) {
        guard let failureImage = failureImage else {
            failureView = nil
            return
        }
        failureView = _PlatformImageView(image: failureImage)
    }

    private func setFailureView(_ oldView: _PlatformBaseView?, _ newView: _PlatformBaseView?) {
        if let oldView = oldView {
            oldView.removeFromSuperview()
        }
        if let newView = newView {
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

    #if os(iOS) || os(tvOS)

    private func runFadeInTransition(duration: TimeInterval) {
        guard !isDisplayingContent else { return }
        imageView.alpha = 0
        UIView.animate(withDuration: duration, delay: 0, options: [.allowUserInteraction]) {
            self.imageView.alpha = 1
        }
    }

    #elseif os(macOS)

    private func runFadeInTransition(duration: TimeInterval) {
        guard !isDisplayingContent else { return }
        imageView.layer?.animateOpacity(duration: duration)
    }

    #endif

    // MARK: Misc

    public enum SubviewPosition {
        /// Center in the superview.
        case center

        /// Fill the superview.
        case fill
    }

    private func resetIfNeeded() {
        if isResetNeeded {
            reset()
            isResetNeeded = false
        }
    }
}

#endif
