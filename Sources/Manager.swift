// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads images into the given targets.
public final class Manager {
    public let loader: Loading

    /// Shared `Manager` instance.
    ///
    /// Shared manager is created with `Loader.shared`.
    public static let shared = Manager(loader: Loader.shared)

    /// Initializes the `Manager` with an image loader.
    public init(loader: Loading) {
        self.loader = loader
    }

    // MARK: Loading Images into Targets

    /// Loads an image into the given target. Cancels previous outstanding request
    /// associated with the target.
    ///
    /// If the image is stored in the memory cache, the image is displayed
    /// immediately. The image is loaded using the `loader` object otherwise.
    ///
    /// `Manager` keeps a weak reference to the target. If the target deallocates
    /// the associated request automatically gets cancelled.
    public func loadImage(with request: Request, into target: Target) {
        loadImage(with: request, into: target) { [weak target] in
            target?.handle(response: $0, isFromMemoryCache: $1)
        }
    }

    public typealias Handler = (Result<Image>, _ isFromMemoryCache: Bool) -> Void

    /// Loads an image and calls the given `handler`. The method itself 
    /// **doesn't do** anything when the image is loaded - you have full
    /// control over how to display it, etc.
    ///
    /// The handler only gets called if the request is still associated with the
    /// `target` by the time it's completed. The handler gets called immediately
    /// if the image was stored in the memory cache.
    ///
    /// See `loadImage(with:into:)` method for more info.
    public func loadImage(with request: Request, into target: AnyObject, handler: @escaping Handler) {
        assert(Thread.isMainThread)

        let context = getContext(for: target)
        context.cts?.cancel() // cancel outstanding request if any
        context.cts = nil

        // Quick synchronous memory cache lookup
        if let image = loader.cachedImage(for: request) {
            handler(.success(image), true)
            return
        }

        // Create CTS and associate it with a context
        let cts = CancellationTokenSource()
        context.cts = cts

        // Start the request
        // Manager assumes that Loader calls completion on the main thread.
        loader.loadImage(with: request, token: cts.token) { [weak context] in
            guard let context = context, context.cts === cts else { return } // check if still registered
            handler($0, false)
            context.cts = nil // avoid redundant cancellations on deinit
        }
    }

    /// Cancels an outstanding request associated with the target.
    public func cancelRequest(for target: AnyObject) {
        assert(Thread.isMainThread)
        let context = getContext(for: target)
        context.cts?.cancel() // cancel outstanding request if any
        context.cts = nil // unregister request
    }

    // MARK: Managing Context

    private static var contextAK = "Manager.Context.AssociatedKey"

    // Lazily create context for a given target and associate it with a target.
    private func getContext(for target: AnyObject) -> Context {
        // Associated objects is a simplest way to bind Context and Target lifetimes
        // The implementation might change in the future.
        if let ctx = objc_getAssociatedObject(target, &Manager.contextAK) as? Context {
            return ctx
        }
        let ctx = Context()
        objc_setAssociatedObject(target, &Manager.contextAK, ctx, .OBJC_ASSOCIATION_RETAIN)
        return ctx
    }

    // Context is reused for multiple requests which makes sense, because in
    // most cases image views are also going to be reused (e.g. in a table view)
    private final class Context {
        var cts: CancellationTokenSource? // also used to identify requests

        // Automatically cancel the request when target deallocates.
        deinit { cts?.cancel() }
    }
}

public extension Manager {
    /// Loads an image into the given target. See the corresponding
    /// `loadImage(with:into)` method that takes `Request` for more info.
    public func loadImage(with url: URL, into target: Target) {
        loadImage(with: Request(url: url), into: target)
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
    public func loadImage(with url: URL, into target: AnyObject, handler: @escaping Handler) {
        loadImage(with: Request(url: url), into: target, handler: handler)
    }
}

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
