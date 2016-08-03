// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: Manager

public class Manager {
    public let loader: Loading
    public let cache: Caching?
    private var map = [TargetKey: Context]()
    
    public init(loader: Loading, cache: Caching? = nil) {
        self.loader = loader
        self.cache = cache
    }
    
    public typealias Handler = (response: Resolution<Image>, isFromMemoryCache: Bool) -> Void
    
    /// Loads an image for the given request and displays it when finished.
    /// Cancels previously started requests.
    ///
    /// If the image is stored in the context's memory cache, the image is
    /// displayed immediately. Otherwise the image is loaded using the `Loader`
    /// instance and is displayed when finished.
    public func loadImage(with request: Request, into target: Target, handler: Handler? = nil) {
        assert(Thread.isMainThread)
        
        let handler = handler ?? { target.handle(response: $0, isFromMemoryCache: $1) }
        
        // Cancel existing request.
        cancelRequest(for: target)
        
        // Quick memory cache lookup
        if request.memoryCacheOptions.readAllowed, let image = cache?.image(for: request) {
            handler(response: .fulfilled(image), isFromMemoryCache: true)
        } else {
            let key = TargetKey(target: target)
            let ctx = Context()
            map[key] = ctx
            
            loader.loadImage(with: request, token: ctx.cts.token).completion { [weak self] in
                guard self?.map[key] === ctx else { return }
                handler(response: $0, isFromMemoryCache: false)
                self?.map[key] = nil
            }
        }
    }
    
    public func cancelRequest(for target: Target) {
        assert(Thread.isMainThread)
        let key = TargetKey(target: target)
        if let ctx = map[key] {
            ctx.cts.cancel()
            map[key] = nil
        }
    }
    
    private struct TargetKey: Hashable {
        let target: Target
        private var hashValue: Int {
            return unsafeAddress(of: target).hashValue
        }
        static func ==(lhs: TargetKey, rhs: TargetKey) -> Bool {
            return lhs.target === rhs.target
        }
    }
    
    private final class Context {
        let cts = CancellationTokenSource()
    }
}

public extension Manager {
    public func loadImage(with url: URL, into target: Target) {
        loadImage(with: Request(url: url), into: target)
    }
}

// MARK: Target

#if os(OSX)
    import Cocoa
    public typealias ImageView = NSImageView
#else
    import UIKit
    public typealias ImageView = UIImageView
#endif

/// By adopting `Target` protocol the class automatically gets a bunch
/// of methods for loading images from the `Target` extension.

/// Represents an arbitrary target for image loading.
public protocol Target: class {
    /// Called when the current task is completed.
    func handle(response: Resolution<Image>, isFromMemoryCache: Bool)
}

/// Default implementation of `Target` protocol for `ImageView`.
extension ImageView: Target {
    /// Simply displays an image on success and runs `opacity` transition if
    /// the response was not from the memory cache.
    ///
    /// To customize response handling you should either override this method
    /// in the subclass, or set a `handler` on the context (`nk_context`).
    public func handle(response: Resolution<Image>, isFromMemoryCache: Bool) {
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
