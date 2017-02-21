// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads images into the given targets.
public final class Manager: Loading {
    public let loader: Loading
    public let cache: Caching?

    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Manager")
    
    /// Shared `Manager` instance.
    ///
    /// Shared manager is created with `Loader.shared` and `Cache.shared`.
    public static let shared = Manager(loader: Loader.shared, cache: Cache.shared)
    
    /// Initializes the `Manager` with the image loader and the memory cache.
    /// - parameter cache: `nil` by default.
    public init(loader: Loading, cache: Caching? = nil) {
        self.loader = loader
        self.cache = cache
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
        
        // Cancel outstanding request if any
        cancelRequest(for: target)
        
        // Quick synchronous memory cache lookup
        if let image = cachedImage(for: request) {
            handler(.success(image), true)
            return
        }
        
        // Create context and associate it with a target
        let cts = CancellationTokenSource(lock: CancellationTokenSource.lock)
        let context = Context(cts)
        Manager.setContext(context, for: target)
        
        // Start the request
        loadImage(with: request, token: cts.token) { [weak context, weak target] in
            guard let context = context, let target = target else { return }
            guard Manager.getContext(for: target) === context else { return }
            handler($0, false)
            context.cts = nil // Avoid redundant cancellations on deinit
        }
    }

    /// Cancels an outstanding request associated with the target.
    public func cancelRequest(for target: AnyObject) {
        assert(Thread.isMainThread)
        if let context = Manager.getContext(for: target) {
            context.cts?.cancel()
            Manager.setContext(nil, for: target)
        }
    }

    // MARK: Loading Images w/o Targets

    /// Loads an image with a given request by using manager's cache and loader.
    ///
    /// - parameter completion: Gets called asynchronously on the main thread.
    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            if token?.isCancelling == true { return } // Fast preflight check
            self._loadImage(with: request, token: token) { result in
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    private func _loadImage(with request: Request, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        // Check if image is in memory cache
        if let image = cachedImage(for: request) {
            completion(.success(image))
        } else {
            // Use underlying loader to load an image and then store it in cache
            loader.loadImage(with: request, token: token) { [weak self] in
                if let image = $0.value {
                    self?.store(image: image, for: request)
                }
                completion($0)
            }
        }
    }

    // MARK: Memory Cache Helpers

    private func cachedImage(for request: Request) -> Image? {
        guard request.memoryCacheOptions.readAllowed else { return nil }
        return cache?[request]
    }

    private func store(image: Image, for request: Request) {
        guard request.memoryCacheOptions.writeAllowed else { return }
        cache?[request] = image
    }

    // MARK: Managing Context

    private static var contextAK = "Manager.Context.AssociatedKey"
    
    // Associated objects is a simplest way to bind Context and Target lifetimes
    // The implementation might change in the future.
    private static func getContext(for target: AnyObject) -> Context? {
        return objc_getAssociatedObject(target, &contextAK) as? Context
    }
    
    private static func setContext(_ context: Context?, for target: AnyObject) {
        objc_setAssociatedObject(target, &contextAK, context, .OBJC_ASSOCIATION_RETAIN)
    }
    
    private final class Context {
        var cts: CancellationTokenSource?
        
        init(_ cts: CancellationTokenSource) { self.cts = cts }
        
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

/// Represents an arbitrary target for image loading.
public protocol Target: class {
    /// Callback that gets called when the request gets completed.
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
