// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

/// Provides in-memory storage for image responses.
public protocol ImageMemoryCaching {
    /// Returns the cached response for the specified key.
    func responseForKey(key: ImageRequestKey) -> ImageCachedResponse?

    /// Stores the cached response for the specified key.
    func setResponse(response: ImageCachedResponse, forKey key: ImageRequestKey)

    /// Removes the cached response for the specified key.
    func removeResponseForKey(key: ImageRequestKey)
    
    /// Clears the receiver's storage.
    func clear()
}

/// Represents a cached image response.
public class ImageCachedResponse {
    /// The image that the receiver was initialized with.
    public let image: Image

    /// User info returned by the image loader (see ImageLoading protocol).
    public let userInfo: Any?

    /// Initializes the receiver with a given image and user info.
    public init(image: Image, userInfo: Any?) {
        self.image = image
        self.userInfo = userInfo
    }
}

/// Auto purging memory cache that uses NSCache as its internal storage.
public class ImageMemoryCache: ImageMemoryCaching {
    deinit {
        #if os(iOS) || os(tvOS)
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        #endif
    }
    
    // MARK: Configuring Cache
    
    /// The internal memory cache.
    public let cache: NSCache

    /// Initializes the receiver with a given memory cache.
    public init(cache: NSCache) {
        self.cache = cache
        #if os(iOS) || os(tvOS)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ImageMemoryCache.didReceiveMemoryWarning(_:)), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        #endif
    }

    /// Initializes cache with the recommended cache total limit.
    public convenience init() {
        let cache = NSCache()
        cache.totalCostLimit = ImageMemoryCache.recommendedCostLimit()
        #if os(OSX)
            cache.countLimit = 100
        #endif
        self.init(cache: cache)
    }
    
    /// Returns recommended cost limit in bytes.
    public class func recommendedCostLimit() -> Int {
        let physicalMemory = NSProcessInfo.processInfo().physicalMemory
        let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory / UInt64(1 / ratio)
        return limit > UInt64(Int.max) ? Int.max : Int(limit)
    }
    
    // MARK: Managing Cached Responses

    /// Returns the cached response for the specified key.
    public func responseForKey(key: ImageRequestKey) -> ImageCachedResponse? {
        return cache.objectForKey(key) as? ImageCachedResponse
    }

    /// Stores the cached response for the specified key.
    public func setResponse(response: ImageCachedResponse, forKey key: ImageRequestKey) {
        cache.setObject(response, forKey: key, cost: costFor(response.image))
    }

    /// Removes the cached response for the specified key.
    public func removeResponseForKey(key: ImageRequestKey) {
        cache.removeObjectForKey(key)
    }
    
    /// Removes all cached images.
    public func clear() {
        cache.removeAllObjects()
    }

    // MARK: Subclassing Hooks
    
    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    public func costFor(image: Image) -> Int {
        #if os(OSX)
            return 1
        #else
            return CGImageGetBytesPerRow(image.CGImage) * CGImageGetHeight(image.CGImage)
        #endif
    }
    
    @objc private func didReceiveMemoryWarning(notification: NSNotification) {
        cache.removeAllObjects()
    }
}
