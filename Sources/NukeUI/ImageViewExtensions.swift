// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// Displays images. Add the conformance to this protocol to your views to make
/// them compatible with Nuke image loading extensions.
///
/// The protocol is defined as `@objc` to make it possible to override its
/// methods in extensions (e.g. you can override `nuke_display(image:)` in
/// `UIImageView` subclass like `Gifu.ImageView).
///
/// The protocol and its methods have prefixes to make sure they don't clash
/// with other similar methods and protocol in Objective-C runtime.
@objc public protocol Nuke_ImageDisplaying {
    /// Display a given image.
    @objc func nuke_display(image: PlatformImage?)

    #if os(macOS)
    @objc var layer: CALayer? { get }
    #endif
}

#if os(macOS)
public extension Nuke_ImageDisplaying {
    var layer: CALayer? { nil }
}
#endif

#if os(iOS) || os(tvOS)
import UIKit
/// A `UIView` that implements `ImageDisplaying` protocol.
public typealias ImageDisplayingView = UIView & Nuke_ImageDisplaying

extension UIImageView: Nuke_ImageDisplaying {
    /// Displays an image.
    open func nuke_display(image: UIImage?) {
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
    open func nuke_display(image: NSImage?) {
        self.image = image
    }
}
#elseif os(watchOS)
import WatchKit

/// A `WKInterfaceObject` that implements `ImageDisplaying` protocol.
public typealias ImageDisplayingView = WKInterfaceObject & Nuke_ImageDisplaying

extension WKInterfaceImage: Nuke_ImageDisplaying {
    /// Displays an image.
    open func nuke_display(image: UIImage?) {
        self.setImage(image)
    }
}
#endif

// MARK: - ImageView Extensions

@discardableResult
public func loadImage(with request: ImageRequestConvertible,
                      options: ImageLoadingOptions = ImageLoadingOptions.shared,
                      into view: ImageDisplayingView,
                      completion: @escaping (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void) -> ImageTask? {
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
/// - parameter options: `ImageLoadingOptions.shared` by default.
/// - parameter view: Nuke keeps a weak reference to the view. If the view is deallocated
/// the associated request automatically gets canceled.
/// - parameter progress: A closure to be called periodically on the main thread
/// when the progress is updated. `nil` by default.
/// - parameter completion: A closure to be called on the main thread when the
/// request is finished. Gets called synchronously if the response was found in
/// the memory cache. `nil` by default.
/// - returns: An image task or `nil` if the image was found in the memory cache.
@discardableResult
public func loadImage(with request: ImageRequestConvertible,
                      options: ImageLoadingOptions = ImageLoadingOptions.shared,
                      into view: ImageDisplayingView,
                      progress: ((_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void)? = nil,
                      completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) -> ImageTask? {
    assert(Thread.isMainThread)
    let controller = ImageViewController.controller(for: view)
    return controller.loadImage(with: request.asImageRequest(), options: options, progress: progress, completion: completion)
}

/// Cancels an outstanding request associated with the view.
public func cancelRequest(for view: ImageDisplayingView) {
    assert(Thread.isMainThread)
    ImageViewController.controller(for: view).cancelOutstandingTask()
}

// MARK: - ImageLoadingOptions

/// A range of options that control how the image is loaded and displayed.
public struct ImageLoadingOptions {
    /// Shared options.
    public static var shared = ImageLoadingOptions()

    /// Placeholder to be displayed when the image is loading. `nil` by default.
    public var placeholder: PlatformImage?

    /// Image to be displayed when the request fails. `nil` by default.
    public var failureImage: PlatformImage?

    #if os(iOS) || os(tvOS) || os(macOS)

    /// The image transition animation performed when displaying a loaded image.
    /// Only runs when the image was not found in memory cache. `nil` by default.
    public var transition: Transition?

    /// The image transition animation performed when displaying a failure image.
    /// `nil` by default.
    public var failureImageTransition: Transition?

    /// If true, the requested image will always appear with transition, even
    /// when loaded from cache.
    public var alwaysTransition = false

    #endif

    /// If true, every time you request a new image for a view, the view will be
    /// automatically prepared for reuse: image will be set to `nil`, and animations
    /// will be removed. `true` by default.
    public var isPrepareForReuseEnabled = true

    /// If `true`, every progressively generated preview produced by the pipeline
    /// is going to be displayed. `true` by default.
    ///
    /// - note: To enable progressive decoding, see `ImagePipeline.Configuration`,
    /// `isProgressiveDecodingEnabled` option.
    public var isProgressiveRenderingEnabled = true

    /// Custom pipeline to be used. `nil` by default.
    public var pipeline: ImagePipeline?

    #if os(iOS) || os(tvOS)

    /// Content modes to be used for each image type (placeholder, success,
    /// failure). `nil`  by default (don't change content mode).
    public var contentModes: ContentModes?

    /// Custom content modes to be used for each image type (placeholder, success,
    /// failure).
    public struct ContentModes {
        /// Content mode to be used for the loaded image.
        public var success: UIView.ContentMode
        /// Content mode to be used when displaying a `failureImage`.
        public var failure: UIView.ContentMode
        /// Content mode to be used when displaying a `placeholder`.
        public var placeholder: UIView.ContentMode

        /// - parameter success: A content mode to be used with a loaded image.
        /// - parameter failure: A content mode to be used with a `failureImage`.
        /// - parameter placeholder: A content mode to be used with a `placeholder`.
        public init(success: UIView.ContentMode, failure: UIView.ContentMode, placeholder: UIView.ContentMode) {
            self.success = success; self.failure = failure; self.placeholder = placeholder
        }
    }

    /// Tint colors to be used for each image type (placeholder, success,
    /// failure). `nil`  by default (don't change tint color or rendering mode).
    public var tintColors: TintColors?

    /// Custom tint color to be used for each image type (placeholder, success,
    /// failure).
    public struct TintColors {
        /// Tint color to be used for the loaded image.
        public var success: UIColor?
        /// Tint color to be used when displaying a `failureImage`.
        public var failure: UIColor?
        /// Tint color to be used when displaying a `placeholder`.
        public var placeholder: UIColor?

        /// - parameter success: A tint color to be used with a loaded image.
        /// - parameter failure: A tint color to be used with a `failureImage`.
        /// - parameter placeholder: A tint color to be used with a `placeholder`.
        public init(success: UIColor?, failure: UIColor?, placeholder: UIColor?) {
            self.success = success; self.failure = failure; self.placeholder = placeholder
        }
    }

    #endif

    #if os(iOS) || os(tvOS)

    /// - parameter placeholder: Placeholder to be displayed when the image is
    /// loading . `nil` by default.
    /// - parameter transition: The image transition animation performed when
    /// displaying a loaded image. Only runs when the image was not found in
    /// memory cache. `nil` by default (no animations).
    /// - parameter failureImage: Image to be displayd when request fails.
    /// `nil` by default.
    /// - parameter failureImageTransition: The image transition animation
    /// performed when displaying a failure image. `nil` by default.
    /// - parameter contentModes: Content modes to be used for each image type
    /// (placeholder, success, failure). `nil` by default (don't change content mode).
    public init(placeholder: UIImage? = nil, transition: Transition? = nil, failureImage: UIImage? = nil, failureImageTransition: Transition? = nil, contentModes: ContentModes? = nil, tintColors: TintColors? = nil) {
        self.placeholder = placeholder
        self.transition = transition
        self.failureImage = failureImage
        self.failureImageTransition = failureImageTransition
        self.contentModes = contentModes
        self.tintColors = tintColors
    }

    #elseif os(macOS)

    public init(placeholder: NSImage? = nil, transition: Transition? = nil, failureImage: NSImage? = nil, failureImageTransition: Transition? = nil) {
        self.placeholder = placeholder
        self.transition = transition
        self.failureImage = failureImage
        self.failureImageTransition = failureImageTransition
    }

    #elseif os(watchOS)

    public init(placeholder: UIImage? = nil, failureImage: UIImage? = nil) {
        self.placeholder = placeholder
        self.failureImage = failureImage
    }

    #endif

    #if os(iOS) || os(tvOS)

    /// An animated image transition.
    public struct Transition {
        var style: Style

        enum Style { // internal representation
            case fadeIn(parameters: Parameters)
            case custom((ImageDisplayingView, UIImage) -> Void)
        }

        struct Parameters { // internal representation
            let duration: TimeInterval
            let options: UIView.AnimationOptions
        }

        /// Fade-in transition (cross-fade in case the image view is already
        /// displaying an image).
        public static func fadeIn(duration: TimeInterval, options: UIView.AnimationOptions = .allowUserInteraction) -> Transition {
            Transition(style: .fadeIn(parameters: Parameters(duration: duration, options: options)))
        }

        /// Custom transition. Only runs when the image was not found in memory cache.
        public static func custom(_ closure: @escaping (ImageDisplayingView, UIImage) -> Void) -> Transition {
            Transition(style: .custom(closure))
        }
    }

    #elseif os(macOS)

    /// An animated image transition.
    public struct Transition {
        var style: Style

        enum Style { // internal representation
            case fadeIn(parameters: Parameters)
            case custom((ImageDisplayingView, NSImage) -> Void)
        }

        struct Parameters { // internal representation
            let duration: TimeInterval
        }

        /// Fade-in transition.
        public static func fadeIn(duration: TimeInterval) -> Transition {
            Transition(style: .fadeIn(parameters: Parameters(duration: duration)))
        }

        /// Custom transition. Only runs when the image was not found in memory cache.
        public static func custom(_ closure: @escaping (ImageDisplayingView, NSImage) -> Void) -> Transition {
            Transition(style: .custom(closure))
        }
    }

    #endif

    public init() {}
}

// MARK: - ImageViewController

/// Manages image requests on behalf of an image view.
///
/// - note: With a few modifications this might become public at some point,
/// however as it stands today `ImageViewController` is just a helper class,
/// making it public wouldn't expose any additional functionality to the users.
private final class ImageViewController {
    private weak var imageView: ImageDisplayingView?
    private var task: ImageTask?

    // Automatically cancel the request when the view is deallocated.
    deinit {
        cancelOutstandingTask()
    }

    init(view: /* weak */ ImageDisplayingView) {
        self.imageView = view
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

    func loadImage(with request: ImageRequest,
                   options: ImageLoadingOptions,
                   progress progressHandler: ((_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void)? = nil,
                   completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) -> ImageTask? {
        cancelOutstandingTask()

        guard let imageView = imageView else {
            return nil
        }

        if options.isPrepareForReuseEnabled { // enabled by default
            #if os(iOS) || os(tvOS)
            imageView.layer.removeAllAnimations()
            #elseif os(macOS)
            let layer = (imageView as? NSView)?.layer ?? imageView.layer
            layer?.removeAllAnimations()
            #endif
        }

        let pipeline = options.pipeline ?? ImagePipeline.shared

        // Quick synchronous memory cache lookup.
        if let image = pipeline.cache[request] {
            let response = ImageResponse(container: image, cacheType: .memory)
            handle(result: .success(response), fromMemCache: true, options: options)
            if !image.isPreview { // Final image was downloaded
                completion?(.success(response))
                return nil // No task to perform
            }
        }

        // Display a placeholder.
        if var placeholder = options.placeholder {
            #if os(iOS) || os(tvOS)
            if let tintColor = options.tintColors?.placeholder {
                placeholder = placeholder.withRenderingMode(.alwaysTemplate)
                imageView.tintColor = tintColor
            }
            if let contentMode = options.contentModes?.placeholder {
                imageView.contentMode = contentMode
            }
            #endif
            imageView.nuke_display(image: placeholder)
        } else if options.isPrepareForReuseEnabled {
            imageView.nuke_display(image: nil) // Remove previously displayed images (if any)
        }

        task = pipeline.loadImage(with: request, queue: .main, progress: { [weak self] response, completedCount, totalCount in
            if let response = response, options.isProgressiveRenderingEnabled {
                self?.handle(partialImage: response, options: options)
            }
            progressHandler?(response, completedCount, totalCount)
        }, completion: { [weak self] result in
            self?.handle(result: result, fromMemCache: false, options: options)
            completion?(result)
        })
        return task
    }

    func cancelOutstandingTask() {
        task?.cancel() // The pipeline guarantees no callbacks to be deliver after cancellation
        task = nil
    }

    // MARK: - Handling Responses

    #if os(iOS) || os(tvOS)

    private func handle(result: Result<ImageResponse, ImagePipeline.Error>, fromMemCache: Bool, options: ImageLoadingOptions) {
        switch result {
        case let .success(response):
            display(response.image, options.transition, options.alwaysTransition, fromMemCache, options.contentModes?.success, options.tintColors?.success)
        case .failure:
            if let failureImage = options.failureImage {
                display(failureImage, options.failureImageTransition, options.alwaysTransition, fromMemCache, options.contentModes?.failure, options.tintColors?.failure)
            }
        }
        self.task = nil
    }

    private func handle(partialImage response: ImageResponse, options: ImageLoadingOptions) {
        display(response.image, options.transition, options.alwaysTransition, false, options.contentModes?.success, options.tintColors?.success)
    }

    // swiftlint:disable:next function_parameter_count
    private func display(_ image: UIImage, _ transition: ImageLoadingOptions.Transition?, _ alwaysTransition: Bool, _ fromMemCache: Bool, _ newContentMode: UIView.ContentMode?, _ newTintColor: UIColor?) {
        guard let imageView = imageView else {
            return
        }

        var image = image

        if let newTintColor = newTintColor {
            image = image.withRenderingMode(.alwaysTemplate)
            imageView.tintColor = newTintColor
        }

        if !fromMemCache || alwaysTransition, let transition = transition {
            switch transition.style {
            case let .fadeIn(params):
                runFadeInTransition(image: image, params: params, contentMode: newContentMode)
            case let .custom(closure):
                // The user is reponsible for both displaying an image and performing
                // animations.
                closure(imageView, image)
            }
        } else {
            imageView.nuke_display(image: image)
        }
        if let newContentMode = newContentMode {
            imageView.contentMode = newContentMode
        }
    }

    // Image view used for cross-fade transition between images with different
    // content modes.
    private lazy var transitionImageView = UIImageView()

    private func runFadeInTransition(image: UIImage, params: ImageLoadingOptions.Transition.Parameters, contentMode: UIView.ContentMode?) {
        guard let imageView = imageView else {
            return
        }

        // Special case where it animates between content modes, only works
        // on imageView subclasses.
        if let contentMode = contentMode, imageView.contentMode != contentMode, let imageView = imageView as? UIImageView, imageView.image != nil {
            runCrossDissolveWithContentMode(imageView: imageView, image: image, params: params)
        } else {
            runSimpleFadeIn(image: image, params: params)
        }
    }

    private func runSimpleFadeIn(image: UIImage, params: ImageLoadingOptions.Transition.Parameters) {
        guard let imageView = imageView else {
            return
        }

        UIView.transition(
            with: imageView,
            duration: params.duration,
            options: params.options.union(.transitionCrossDissolve),
            animations: {
                imageView.nuke_display(image: image)
            },
            completion: nil
        )
    }

    /// Performs cross-dissolve animation alonside transition to a new content
    /// mode. This isn't natively supported feature and it requires a second
    /// image view. There might be better ways to implement it.
    private func runCrossDissolveWithContentMode(imageView: UIImageView, image: UIImage, params: ImageLoadingOptions.Transition.Parameters) {
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
        imageView.image = image // Display new image in current view

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

    private func handle(result: Result<ImageResponse, ImagePipeline.Error>, fromMemCache: Bool, options: ImageLoadingOptions) {
        // NSImageView doesn't support content mode, unfortunately.
        switch result {
        case let .success(response):
            display(response.image, options.transition, options.alwaysTransition, fromMemCache)
        case .failure:
            if let failureImage = options.failureImage {
                display(failureImage, options.failureImageTransition, options.alwaysTransition, fromMemCache)
            }
        }
        self.task = nil
    }

    private func handle(partialImage response: ImageResponse, options: ImageLoadingOptions) {
        display(response.image, options.transition, options.alwaysTransition, false)
    }

    private func display(_ image: NSImage, _ transition: ImageLoadingOptions.Transition?, _ alwaysTransition: Bool, _ fromMemCache: Bool) {
        guard let imageView = imageView else {
            return
        }

        if !fromMemCache || alwaysTransition, let transition = transition {
            switch transition.style {
            case let .fadeIn(params):
                runFadeInTransition(image: image, params: params)
            case let .custom(closure):
                // The user is reponsible for both displaying an image and performing
                // animations.
                closure(imageView, image)
            }
        } else {
            imageView.nuke_display(image: image)
        }
    }

    private func runFadeInTransition(image: NSImage, params: ImageLoadingOptions.Transition.Parameters) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = params.duration
        animation.fromValue = 0
        animation.toValue = 1
        imageView?.layer?.add(animation, forKey: "imageTransition")

        imageView?.nuke_display(image: image)
    }

    #elseif os(watchOS)

    private func handle(result: Result<ImageResponse, ImagePipeline.Error>, fromMemCache: Bool, options: ImageLoadingOptions) {
        switch result {
        case let .success(response):
            imageView?.nuke_display(image: response.image)
        case .failure:
            if let failureImage = options.failureImage {
                imageView?.nuke_display(image: failureImage)
            }
        }
        self.task = nil
    }

    private func handle(partialImage response: ImageResponse, options: ImageLoadingOptions) {
        imageView?.nuke_display(image: response.image)
    }

    #endif
}
