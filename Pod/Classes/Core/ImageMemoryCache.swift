// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public protocol ImageMemoryCaching {
    func cachedResponseForKey(key: AnyObject) -> CachedImageResponse?
    func storeResponse(response: CachedImageResponse, forKey key: AnyObject)
}

public class CachedImageResponse {
    public let image: UIImage
    public let info: NSDictionary?
    
    public init(image: UIImage, info: NSDictionary?) {
        self.image = image
        self.info = info
    }
}

public class ImageMemoryCache: ImageMemoryCaching {
    public let cache: NSCache
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
    }
    
    public init(cache: NSCache) {
        self.cache = cache
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("didReceiveMemoryWarning:"), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
    }
    
    public convenience init() {
        let cache = NSCache()
        cache.totalCostLimit = ImageMemoryCache.recommendedCacheTotalLimit()
        self.init(cache: cache)
    }
    
    public func cachedResponseForKey(key: AnyObject) -> CachedImageResponse? {
        let object: AnyObject? = self.cache.objectForKey(key)
        return object as? CachedImageResponse
    }
    
    public func storeResponse(response: CachedImageResponse, forKey key: AnyObject) {
        let cost = self.costForImage(response.image)
        self.cache.setObject(response, forKey: key, cost: cost)
    }
    
    public func costForImage(image: UIImage) -> Int {
        let imageRef = image.CGImage
        let bits = CGImageGetWidth(imageRef) * CGImageGetHeight(imageRef) * CGImageGetBitsPerPixel(imageRef)
        return bits / 8
    }
    
    public class func recommendedCacheTotalLimit() -> Int {
        let physicalMemory = NSProcessInfo.processInfo().physicalMemory
        let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2;
        return Int(Double(physicalMemory) * ratio)
    }
    
    @objc private func didReceiveMemoryWarning(notification: NSNotification) {
        self.cache.removeAllObjects()
    }
}
