// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(macOS)
import AppKit.NSImage
/// Alias for `NSImage`.
public typealias Image = NSImage
#else
import UIKit.UIImage
/// Alias for `UIImage`.
public typealias Image = UIImage
#endif

#if !os(watchOS)

#if os(macOS)
import Cocoa
/// Alias for `NSImageView`
public typealias ImageView = NSImageView
#else
import UIKit
/// Alias for `UIImageView`
public typealias ImageView = UIImageView
#endif

/// Loads an image into the given image view. For more info See the corresponding
/// `loadImage(with:options:into:)` method that works with `ImageRequest`.
/// - parameter completion: Completion handler to be called when the requests is
/// finished and image is displayed. `nil` by default.
@discardableResult public func loadImage(with url: URL, into view: ImageView, completion: ((ImageResponse?, Error?, Bool) -> Void)? = nil) -> ImageTask? {
    return loadImage(with: ImageRequest(url: url), into: view, completion: completion)
}

/// Loads an image into the given image view. Cancels previous outstanding request
/// associated with the view.
/// - parameter completion: Completion handler to be called when the requests is
/// finished and image is displayed. `nil` by default.
///
/// If the image is stored in the memory cache, the image is displayed
/// immediately. The image is loaded using the pipeline object otherwise.
///
/// Nuke keeps a weak reference to the view. If the view is deallocated
/// the associated request automatically gets cancelled.
@discardableResult public func loadImage(with request: ImageRequest, into view: ImageView, completion: ((ImageResponse?, Error?, Bool) -> Void)? = nil) -> ImageTask? {
    assert(Thread.isMainThread)

    let context = Context.context(for: view)
    context.task?.cancel() // cancel outstanding request if any
    context.task = nil

    // Make a copy of options.
    let options = context.options

    // Prepare for reuse.
    if options.isPrepareForReuseEnabled { // enabled by default
        view.image = nil
        #if os(macOS)
        view.layer?.removeAllAnimations()
        #else
        view.layer.removeAllAnimations()
        #endif
    }

    // Quick synchronous memory cache lookup
    if request.memoryCacheOptions.readAllowed,
        let imageCache = options.pipeline.configuration.imageCache,
        let response = imageCache.cachedResponse(for: request) {
        view._handle(response: response, error: nil, fromMemCache: true, options: options)
        completion?(response, nil, true)
        return nil
    }

    // Display a placeholder.
    if let placeholder = options.placeholder {
        view.image = placeholder
        #if !os(macOS)
        if let contentMode = options.contentModes?.placeholder {
            view.contentMode = contentMode
        }
        #endif
    }

    // Make sure that cell reuse is handled correctly.
    context.taskId += 1
    let taskId = context.taskId

    // Start the request
    // Manager assumes that Loader calls completion on the main thread.
    context.task = options.pipeline.loadImage(with: request) { [weak context, weak view] response, error in
        guard let view = view, let context = context, context.taskId == taskId else { return }
        view._handle(response: response, error: error, fromMemCache: false, options: options)
        completion?(response, error, false)
        context.task = nil
    }
    return context.task
}

private extension ImageView {
    func _handle(response: ImageResponse?, error: Error?, fromMemCache: Bool, options: ImageViewOptions) {
        #if !os(macOS)
        if let image = response?.image {
            _display(image, options.transition, fromMemCache, options.contentModes?.success)
        } else if let failureImage = options.failureImage {
            _display(failureImage, options.failureImageTransition, fromMemCache, options.contentModes?.failure)
        }
        #else // NSImageView doesn't support content mode, unfortunately.
        if let image = response?.image {
            _display(image, options.transition, fromMemCache, nil)
        } else if let failureImage = options.failureImage {
            _display(failureImage, options.failureImageTransition, fromMemCache, nil)
        }
        #endif
    }

    #if !os(macOS)
    private typealias _ContentMode = UIViewContentMode
    #else
    private typealias _ContentMode = Void // There is no content mode on macOS
    #endif

    private func _display(_ image: Image, _ transition: ImageViewOptions.Transition, _ fromMemCache: Bool, _ newContentMode: _ContentMode?) {
        switch transition {
        case .none:
            self.image = image
        case let .custom(transition):
            // The user is reponsible for both displaying an image and performing
            // animations.
            transition(self, image, fromMemCache)
        case let .opacity(duration):
            if !fromMemCache {
                _animateOpacity(from: 0, to: 1, duration: duration)
            }
            self.image = image
        case let .crossDissolve(duration):
            if !fromMemCache {
                #if !os(macOS)
                if let newContentMode = newContentMode, self.contentMode != newContentMode, self.image != nil {
                    _animateCrossDissolveTransitioningToContentMode(contentMode: newContentMode, from: self.image, to: image, duration: duration)
                } else {
                    _animateCrossDissolve(from: self.image, to: image, duration: duration)
                }
                #else
                _animateCrossDissolve(from: self.image, to: image, duration: duration)
                #endif
            }
            self.image = image
        }

        #if !os(macOS)
        if let newContentMode = newContentMode {
            self.contentMode = newContentMode
        }
        #endif
    }
}

/// Cancels an outstanding request associated with the view.
public func cancelRequest(for view: ImageView) {
    assert(Thread.isMainThread)
    let context = Context.context(for: view)
    context.task?.cancel() // cancel outstanding request if any
    context.task = nil // unregister request
}

// MARK: - ImageViewOptions

public struct ImageViewOptions {
    /// Placeholder to be set before loading an image. `nil` by default.
    public var placeholder: Image?

    /// The image transition animation performed when displaying a loaded image
    /// `.none` by default.
    public var transition: Transition = .none

    /// Image to be displayd when request fails. `nil` by default.
    public var failureImage: Image?

    /// The image transition animation performed when displaying a failure image
    /// `.none` by default.
    public var failureImageTransition: Transition = .none

    /// If true, every time you request a new image for a view, the view will be
    /// automatically prepared for reuse: image will be set to `nil`, and animations
    /// will be removed. `true` by default.
    public var isPrepareForReuseEnabled = true

    /// The pipeline to be used. `ImagePipeline.shared` by default.
    public var pipeline: ImagePipeline = ImagePipeline.shared

    #if !os(macOS)
    /// Custom content modes to be used when switching between images. It's very
    /// often when a "failure" image needs a `.center` mode when a "success" image
    /// needs something like `.scaleAspectFill`. `nil`  by default (don't change
    /// content mode).
    public var contentModes: ContentModes?

    public struct ContentModes {
        public var success: UIViewContentMode = .scaleAspectFill
        public var failure: UIViewContentMode = .center
        public var placeholder: UIViewContentMode = .center

        public init(success: UIViewContentMode = .scaleAspectFill, failure: UIViewContentMode = .center, placeholder: UIViewContentMode = .center) {
            self.success = success; self.failure = failure; self.placeholder = placeholder
        }
    }
    #endif

    public enum Transition {
        case none
        case opacity(TimeInterval)
        case crossDissolve(TimeInterval)
        case custom((ImageView, Image, _ isFromMemCache: Bool) -> Void)
    }

    public init() {}
}

public extension ImageView {
    public var options: ImageViewOptions {
        get { return Context.context(for: self).options }
        set { Context.context(for: self).options = newValue }
    }
}

// MARK: - Managing Context

// Context is reused for multiple requests which makes sense, because in most
// cases image views are also going to be reused (e.g. cells in a table view).
private final class Context {
    weak var task: ImageTask?
    var taskId: Int = 0
    var options = ImageViewOptions()

    // Image view used for cross-fade transition between images with different
    // content modes.
    lazy var transitionImageView = ImageView()

    // Automatically cancel the request when the view is deallocated.
    deinit {
        task?.cancel()
    }

    static var contextAK = "Context.AssociatedKey"

    // Lazily create a context for a given view and associate it with a view.
    static func context(for view: ImageView) -> Context {
        if let ctx = objc_getAssociatedObject(view, &Context.contextAK) as? Context {
            return ctx
        }
        let ctx = Context()
        objc_setAssociatedObject(view, &Context.contextAK, ctx, .OBJC_ASSOCIATION_RETAIN)
        return ctx
    }
}

#endif

// MARK: - Animations

private extension ImageView {
    private func _add(animation: CAAnimation) {
        #if os(macOS)
        layer?.add(animation, forKey: "imageTransition")
        #else
        layer.add(animation, forKey: "imageTransition")
        #endif
    }

    func _animateOpacity(from: CGFloat, to: CGFloat, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = duration
        animation.fromValue = from
        animation.toValue = to
        _add(animation: animation)
    }

    func _animateCrossDissolve(from: Image?, to: Image?, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "contents")
        animation.duration = duration
        animation.fromValue = from?.cgImage
        animation.toValue = to?.cgImage
        _add(animation: animation)
    }

    #if !os(macOS)
    /// Performs cross-dissolve animation alonside transition to a new content
    /// mode. This isn't natively supported feature and it requires a second
    /// image view. There might be better ways to implement it.
    func _animateCrossDissolveTransitioningToContentMode(contentMode: UIViewContentMode, from: Image?, to: Image?, duration: TimeInterval) {
        // Lazily create a transition view.
        let transitionView = Context.context(for: self).transitionImageView

        // Create a transition view which mimics current view's contents.
        transitionView.image = self.image
        transitionView.contentMode = self.contentMode
        addSubview(transitionView)
        transitionView.frame = self.bounds

        // "Manual" cross-fade.
        transitionView.alpha = 1
        self.alpha = 0
        UIView.animate(
            withDuration: duration,
            animations: {
                transitionView.alpha = 0
                self.alpha = 1
        },
            completion: { isCompleted in
                if isCompleted {
                    transitionView.removeFromSuperview()
                }
        })
    }
    #endif
}
