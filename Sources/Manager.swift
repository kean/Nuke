// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Manages execution of the requests into arbitrary targets.
public class Manager {
    public let loader: Loading
    public let cache: Caching?
    
    /// Initializes the `Manager` with the given image loader and memory cache.
    public init(loader: Loading, cache: Caching? = nil) {
        self.loader = loader
        self.cache = cache
    }
    
    /// Asynchronously fulfills the request into the given target.
    /// Cancels previous request started for the given target.
    ///
    /// `Manager` keeps a weak reference to the target. If the target deallocates
    /// the associated request automatically gets cancelled.
    ///
    /// If the image is stored in the memory cache, the image is displayed
    /// immediately. The image is loaded using the `Loading` object otherwise.
    public func loadImage(with request: Request, into target: Target) {
        loadImage(with: request, into: target) { [weak target] in
            target?.handle(response: $0, isFromMemoryCache: $1)
        }
    }
    
    public typealias Handler = (Resolution<Image>, _ isFromMemoryCache: Bool) -> Void
    
    /// Asynchronously fulfills the request into the given target and calls
    /// the `handler`. The handler gets called only if the request is still
    /// associated with the target by the time the request is completed.
    ///
    /// See `loadImage(with:into:)` method for more info.
    public func loadImage(with request: Request, into target: AnyObject, handler: Handler) {
        assert(Thread.isMainThread)
        
        // Cancel existing request
        cancelRequest(for: target)
        
        // Quick memory cache lookup
        if request.memoryCacheOptions.readAllowed, let image = cache?[request] {
            handler(.fulfilled(image), true)
        } else {
            let ctx = Context()
            Manager.setContext(ctx, for: target)
            
            loader.loadImage(with: request, token: ctx.cts.token).completion { [weak ctx, weak target] in
                guard let ctx = ctx, let target = target else { return }
                guard Manager.getContext(for: target) === ctx else { return }
                handler($0, false)
            }
        }
    }
    
    /// Cancels the request which is currently associated with the target.
    public func cancelRequest(for target: AnyObject) {
        assert(Thread.isMainThread)
        if let context = Manager.getContext(for: target) {
            context.cts.cancel()
            Manager.setContext(nil, for: target)
        }
    }
    
    // Associated objects is a simplest way to bind Context and Target lifetimes
    // The implementation might change in the future.
    private static func getContext(for target: AnyObject) -> Context? {
        return objc_getAssociatedObject(target, &contextAK) as? Context
    }
    
    private static func setContext(_ context: Context?, for target: AnyObject) {
        objc_setAssociatedObject(target, &contextAK, context, .OBJC_ASSOCIATION_RETAIN)
    }
    
    private final class Context {
        let cts = CancellationTokenSource()
        
        deinit {
            if !cts.isCancelling {
                cts.cancel()
            }
        }
    }
}

private var contextAK = "Manager.Context.AssociatedKey"

public extension Manager {
    public func loadImage(with url: URL, into target: Target) {
        loadImage(with: Request(url: url), into: target)
    }
}

/// Represents an arbitrary target for image loading.
public protocol Target: class {
    /// Callback that gets called when the request gets completed.
    func handle(response: Resolution<Image>, isFromMemoryCache: Bool)
}

#if os(macOS)
    import Cocoa
    public typealias ImageView = NSImageView
#elseif os(iOS) || os(tvOS)
    import UIKit
    public typealias ImageView = UIImageView
#endif


#if os(macOS) || os(iOS) || os(tvOS)
    
    /// Default implementation of `Target` protocol for `ImageView`.
    extension ImageView: Target {
        /// Displays an image on success. Runs `opacity` transition if
        /// the response was not from the memory cache.
        public func handle(response: Resolution<Image>, isFromMemoryCache: Bool) {
            switch response {
            case let .fulfilled(image):
                self.image = image
                if !isFromMemoryCache {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.duration = 0.25
                    animation.fromValue = 0
                    animation.toValue = 1
                    let layer: CALayer? = self.layer // Make compiler happy on macOS
                    layer?.add(animation, forKey: "imageTransition")
                }
            case .rejected(_): return
            }
        }
    }
    
#endif
