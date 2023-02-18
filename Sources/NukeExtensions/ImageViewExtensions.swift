// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if !os(macOS)
import UIKit.UIImage
import UIKit.UIColor
#else
import AppKit.NSImage
#endif

#if os(iOS) || os(tvOS) || os(macOS)

/// Displays images. Add the conformance to this protocol to your views to make
/// them compatible with Nuke image loading extensions.
///
/// The protocol is defined as `@objc` to make it possible to override its
/// methods in extensions (e.g. you can override `nuke_display(image:data:)` in
/// `UIImageView` subclass like `Gifu.ImageView).
///
/// The protocol and its methods have prefixes to make sure they don't clash
/// with other similar methods and protocol in Objective-C runtime.
@MainActor
@objc public protocol Nuke_ImageDisplaying {
    /// Display a given image.
    @objc func nuke_display(image: PlatformImage?, data: Data?)

#if os(macOS)
    @objc var layer: CALayer? { get }
#endif
}

extension Nuke_ImageDisplaying {
    func display(_ container: ImageContainer) {
        nuke_display(image: container.image, data: container.data)
    }
}

#if os(macOS)
extension Nuke_ImageDisplaying {
    public var layer: CALayer? { nil }
}
#endif

#if os(iOS) || os(tvOS)
import UIKit
/// A `UIView` that implements `ImageDisplaying` protocol.
public typealias ImageDisplayingView = UIView & Nuke_ImageDisplaying

extension UIImageView: Nuke_ImageDisplaying {
    /// Displays an image.
    open func nuke_display(image: UIImage?, data: Data? = nil) {
        self.image = image
    }
}
#elseif os(macOS)
import Cocoa
/// An `NSObject` that implements `ImageDisplaying`  and `Animating` protocols.
/// Can support `NSView` and `NSCell`. The latter can return nil for layer.
public typealias ImageDisplayingView = NSObject & Nuke_ImageDisplaying

extension NSImageView: Nuke_ImageDisplaying {
    /// Displays an image.
    open func nuke_display(image: NSImage?, data: Data? = nil) {
        self.image = image
    }
}
#endif

#if os(tvOS)
import TVUIKit

extension TVPosterView: Nuke_ImageDisplaying {
    /// Displays an image.
    open func nuke_display(image: UIImage?, data: Data? = nil) {
        self.image = image
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
    options: ImageLoadingOptions = ImageLoadingOptions.shared,
    into view: ImageDisplayingView,
    completion: @escaping (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void
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
///   - request: The image request. If `nil`, it's handled as a failure scenario.
///   - options: `ImageLoadingOptions.shared` by default.
///   - view: Nuke keeps a weak reference to the view. If the view is deallocated
///   the associated request automatically gets canceled.
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
    options: ImageLoadingOptions = ImageLoadingOptions.shared,
    into view: ImageDisplayingView,
    progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
    completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
) -> ImageTask? {
    let controller = ImageViewController.controller(for: view)
    return controller.loadImage(with: url.map({ ImageRequest(url: $0) }), options: options, progress: progress, completion: completion)
}

/// Loads an image with the given request and displays it in the view.
///
/// See the complete method signature for more information.
@MainActor
@discardableResult public func loadImage(
    with request: ImageRequest?,
    options: ImageLoadingOptions = ImageLoadingOptions.shared,
    into view: ImageDisplayingView,
    completion: @escaping (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void
) -> ImageTask? {
    loadImage(with: request, options: options, into: view, progress: nil, completion: completion)
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
///   - view: Nuke keeps a weak reference to the view. If the view is deallocated
///   the associated request automatically gets canceled.
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
    options: ImageLoadingOptions = ImageLoadingOptions.shared,
    into view: ImageDisplayingView,
    progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
    completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
) -> ImageTask? {
    let controller = ImageViewController.controller(for: view)
    return controller.loadImage(with: request, options: options, progress: progress, completion: completion)
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

#if os(iOS) || os(tvOS)
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

    static var controllerAK = "ImageViewController.AssociatedKey"

    // Lazily create a controller for a given view and associate it with a view.
    static func controller(for view: ImageDisplayingView) -> ImageViewController {
        if let controller = objc_getAssociatedObject(view, &ImageViewController.controllerAK) as? ImageViewController {
            return controller
        }
        let controller = ImageViewController(view: view)
        objc_setAssociatedObject(view, &ImageViewController.controllerAK, controller, .OBJC_ASSOCIATION_RETAIN)
        return controller
    }

    // MARK: - Loading Images

    func loadImage(
        with request: ImageRequest?,
        options: ImageLoadingOptions,
        progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
        completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
    ) -> ImageTask? {
        cancelOutstandingTask()

        guard let imageView = imageView else {
            return nil
        }

        self.options = options

        if options.isPrepareForReuseEnabled { // enabled by default
#if os(iOS) || os(tvOS)
            imageView.layer.removeAllAnimations()
#elseif os(macOS)
            let layer = (imageView as? NSView)?.layer ?? imageView.layer
            layer?.removeAllAnimations()
#endif
        }

        // Handle a scenario where request is `nil` (in the same way as a failure)
        guard var request = request else {
            if options.isPrepareForReuseEnabled {
                imageView.nuke_display(image: nil, data: nil)
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
            imageView.nuke_display(image: nil, data: nil) // Remove previously displayed images (if any)
        }

        task = pipeline.loadImage(with: request, queue: .main, progress: { [weak self] response, completedCount, totalCount in
            if let response = response, options.isProgressiveRenderingEnabled {
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
        task?.cancel() // The pipeline guarantees no callbacks to be deliver after cancellation
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

#if os(iOS) || os(tvOS) || os(macOS)

    private func display(_ image: ImageContainer, _ isFromMemory: Bool, _ response: ImageLoadingOptions.ResponseType) {
        guard let imageView = imageView else {
            return
        }

        var image = image

#if os(iOS) || os(tvOS)
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
            imageView.display(image)
        }

#if os(iOS) || os(tvOS)
        if let contentMode = options.contentMode(for: response) {
            imageView.contentMode = contentMode
        }
#endif
    }

#elseif os(watchOS)

    private func display(_ image: ImageContainer, _ isFromMemory: Bool, _ response: ImageLoadingOptions.ResponseType) {
        imageView?.display(image)
    }

#endif
}

// MARK: - ImageViewController (Transitions)

extension ImageViewController {
#if os(iOS) || os(tvOS)

    private func runFadeInTransition(image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters, response: ImageLoadingOptions.ResponseType) {
        guard let imageView = imageView else {
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
        guard let imageView = imageView else {
            return
        }

        UIView.transition(
            with: imageView,
            duration: params.duration,
            options: params.options.union(.transitionCrossDissolve),
            animations: {
                imageView.nuke_display(image: image.image, data: image.data)
            },
            completion: nil
        )
    }

    /// Performs cross-dissolve animation alonside transition to a new content
    /// mode. This isn't natively supported feature and it requires a second
    /// image view. There might be better ways to implement it.
    private func runCrossDissolveWithContentMode(imageView: UIImageView, image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters) {
        // Lazily create a transition view.
        let transitionView = self.transitionImageView

        // Create a transition view which mimics current view's contents.
        transitionView.image = imageView.image
        transitionView.contentMode = imageView.contentMode
        imageView.addSubview(transitionView)
        transitionView.frame = imageView.bounds

        // "Manual" cross-fade.
        transitionView.alpha = 1
        imageView.alpha = 0
        imageView.display(image) // Display new image in current view

        UIView.animate(
            withDuration: params.duration,
            delay: 0,
            options: params.options,
            animations: {
                transitionView.alpha = 0
                imageView.alpha = 1
            },
            completion: { isCompleted in
                if isCompleted {
                    transitionView.removeFromSuperview()
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

        imageView?.display(image)
    }

#endif
}

#endif
