// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#if WATCHKIT
  import WatchKit
  #else
  import Foundation
#endif

public protocol ImageMemoryCaching {
    func cachedImage(key: AnyObject) -> UIImage?
    func storeImage(image: UIImage, key: AnyObject)
}

public class ImageMemoryCache: ImageMemoryCaching {
    public let cache: NSCache
    
    deinit {
#if WATCHKIT
#else
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
#endif
    }
    
    public init(cache: NSCache) {
        self.cache = cache
#if WATCHKIT
#else
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("didReceiveMemoryWarning:"), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
#endif
    }
    
    public convenience init() {
        let cache = NSCache()
        cache.totalCostLimit = ImageMemoryCache.recommendedCacheTotalLimit()
        self.init(cache: cache)
    }
    
    public func cachedImage(key: AnyObject) -> UIImage? {
        let object: AnyObject? = self.cache.objectForKey(key)
        return object as? UIImage
    }
    
    public func storeImage(image: UIImage, key: AnyObject) {
        let cost = self.costForImage(image)
        self.cache.setObject(image, forKey: key, cost: cost)
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
