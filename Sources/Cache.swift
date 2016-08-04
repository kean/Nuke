// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

/// Provides in-memory storage for images.
///
/// The implementation is expected to be thread safe.
public protocol Caching {
    /// Returns an image for the request.
    func image(for request: Request) -> Image?

    /// Stores the image for the request.
    func setImage(_ image: Image, for request: Request)
}

/// Auto purging memory cache that uses `NSCache` as its internal storage.
public class Cache: Caching {
    deinit {
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.removeObserver(self)
        #endif
    }
    
    // MARK: Configuring Cache
    
    /// The internal memory cache.
    public let cache: NSCache<AnyObject, AnyObject>

    private let equator: RequestEquating

    /// Initializes the receiver with a given memory cache.
    public init(cache: NSCache<AnyObject, AnyObject> = Cache.makeDefaultCache(), equator: RequestEquating = RequestCachingEquator()) {
        self.cache = cache
        self.equator = equator
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMemoryWarning(_:)), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
        #endif
    }
    
    /// Initializes cache with the recommended cache total limit.
    private static func makeDefaultCache() -> NSCache<AnyObject, AnyObject> {
        let cache = NSCache<AnyObject, AnyObject>()
        cache.totalCostLimit = {
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2
            let limit = physicalMemory / UInt64(1 / ratio)
            return limit > UInt64(Int.max) ? Int.max : Int(limit)
        }()
        return cache
    }
    
    // MARK: Managing Cached Images

    /// Returns an image for the request.
    public func image(for request: Request) -> Image? {
        return cache.object(forKey: makeKey(for: request)) as? Image
    }

    /// Stores the image for the request.
    public func setImage(_ image: Image, for request: Request) {
        cache.setObject(image, forKey: makeKey(for: request), cost: cost(for: image))
    }

    /// Removes an image for the request.
    public func removeImage(for request: Request) {
        cache.removeObject(forKey: makeKey(for: request))
    }

    private func makeKey(for request: Request) -> RequestKey {
        return RequestKey(request, equator: equator)
    }

    // MARK: Subclassing Hooks
    
    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    public func cost(for image: Image) -> Int {
        #if os(OSX)
            return 1
        #else
            guard let cgImage = image.cgImage else { return 1 }
            return cgImage.bytesPerRow * cgImage.height
        #endif
    }
    
    dynamic private func didReceiveMemoryWarning(_ notification: Notification) {
        cache.removeAllObjects()
    }
}
