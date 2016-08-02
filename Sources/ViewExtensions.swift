// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
    public typealias ImageView = NSImageView
#else
    import UIKit
    public typealias ImageView = UIImageView
#endif

/// By adopting `ResponseHandling` protocol the class automatically gets a bunch
/// of methods for loading images from the `ResponseHandling` extension.
public protocol ResponseHandling: class {
    /// Called when the current task is completed.
    func nk_handle(response: PromiseResolution<Image>, isFromMemoryCache: Bool)
}

/// Extends `ResponseHandling` with a bunch of methods for loading images.
public extension ResponseHandling {
    /// Cancels the current task. The completion handler doesn't get called.
    public func nk_cancelLoading() {
        nk_context.cancel()
    }
    
    /// Loads an image for the given URL and displays it when finished.
    /// For more info see `nk_setImage(with:options:)` method.
    public func nk_setImage(with url: URL) {
        nk_setImage(with: Request(url: url))
    }

    /// Loads an image for the given request and displays it when finished.
    /// Cancels previously started requests.
    ///
    /// If the image is stored in the context's memory cache, the image is
    /// displayed immediately. Otherwise the image is loaded using the `Loader`
    /// instance and is displayed when finished.
    public func nk_setImage(with request: Request, options: CachingOptions = CachingOptions()) {
        let ctx = nk_context
        
        ctx.cancel()
        
        if options.memoryCachePolicy == .returnCachedObjectElseLoad,
            let image = ctx.cache?.image(for: request) {
            ctx.handler?(response: .fulfilled(image), isFromMemoryCache: true)
        } else {
            let requestId = ctx.nextRequestId
            let cts = CancellationTokenSource()
            _ = ctx.loader.loadImage(with: request, token: cts.token)
                .then {
                    if options.memoryCacheStorageAllowed {
                        ctx.cache?.setImage($0, for: request)
                    }
                }
                .completion { resolution in
                    guard requestId == ctx.requestId else { return }
                    ctx.handler?(response: resolution, isFromMemoryCache: false)
            }
            ctx.cts = cts
        }
    }

    /// Returns the context associated with the receiver.
    public var nk_context: ViewContext {
        if let ctx = objc_getAssociatedObject(self, &contextAK) as? ViewContext {
            return ctx
        }
        let ctx = ViewContext()
        ctx.handler = { [weak self] in
            self?.nk_handle(response: $0, isFromMemoryCache: $1)
        }
        objc_setAssociatedObject(self, &contextAK, ctx, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return ctx
    }
}

/// A set of options affecting how `ViewExtension` deliveres an image.
public struct CachingOptions {
    /// Defines the way `Loader` interacts with the memory cache.
    public enum MemoryCachePolicy {
        /// Return memory cached image corresponding the request.
        /// If there is no existing image in the memory cache,
        /// the image manager continues with the request.
        case returnCachedObjectElseLoad
        
        /// Reload using ignoring memory cached objects.
        case reloadIgnoringCachedObject
    }
    
    /// Specifies whether loaded object should be stored into memory cache.
    /// `true` be default.
    public var memoryCacheStorageAllowed = true
    
    /// `.returnCachedObjectElseLoad` by default.
    public var memoryCachePolicy = MemoryCachePolicy.returnCachedObjectElseLoad
    
    public init() {}
}

private var contextAK = "nk_context"

/// Default implementation of `ResponseHandling` protocol for `ImageView`.
extension ImageView: ResponseHandling {
    /// Simply displays an image on success and runs `opacity` transition if
    /// the response was not from the memory cache.
    ///
    /// To customize response handling you should either override this method
    /// in the subclass, or set a `handler` on the context (`nk_context`).
    public func nk_handle(response: PromiseResolution<Image>, isFromMemoryCache: Bool) {
        switch response {
        case let .fulfilled(image):
            self.image = image
            if !isFromMemoryCache {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.duration = 0.25
                animation.fromValue = 0
                animation.toValue = 1
                let layer: CALayer? = self.layer // Make compiler happy on OSX
                layer?.add(animation, forKey: "imageTransition")
            }
        case .rejected(_): return
        }
    }
}

/// Execution context used by `ResponseHandling` extension.
public final class ViewContext {
    public typealias Handler = (response: PromiseResolution<Image>, isFromMemoryCache: Bool) -> Void
    
    /// Current cancellation token.
    public private(set) var cts: CancellationTokenSource?

    /// Gets incremented for each subsequent request.
    public var requestId = 0
    public var nextRequestId: Int {
        requestId += 1
        return requestId
    }

    /// Called when the current task is completed.
    public var handler: Handler?
    
    /// `Loader.shared` by default.
    public var loader: Loading = Loader.shared
    
    /// `Cache.shared` by default.
    public var cache: Caching? = Cache.shared

    /// Cancels current task.
    deinit {
        cancel()
    }

    /// Cancels the current task. The completion handler doesn't get called.
    public func cancel() {
        cts?.cancel()
        cts = nil
    }

    /// Initializes `ViewContext`.
    public init() {}
}
