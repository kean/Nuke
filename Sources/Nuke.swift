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

// MARK: - Loading Images

/// Loads an image into the given target. See the corresponding
/// `loadImage(with:into)` method that takes `Request` for more info.
public func loadImage(with url: URL, pipeline: ImagePipeline = ImagePipeline.shared, into target: Target) {
    loadImage(with: Request(url: url), pipeline: pipeline, into: target)
}

/// Loads an image into the given target. Cancels previous outstanding request
/// associated with the target.
///
/// If the image is stored in the memory cache, the image is displayed
/// immediately. The image is loaded using the `loader` object otherwise.
///
/// `Manager` keeps a weak reference to the target. If the target deallocates
/// the associated request automatically gets cancelled.
public func loadImage(with request: Request, pipeline: ImagePipeline = ImagePipeline.shared, into target: Target) {
    loadImage(with: request, pipeline: pipeline, into: target) { [weak target] in
        target?.handle(response: $0, isFromMemoryCache: $1)
    }
}

/// Loads an image and calls the given `handler`. The method itself
/// **doesn't do** anything when the image is loaded - you have full
/// control over how to display it, etc.
///
/// The handler only gets called if the request is still associated with the
/// `target` by the time it's completed. The handler gets called immediately
/// if the image was stored in the memory cache.
///
/// See `loadImage(with:into:)` method for more info.
public func loadImage(with url: URL, pipeline: ImagePipeline = ImagePipeline.shared, into target: AnyObject, handler: @escaping (Result<Image>, _ isFromMemoryCache: Bool) -> Void) {
    loadImage(with: Request(url: url), pipeline: pipeline, into: target, handler: handler)
}

/// Loads an image and calls the given `handler`. The method itself
/// **doesn't do** anything when the image is loaded - you have full
/// control over how to display it, etc.
///
/// The handler only gets called if the request is still associated with the
/// `target` by the time it's completed. The handler gets called immediately
/// if the image was stored in the memory cache.
///
/// See `loadImage(with:into:)` method for more info.
public func loadImage(with request: Request, pipeline: ImagePipeline = ImagePipeline.shared, into target: AnyObject, handler: @escaping (Result<Image>, _ isFromMemoryCache: Bool) -> Void) {
    assert(Thread.isMainThread)

    let context = getContext(for: target)
    context.task?.cancel() // cancel outstanding request if any
    context.task = nil

    // Quick synchronous memory cache lookup
    if let image = pipeline.cachedImage(for: request) {
        handler(.success(image), true)
        return
    }

    // Create ID to check whether the active request hasn't changed while downloading
    context.taskId += 1
    let taskId = context.taskId

    // Start the request
    // Manager assumes that Loader calls completion on the main thread.
    context.task = pipeline.loadImage(with: request) { [weak context] in
        // Check if still registered
        guard let context = context, context.taskId == taskId else { return }
        handler($0, false)
        context.task = nil // avoid redundant cancellations on deinit
    }
}

/// Cancels an outstanding request associated with the target.
public func cancelRequest(for target: AnyObject) {
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
    var task: ImageTask? // also used to identify requests
    var taskId: Int = 0

    // Automatically cancel the request when target deallocates.
    deinit { task?.cancel() }

    static var contextAK = "Context.AssociatedKey"
}

// MARK: - Target

/// Represents a target for image loading.
public protocol Target: class {
    /// Callback that gets called when the request is completed.
    func handle(response: Result<Image>, isFromMemoryCache: Bool)
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
/// Default implementation of `Target` protocol for `ImageView`.
extension ImageView: Target {
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

// MARK: - Result

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
