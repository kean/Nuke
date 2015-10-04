// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

public protocol ImageMemoryCaching {
    func cachedResponseForKey(key: ImageRequestKey) -> ImageCachedResponse?
    func storeResponse(response: ImageCachedResponse, forKey key: ImageRequestKey)
    func removeAllCachedImages()
}

public class ImageCachedResponse {
    public let image: UIImage
    public let userInfo: Any?

    public init(image: UIImage, userInfo: Any?) {
        self.image = image
        self.userInfo = userInfo
    }
}

public class ImageMemoryCache: ImageMemoryCaching {
    public let cache: NSCache

    deinit {
        #if os(iOS)
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        #endif
    }

    public init(cache: NSCache) {
        self.cache = cache
        #if os(iOS)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("didReceiveMemoryWarning:"), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        #endif
    }

    public convenience init() {
        let cache = NSCache()
        cache.totalCostLimit = ImageMemoryCache.recommendedCacheTotalLimit()
        self.init(cache: cache)
    }

    public func cachedResponseForKey(key: ImageRequestKey) -> ImageCachedResponse? {
        return self.cache.objectForKey(key) as? ImageCachedResponse
    }
    
    public func storeResponse(response: ImageCachedResponse, forKey key: ImageRequestKey) {
        self.cache.setObject(response, forKey: key, cost: self.costForImage(response.image))
    }

    public func costForImage(image: UIImage) -> Int {
        let imageRef = image.CGImage
        let bits = CGImageGetWidth(imageRef) * CGImageGetHeight(imageRef) * CGImageGetBitsPerPixel(imageRef)
        return bits / 8
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
