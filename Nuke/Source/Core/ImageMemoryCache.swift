// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

public protocol ImageMemoryCaching {
    func cachedResponseForKey(key: ImageRequestKey) -> ImageCachedResponse?
    func storeResponse(response: ImageCachedResponse, forKey key: ImageRequestKey)
    func removeAllCachedImages()
}

public class ImageCachedResponse {
    public let image: Image

    /** User info returned by the image loader (see ImageLoading protocol).
     */
    public let userInfo: Any?

    public init(image: Image, userInfo: Any?) {
        self.image = image
        self.userInfo = userInfo
    }
}

/** Auto purging memory cache.
*/
public class ImageMemoryCache: ImageMemoryCaching {
    public let cache: NSCache

    deinit {
        #if os(iOS) || os(tvOS)
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        #endif
    }

    public init(cache: NSCache) {
        self.cache = cache
        #if os(iOS) || os(tvOS)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("didReceiveMemoryWarning:"), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        #endif
    }

    /** Initializes cache with the recommended cache total limit.
     */
    public convenience init() {
        let cache = NSCache()
        cache.totalCostLimit = ImageMemoryCache.recommendedCacheTotalLimit()
        #if os(OSX)
            cache.countLimit = 100
        #endif
        self.init(cache: cache)
    }

    public func cachedResponseForKey(key: ImageRequestKey) -> ImageCachedResponse? {
        return self.cache.objectForKey(key) as? ImageCachedResponse
    }
    
    public func storeResponse(response: ImageCachedResponse, forKey key: ImageRequestKey) {
        self.cache.setObject(response, forKey: key, cost: self.costForImage(response.image))
    }

    public func costForImage(image: Image) -> Int {
        #if os(OSX)
            return 1
        #else
            let imageRef = image.CGImage
            let bits = CGImageGetWidth(imageRef) * CGImageGetHeight(imageRef) * CGImageGetBitsPerPixel(imageRef)
            return bits / 8
        #endif
    }

    public class func recommendedCacheTotalLimit() -> Int {
        let physicalMemory = Double(NSProcessInfo.processInfo().physicalMemory)
        let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory * ratio
        return limit > Double(Int.max) ? Int.max : Int(limit)
    }

    public func removeAllCachedImages() {
        self.cache.removeAllObjects()
    }

    @objc private func didReceiveMemoryWarning(notification: NSNotification) {
        self.cache.removeAllObjects()
    }
}
