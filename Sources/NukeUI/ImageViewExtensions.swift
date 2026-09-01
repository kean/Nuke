// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if !os(macOS)
import UIKit.UIImage
import UIKit.UIColor
#else
import AppKit.NSImage
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

/// Displays images. Add the conformance to this protocol to your views to make
/// them compatible with the image loading extensions.
///
/// The view is handed the whole ``ImageContainer``, so a renderer of its own
/// has everything the pipeline produced: the still image, the encoded
/// ``ImageContainer/data``, and the ``ImageContainer/animation`` parsed out of
/// it.
///
/// ```swift
/// final class MyImageView: UIView, ImageDisplaying {
///     func nuke_display(_ container: ImageContainer?) {
///         guard let animation = container?.animation else {
///             return show(still: container?.image)
///         }
///         myEngine.play(animation)
///     }
/// }
/// ```
///
/// The method keeps its `nuke_` prefix because the conformances ship as
/// extensions of system classes, where an unprefixed name could collide with a
/// future OS API.
///
/// - important: A conformance declared in an extension – which is how the
/// platform image views get theirs – cannot be overridden by a subclass.
/// Conform your own view directly, as above, rather than subclassing
/// `UIImageView`. To play animated images without writing a renderer, use
/// ``AnimatedImageView``.
@MainActor
public protocol ImageDisplaying {
    /// Displays the image the pipeline produced, or clears the view when the
    /// container is `nil`.
    func nuke_display(_ container: ImageContainer?)

#if os(macOS)
    var layer: CALayer? { get }
#endif
}

#if os(macOS)
extension ImageDisplaying {
    public var layer: CALayer? { nil }
}
#endif

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
/// A `UIView` that implements the `ImageDisplaying` protocol.
public typealias ImageDisplayingView = UIView & ImageDisplaying

extension UIImageView: ImageDisplaying {
    /// Displays the still image, and plays it when the view is an
    /// ``AnimatedImageView``.
    public func nuke_display(_ container: ImageContainer?) {
        displayContainer(container)
    }
}
#elseif os(macOS)
import Cocoa
/// An `NSObject` that implements the `ImageDisplaying` protocol.
/// Can support `NSView` and `NSCell`. The latter can return nil for layer.
public typealias ImageDisplayingView = NSObject & ImageDisplaying

extension NSImageView: ImageDisplaying {
    /// Displays the still image, and plays it when the view is an
    /// ``AnimatedImageView``.
    public func nuke_display(_ container: ImageContainer?) {
        displayContainer(container)
    }
}
#endif

extension _PlatformImageView {
    /// ``AnimatedImageView`` inherits its ``ImageDisplaying`` conformance from
    /// the extension above, and a witness declared in an extension is resolved
    /// statically, so the subclass has nothing to override. This is where it
    /// gets the whole container instead of the still image.
    fileprivate func displayContainer(_ container: ImageContainer?) {
        if let view = self as? AnimatedImageView {
            view.display(container)
        } else {
            self.image = container?.image
        }
    }
}

#if os(tvOS)
import TVUIKit

extension TVPosterView: ImageDisplaying {
    /// Displays an image.
    public func nuke_display(_ container: ImageContainer?) {
        self.image = container?.image
    }
}
#endif

// MARK: - ImageView Extensions

/// Loads an image with the given request and displays it in the view.
///
/// See the complete method signature for more information.
@MainActor
@discardableResult public func loadImage(
    with url: URL?,
    options: ImageLoadingOptions? = nil,
    into view: ImageDisplayingView,
    completion: @escaping @MainActor @Sendable (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void
) -> ImageTask? {
    loadImage(with: url, options: options, into: view, progress: nil, completion: completion)
}

/// Loads an image with the given request and displays it in the view.
///
/// Before loading a new image, the view is prepared for reuse by canceling any
/// outstanding requests and removing a previously displayed image.
///
/// If the image is stored in the memory cache, it is displayed immediately with
/// no animations. If not, the image is loaded using an image pipeline. When the
/// image is loading, the `placeholder` is displayed. When the request
/// completes the loaded image is displayed (or `failureImage` in case of an error)
/// with the selected animation.
///
/// - parameters:
///   - url: The image URL. If `nil`, it's handled as a failure scenario.
///   - options: `ImageLoadingOptions.shared` by default.
///   - view: The view is held weakly. If it is deallocated, the associated
///   request automatically gets canceled.
///   - progress: A closure to be called periodically on the main thread
///   when the progress is updated.
///   - completion: A closure to be called on the main thread when the
///   request is finished. Gets called synchronously if the response was found in
///   the memory cache.
///
/// - returns: An image task or `nil` if the image was found in the memory cache.
@MainActor
@discardableResult public func loadImage(
    with url: URL?,
    options: ImageLoadingOptions? = nil,
    into view: ImageDisplayingView,
    progress: (@MainActor @Sendable (_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
    completion: (@MainActor @Sendable (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
) -> ImageTask? {
    let controller = ImageViewController.controller(for: view)
    let request: ImageRequest?
    if let url {
        request = ImageRequest(url: url)
    } else {
        request = nil
    }
    return controller.loadImage(with: request, options: options ?? .shared, progress: progress, completion: completion)
}

/// Loads an image with the given request and displays it in the view.
///
/// See the complete method signature for more information.
@MainActor
@discardableResult public func loadImage(
    with request: ImageRequest?,
    options: ImageLoadingOptions? = nil,
    into view: ImageDisplayingView,
    completion: @escaping @MainActor @Sendable (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void
) -> ImageTask? {
    loadImage(with: request, options: options ?? .shared, into: view, progress: nil, completion: completion)
}

/// Loads an image with the given request and displays it in the view.
///
/// Before loading a new image, the view is prepared for reuse by canceling any
/// outstanding requests and removing a previously displayed image.
///
/// If the image is stored in the memory cache, it is displayed immediately with
/// no animations. If not, the image is loaded using an image pipeline. When the
/// image is loading, the `placeholder` is displayed. When the request
/// completes the loaded image is displayed (or `failureImage` in case of an error)
/// with the selected animation.
///
/// - parameters:
///   - request: The image request. If `nil`, it's handled as a failure scenario.
///   - options: `ImageLoadingOptions.shared` by default.
///   - view: The view is held weakly. If it is deallocated, the associated
///   request automatically gets canceled.
///   - progress: A closure to be called periodically on the main thread
///   when the progress is updated.
///   - completion: A closure to be called on the main thread when the
///   request is finished. Gets called synchronously if the response was found in
///   the memory cache.
///
/// - returns: An image task or `nil` if the image was found in the memory cache.
@MainActor
@discardableResult public func loadImage(
    with request: ImageRequest?,
    options: ImageLoadingOptions? = nil,
    into view: ImageDisplayingView,
    progress: (@MainActor @Sendable (_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
    completion: (@MainActor @Sendable (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
) -> ImageTask? {
    let controller = ImageViewController.controller(for: view)
    return controller.loadImage(with: request, options: options ?? .shared, progress: progress, completion: completion)
}

/// Cancels an outstanding request associated with the view.
@MainActor
public func cancelRequest(for view: ImageDisplayingView) {
    ImageViewController.controller(for: view).cancelOutstandingTask()
}

// MARK: - ImageViewController

/// Manages image requests on behalf of an image view.
///
/// - note: With a few modifications this might become public at some point,
/// however as it stands today `ImageViewController` is just a helper class,
/// making it public wouldn't expose any additional functionality to the users.
@MainActor
private final class ImageViewController {
    private weak var imageView: ImageDisplayingView?
    private var task: ImageTask?
    private var options: ImageLoadingOptions

#if os(iOS) || os(tvOS) || os(visionOS)
    // Image view used for cross-fade transition between images with different
    // content modes.
    private lazy var transitionImageView = UIImageView()
#endif

    // Automatically cancel the request when the view is deallocated.
    deinit {
        task?.cancel()
    }

    init(view: /* weak */ ImageDisplayingView) {
        self.imageView = view
        self.options = .shared
    }

    // MARK: - Associating Controller

    // Safe because it's never mutated.
    nonisolated(unsafe) static let controllerAK = malloc(1)!

    // Lazily create a controller for a given view and associate it with a view.
    static func controller(for view: ImageDisplayingView) -> ImageViewController {
        if let controller = objc_getAssociatedObject(view, controllerAK) as? ImageViewController {
            return controller
        }
        let controller = ImageViewController(view: view)
        objc_setAssociatedObject(view, controllerAK, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    // MARK: - Loading Images

    func loadImage(
        with request: ImageRequest?,
        options: ImageLoadingOptions,
        progress: (@MainActor @Sendable (_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
        completion: (@MainActor @Sendable (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
    ) -> ImageTask? {
        cancelOutstandingTask()

        guard let imageView else {
            return nil
        }

        self.options = options

        if options.isPrepareForReuseEnabled { // enabled by default
#if os(iOS) || os(tvOS) || os(visionOS)
            imageView.layer.removeAllAnimations()
#elseif os(macOS)
            let layer = (imageView as? NSView)?.layer ?? imageView.layer
            layer?.removeAllAnimations()
#endif
        }

        // Handle a scenario where request is `nil` (in the same way as a failure)
        guard var request else {
            if options.isPrepareForReuseEnabled {
                imageView.nuke_display(nil)
            }
            let result: Result<ImageResponse, ImagePipeline.Error> = .failure(.imageRequestMissing)
            handle(result: result, isFromMemory: true)
            completion?(result)
            return nil
        }

        let pipeline = options.pipeline ?? ImagePipeline.shared
        if !options.processors.isEmpty && request.processors.isEmpty {
            request.processors = options.processors
        }

        // Quick synchronous memory cache lookup.
        if let image = pipeline.cache[request] {
            display(image, true, .success)
            if !image.isPreview { // Final image was downloaded
                completion?(.success(ImageResponse(container: image, request: request, cacheType: .memory)))
                return nil // No task to perform
            }
        }

        // Display a placeholder.
        if let placeholder = options.placeholder {
            display(ImageContainer(image: placeholder), true, .placeholder)
        } else if options.isPrepareForReuseEnabled {
            imageView.nuke_display(nil) // Remove previously displayed images (if any)
        }

        task = pipeline.loadImage(with: request, progress: { [weak self] response, completedCount, totalCount in
            if let response, options.isProgressiveRenderingEnabled {
                self?.handle(partialImage: response)
            }
            progress?(response, completedCount, totalCount)
        }, completion: { [weak self] result in
            self?.handle(result: result, isFromMemory: false)
            completion?(result)
        })
        return task
    }

    func cancelOutstandingTask() {
        task?.cancel() // The pipeline guarantees no callbacks will be delivered after cancellation
        task = nil
    }

    // MARK: - Handling Responses

    private func handle(result: Result<ImageResponse, ImagePipeline.Error>, isFromMemory: Bool) {
        switch result {
        case let .success(response):
            display(response.container, isFromMemory, .success)
        case .failure:
            if let failureImage = options.failureImage {
                display(ImageContainer(image: failureImage), isFromMemory, .failure)
            }
        }
        self.task = nil
    }

    private func handle(partialImage response: ImageResponse) {
        display(response.container, false, .success)
    }

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

    private func display(_ image: ImageContainer, _ isFromMemory: Bool, _ response: ImageLoadingOptions.ResponseType) {
        guard let imageView else {
            return
        }

        var image = image

#if os(iOS) || os(tvOS) || os(visionOS)
        if let tintColor = options.tintColor(for: response) {
            image.image = image.image.withRenderingMode(.alwaysTemplate)
            imageView.tintColor = tintColor
        }
#endif

        if !isFromMemory || options.alwaysTransition, let transition = options.transition(for: response) {
            switch transition.style {
            case let .fadeIn(params):
                runFadeInTransition(image: image, params: params, response: response)
            case let .custom(closure):
                // The user is responsible for both displaying an image and performing
                // animations.
                closure(imageView, image.image)
            }
        } else {
            imageView.nuke_display(image)
        }

#if os(iOS) || os(tvOS) || os(visionOS)
        if let contentMode = options.contentMode(for: response) {
            imageView.contentMode = contentMode
        }
#endif
    }

#elseif os(watchOS)

    private func display(_ image: ImageContainer, _ isFromMemory: Bool, _ response: ImageLoadingOptions.ResponseType) {
        imageView?.nuke_display(image)
    }

#endif
}

// MARK: - ImageViewController (Transitions)

extension ImageViewController {
#if os(iOS) || os(tvOS) || os(visionOS)

    private func runFadeInTransition(image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters, response: ImageLoadingOptions.ResponseType) {
        guard let imageView else {
            return
        }

        // Special case where it animates between content modes, only works
        // on imageView subclasses.
        if let contentMode = options.contentMode(for: response), imageView.contentMode != contentMode, let imageView = imageView as? UIImageView, imageView.image != nil {
            runCrossDissolveWithContentMode(imageView: imageView, image: image, params: params)
        } else {
            runSimpleFadeIn(image: image, params: params)
        }
    }

    private func runSimpleFadeIn(image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters) {
        guard let imageView else {
            return
        }

        UIView.transition(
            with: imageView,
            duration: params.duration,
            options: params.options.union(.transitionCrossDissolve),
            animations: {
                imageView.nuke_display(image)
            },
            completion: nil
        )
    }

    /// Performs cross-dissolve animation alongside transition to a new content
    /// mode. This isn't natively supported feature and it requires a second
    /// image view. There might be better ways to implement it.
    private func runCrossDissolveWithContentMode(imageView: UIImageView, image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters) {
        // Lazily create a transition view.
        let transitionView = self.transitionImageView

        // Create a transition view which mimics current view's contents.
        transitionView.image = imageView.image
        transitionView.contentMode = imageView.contentMode
        transitionView.frame = imageView.frame
        transitionView.tintColor = imageView.tintColor
        transitionView.tintAdjustmentMode = imageView.tintAdjustmentMode
        if #available(iOS 17.0, tvOS 17.0, *) {
            transitionView.preferredImageDynamicRange = imageView.preferredImageDynamicRange
        }
        transitionView.preferredSymbolConfiguration = imageView.preferredSymbolConfiguration
        transitionView.isHidden = imageView.isHidden
        transitionView.clipsToBounds = imageView.clipsToBounds
        transitionView.layer.cornerRadius = imageView.layer.cornerRadius
        transitionView.layer.cornerCurve = imageView.layer.cornerCurve
        transitionView.layer.maskedCorners = imageView.layer.maskedCorners
        imageView.superview?.insertSubview(transitionView, aboveSubview: imageView)

        // "Manual" cross-fade.
        transitionView.alpha = 1
        imageView.alpha = 0
        imageView.nuke_display(image) // Display new image in current view

        UIView.animate(
            withDuration: params.duration,
            delay: 0,
            options: params.options,
            animations: {
                transitionView.alpha = 0
                imageView.alpha = 1
            },
            completion: { [weak transitionView] isCompleted in
                if isCompleted, let transitionView {
                    transitionView.removeFromSuperview()
                    transitionView.image = nil
                }
            }
        )
    }

#elseif os(macOS)

    private func runFadeInTransition(image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters, response: ImageLoadingOptions.ResponseType) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = params.duration
        animation.fromValue = 0
        animation.toValue = 1
        imageView?.layer?.add(animation, forKey: "imageTransition")

        imageView?.nuke_display(image)
    }

#endif
}

#endif
