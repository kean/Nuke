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
@discardableResult public func loadImage(with url: URL, options: ImageLoadingOptions = ImageLoadingOptions(), into view: ImageView) -> ImageTask? {
    return loadImage(with: ImageRequest(url: url), options: options, into: view)
}

/// Loads an image into the given image view. Cancels previous outstanding request
/// associated with the view.
///
/// If the image is stored in the memory cache, the image is displayed
/// immediately. The image is loaded using the pipeline object otherwise.
///
/// Nuke keeps a weak reference to the view. If the view is deallocated
/// the associated request automatically gets cancelled.
@discardableResult public func loadImage(with request: ImageRequest, options: ImageLoadingOptions = ImageLoadingOptions(), into view: ImageView) -> ImageTask? {
    assert(Thread.isMainThread)

    let context = getContext(for: view)
    context.task?.cancel() // cancel outstanding request if any
    context.task = nil

    // Quick synchronous memory cache lookup
    if request.memoryCacheOptions.readAllowed,
        let imageCache = options.pipeline.configuration.imageCache,
        let response = imageCache.cachedResponse(for: request) {
        _update(view, options: options, response: response, error: nil, isFromMemoryCache: true)
        return nil
    }

    if let placeholder = options.placeholder {
        view.image = placeholder
    }

    // Make sure that cell reuse is handled correctly.
    context.taskId += 1
    let taskId = context.taskId

    // Start the request
    // Manager assumes that Loader calls completion on the main thread.
    context.task = options.pipeline.loadImage(with: request) { [weak context, weak view] response, error in
        guard let view = view, let context = context, context.taskId == taskId else { return }
        _update(view, options: options, response: response, error: error, isFromMemoryCache: false)
        context.task = nil
    }
    return context.task
}

private func _update(_ view: ImageView, options: ImageLoadingOptions, response: ImageResponse?, error: Error?, isFromMemoryCache: Bool) {
    if let image = response?.image {
        func _add(animation: CAAnimation) {
            let layer: CALayer? = view.layer // Make compiler happy on macOS
            layer?.add(animation, forKey: "imageTransition")
        }
        switch options.transition {
        case .none:
            view.image = image
        case let .custom(transition):
            transition(view, image, isFromMemoryCache)
        case let .opacity(duration):
            if !isFromMemoryCache {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.duration = duration
                animation.fromValue = 0
                animation.toValue = 1
                _add(animation: animation)
            }
            view.image = image
        case let .crossDissolve(duration):
            if !isFromMemoryCache {
                let animation = CABasicAnimation(keyPath: "contents")
                animation.duration = duration
                animation.fromValue = view.image?.cgImage
                animation.toValue = image.cgImage
                _add(animation: animation)
            }
            view.image = image
        }
    }
    options.completion?(response, error, isFromMemoryCache)
}

/// Cancels an outstanding request associated with the view.
public func cancelRequest(for view: ImageView) {
    assert(Thread.isMainThread)
    let context = getContext(for: view)
    context.task?.cancel() // cancel outstanding request if any
    context.task = nil // unregister request
}

public struct ImageLoadingOptions {
    /// Placeholder to be set before loading an image. `nil` by default.
    public var placeholder: Image?

    public var transition: Transition

    /// The pipeline to be used. `ImagePipeline.shared` by default.
    public var pipeline: ImagePipeline

    /// Completion handler to be called when the requests is finished and image
    /// is displayed. `nil` by default.
    public var completion: ((ImageResponse?, Error?, Bool) -> Void)?

    public enum Transition {
        case none
        case opacity(TimeInterval)
        case crossDissolve(TimeInterval)
        case custom((ImageView, Image, _ isFromMemCache: Bool) -> Void)
    }

    /// - parameter pipeline: `ImagePipeline.shared` by default.
    /// - parameter placeholder: `nil` by default.
    /// - parameter transition: The image transition animation performed when
    /// displaying a loaded image. `.none` by default.
    /// - parameter completion: Completion closure to be called when request
    /// is finished and transition is started. `nil` by default.
    public init(placeholder: Image? = nil, transition: Transition = .none, pipeline: ImagePipeline = ImagePipeline.shared, completion: ((ImageResponse?, Error?, Bool) -> Void)? = nil) {
        self.placeholder = placeholder
        self.transition = transition
        self.pipeline = pipeline
        self.completion = completion
    }
}

// MARK: - Managing Context

// Lazily create context for a given view and associate it with a view.
private func getContext(for view: ImageView) -> Context {
    // Associated objects is a simplest way to bind Context and View lifetimes
    // The implementation might change in the future.
    if let ctx = objc_getAssociatedObject(view, &Context.contextAK) as? Context {
        return ctx
    }
    let ctx = Context()
    objc_setAssociatedObject(view, &Context.contextAK, ctx, .OBJC_ASSOCIATION_RETAIN)
    return ctx
}

// Context is reused for multiple requests which makes sense, because in
// most cases image views are also going to be reused (e.g. in a table view)
private final class Context {
    weak var task: ImageTask?
    var taskId: Int = 0

    // Automatically cancel the request when view is deallocated.
    deinit {
        task?.cancel()
    }

    static var contextAK = "Context.AssociatedKey"
}

#endif
