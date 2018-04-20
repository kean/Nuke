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

/// Represents a target for image loading.
public protocol ImageTarget: class {
    /// Callback that gets called when the request is completed.
    func handle(response: Result<Image>, isFromMemoryCache: Bool)
}

/// Loads an image into the given target. See the corresponding
/// `loadImage(with:into)` method that takes `Request` for more info.
@discardableResult public func loadImage(with url: URL, pipeline: ImagePipeline = ImagePipeline.shared, into target: ImageTarget) -> ImageTask? {
    return loadImage(with: ImageRequest(url: url), pipeline: pipeline, into: target)
}

/// Loads an image into the given target. Cancels previous outstanding request
/// associated with the target.
///
/// If the image is stored in the memory cache, the image is displayed
/// immediately. The image is loaded using the `loader` object otherwise.
///
/// `Manager` keeps a weak reference to the target. If the target deallocates
/// the associated request automatically gets cancelled.
@discardableResult public func loadImage(with request: ImageRequest, pipeline: ImagePipeline = ImagePipeline.shared, into target: ImageTarget) -> ImageTask? {
    assert(Thread.isMainThread)

    let context = getContext(for: target)
    context.task?.cancel() // cancel outstanding request if any
    context.task = nil

    // Quick synchronous memory cache lookup
    if request.memoryCacheOptions.readAllowed,
        let image = pipeline.configuration.imageCache?[request] {
        target.handle(response: .success(image), isFromMemoryCache: true)
        return nil
    }

    // Make sure that cell reuse is handled correctly.
    context.taskId += 1
    let taskId = context.taskId

    // Start the request
    // Manager assumes that Loader calls completion on the main thread.
    context.task = pipeline.loadImage(with: request) { [weak context, weak target] in
        guard let context = context, context.taskId == taskId else { return }
        target?.handle(response: $0, isFromMemoryCache: false)
        context.task = nil
    }
    return context.task
}

/// Cancels an outstanding request associated with the target.
public func cancelRequest(for target: ImageTarget) {
    _cancelRequest(for: target)
}

private func _cancelRequest(for target: AnyObject) {
    assert(Thread.isMainThread)
    let context = getContext(for: target)
    context.task?.cancel() // cancel outstanding request if any
    context.task = nil // unregister request
}

// MARK: - Managing Context

// Lazily create context for a given target and associate it with a target.
private func getContext(for target: AnyObject) -> Context {
    // Associated objects is a simplest way to bind Context and Target lifetimes
    // The implementation might change in the future.
    if let ctx = objc_getAssociatedObject(target, &Context.contextAK) as? Context {
        return ctx
    }
    let ctx = Context()
    objc_setAssociatedObject(target, &Context.contextAK, ctx, .OBJC_ASSOCIATION_RETAIN)
    return ctx
}

// Context is reused for multiple requests which makes sense, because in
// most cases image views are also going to be reused (e.g. in a table view)
private final class Context {
    weak var task: ImageTask?
    var taskId: Int = 0

    // Automatically cancel the request when target deallocates.
    deinit {
        task?.cancel()
    }

    static var contextAK = "Context.AssociatedKey"
}

#if os(macOS)
import Cocoa
/// Alias for `NSImageView`
public typealias ImageView = NSImageView
#elseif os(iOS) || os(tvOS)
import UIKit
/// Alias for `UIImageView`
public typealias ImageView = UIImageView
#endif

#if os(macOS) || os(iOS) || os(tvOS)
/// Default implementation of `ImageTarget` protocol for `ImageView`.
extension ImageView: ImageTarget {
    /// Displays an image on success. Runs `opacity` transition if
    /// the response was not from the memory cache.
    public func handle(response: Result<Image>, isFromMemoryCache: Bool) {
        guard let image = response.value else { return }
        self.image = image
        if !isFromMemoryCache {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.duration = 0.25
            animation.fromValue = 0
            animation.toValue = 1
            let layer: CALayer? = self.layer // Make compiler happy on macOS
            layer?.add(animation, forKey: "imageTransition")
        }
    }
}
#endif

// MARK: - Misc

/// An enum representing either a success with a result value, or a failure.
public enum Result<T> {
    case success(T), failure(Error)

    /// Returns a `value` if the result is success.
    public var value: T? {
        if case let .success(val) = self { return val } else { return nil }
    }

    /// Returns an `error` if the result is failure.
    public var error: Error? {
        if case let .failure(err) = self { return err } else { return nil }
    }
}
